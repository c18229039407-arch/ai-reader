import 'dart:typed_data';

import 'package:epubx/epubx.dart';

/// 章节的纯文本视图（spike 用：验证解析与中文排版，不追求富文本还原）。
class ChapterText {
  ChapterText({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

class LoadedBook {
  LoadedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.coverBytes,
  });

  final String title;
  final String author;
  final List<ChapterText> chapters;

  /// EPUB 内嵌封面图（原始字节，可能为 null）。
  final Uint8List? coverBytes;
}

// —— 阅读噪音过滤（主要针对维基文库 WSExport 导出的 EPUB）——
// 每章开头会残留「目錄 / ◀上一章 / 下一章▶」导航条与「以…从维基文库导出」说明。
final _navNoise = RegExp(r'^(目錄|目录|◀?\s*上一章|下一章\s*▶?|↑|返回)$');
final _exportNote = RegExp(r'从维基文库导出|從維基文庫導出|↑?\s*Exported from Wikisource');
final _aboutPage = RegExp(r'Wsexport|About this digital edition');

List<String> _cleanParagraphs(List<String> paras, String bookTitle) => paras
    .where((p) =>
        !_navNoise.hasMatch(p) &&
        !_exportNote.hasMatch(p) &&
        p != bookTitle)
    .toList();

/// 站标/图标类图片不能当封面（维基文库 EPUB 里唯一的图就是它的冰山 logo）。
final _notCoverName = RegExp(r'logo|icon|badge|emblem|symbol|wikisource|ornament',
    caseSensitive: false);

/// 从 EPUB 内嵌图片里挑封面：优先文件名含 cover，否则取最大的一张；
/// 小于 8KB 的（装饰图）与站标类命名（logo 等）不当封面。
Uint8List? _pickCover(EpubBook book) {
  final images = book.Content?.Images;
  if (images == null || images.isEmpty) return null;
  MapEntry<String, EpubByteContentFile>? best;
  for (final e in images.entries) {
    if (_notCoverName.hasMatch(e.key)) continue;
    final len = e.value.Content?.length ?? 0;
    if (e.key.toLowerCase().contains('cover') && len > 8 * 1024) {
      best = e;
      break;
    }
    if (len > (best?.value.Content?.length ?? 0)) best = e;
  }
  final bytes = best?.value.Content;
  if (bytes == null || bytes.length < 8 * 1024) return null;
  return Uint8List.fromList(bytes);
}

/// 解析 EPUB 字节流为纯文本章节列表。
Future<LoadedBook> loadEpub(Uint8List bytes) async {
  final book = await EpubReader.readBook(bytes);
  final chapters = <ChapterText>[];
  final bookTitle = (book.Title ?? '').trim();

  void walk(List<EpubChapter> list, int depth) {
    for (final ch in list) {
      final raw = _htmlToParagraphs(ch.HtmlContent ?? '');
      final text = _cleanParagraphs(raw, bookTitle);
      // 过滤 WSExport 的 about 页与清理后已无内容的封面/空页
      final isAbout = raw.take(3).any(_aboutPage.hasMatch) ||
          _aboutPage.hasMatch(ch.Title ?? '');
      if (text.isNotEmpty && !isAbout) {
        chapters.add(
          ChapterText(title: (ch.Title ?? '未命名章节').trim(), paragraphs: text),
        );
      }
      if (ch.SubChapters != null && ch.SubChapters!.isNotEmpty) {
        walk(ch.SubChapters!, depth + 1);
      }
    }
  }

  walk(book.Chapters ?? [], 0);

  // 部分 EPUB 目录为空但正文在 Content 里；兜底：直接读 spine 的 HTML 文件。
  if (chapters.isEmpty) {
    final htmlFiles = book.Content?.Html?.values ?? [];
    var i = 1;
    for (final f in htmlFiles) {
      final text = _cleanParagraphs(_htmlToParagraphs(f.Content ?? ''), bookTitle);
      if (text.isNotEmpty) {
        chapters.add(ChapterText(title: '第 $i 节', paragraphs: text));
        i++;
      }
    }
  }

  return LoadedBook(
    title: book.Title ?? '未知书名',
    author: book.Author ?? '未知作者',
    chapters: chapters,
    coverBytes: _pickCover(book),
  );
}

/// 轻量 HTML → 段落文本。spike 级实现：去标签、按块级元素分段、解码常见实体。
List<String> _htmlToParagraphs(String html) {
  var s = html;
  // 去掉 script/style 及其内容
  s = s.replaceAll(
    RegExp(r'<(script|style)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    '',
  );
  // 块级结束标签 → 换行
  s = s.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|blockquote|tr|td|th|section|article)>',
      caseSensitive: false,
    ),
    '\n',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  // 去掉其余标签
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');
  // 常见实体
  const entities = {
    '&nbsp;': ' ',
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&hellip;': '…',
    '&mdash;': '—',
    '&ldquo;': '“',
    '&rdquo;': '”',
    '&lsquo;': '‘',
    '&rsquo;': '’',
  };
  entities.forEach((k, v) => s = s.replaceAll(k, v));
  s = s.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m[1]!)),
  );

  return s
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
