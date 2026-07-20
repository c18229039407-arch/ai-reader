import 'dart:typed_data';

import 'package:epubx/epubx.dart';

/// 段落块类型（轻量富文本：标题分级 / 引用 / 插图）。
enum ParaKind { body, h1, h2, h3, quote, image }

/// 一个段落块：纯文本 + 类型 + 行内加粗/斜体范围（半开区间 [start, end)）。
/// 纯文本层保持不变，高亮 / AI 划选 / 翻译 / 检索的定位机制完全复用。
class ParaBlock {
  ParaBlock({
    required this.text,
    this.kind = ParaKind.body,
    this.image,
    this.bold = const [],
    this.italic = const [],
  });

  final String text;
  final ParaKind kind;

  /// kind == image 时：EPUB 内图片的 src（按文件名在书内图片表里解析）。
  final String? image;

  final List<(int, int)> bold;
  final List<(int, int)> italic;
}

/// 章节的文本视图。paragraphs 与 blocks 平行同长（image 块 text 为空串），
/// 旧代码继续用 paragraphs（字符串层），渲染层用 blocks。
class ChapterText {
  ChapterText({
    required this.title,
    required this.paragraphs,
    List<ParaBlock>? blocks,
  }) : blocks = blocks ?? [for (final p in paragraphs) ParaBlock(text: p)];

  final String title;
  final List<String> paragraphs;
  final List<ParaBlock> blocks;
}

class LoadedBook {
  LoadedBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.coverBytes,
    this.images = const {},
  });

  final String title;
  final String author;
  final List<ChapterText> chapters;

  /// EPUB 内嵌封面图（原始字节，可能为 null）。
  final Uint8List? coverBytes;

  /// 书内插图：文件名（basename 小写）→ 原始字节，渲染用。
  final Map<String, Uint8List> images;
}

// —— 阅读噪音过滤（主要针对维基文库 WSExport 导出的 EPUB）——
final _navNoise = RegExp(r'^(目錄|目录|◀?\s*上一章|下一章\s*▶?|↑|返回)$');
final _exportNote =
    RegExp(r'从维基文库导出|從維基文庫導出|↑?\s*Exported from Wikisource');
final _aboutPage = RegExp(r'Wsexport|About this digital edition');

List<ParaBlock> _cleanBlocks(List<ParaBlock> blocks, String bookTitle) =>
    blocks.where((b) {
      if (b.kind == ParaKind.image) return true;
      return !_navNoise.hasMatch(b.text) &&
          !_exportNote.hasMatch(b.text) &&
          b.text != bookTitle;
    }).toList();

/// 站标/图标类图片不能当封面（维基文库 EPUB 里唯一的图就是它的冰山 logo）。
final _notCoverName = RegExp(
    r'logo|icon|badge|emblem|symbol|wikisource|ornament',
    caseSensitive: false);

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

/// 解析 EPUB 字节流为章节列表（轻量富文本）。
Future<LoadedBook> loadEpub(Uint8List bytes) async {
  final book = await EpubReader.readBook(bytes);
  final chapters = <ChapterText>[];
  final bookTitle = (book.Title ?? '').trim();

  void addChapter(String title, String html) {
    final raw = htmlToBlocks(html);
    final blocks = _cleanBlocks(raw, bookTitle);
    final isAbout = raw.take(3).any((b) => _aboutPage.hasMatch(b.text)) ||
        _aboutPage.hasMatch(title);
    final hasText = blocks.any((b) => b.text.isNotEmpty);
    if (hasText && !isAbout) {
      chapters.add(ChapterText(
        title: title.trim(),
        paragraphs: blocks.map((b) => b.text).toList(),
        blocks: blocks,
      ));
    }
  }

  void walk(List<EpubChapter> list, int depth) {
    for (final ch in list) {
      addChapter(ch.Title ?? '未命名章节', ch.HtmlContent ?? '');
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
      final before = chapters.length;
      addChapter('第 $i 节', f.Content ?? '');
      if (chapters.length > before) i++;
    }
  }

  // 书内插图表：basename（小写）→ 字节
  final images = <String, Uint8List>{};
  for (final e in (book.Content?.Images ?? {}).entries) {
    final data = e.value.Content;
    if (data == null) continue;
    final base = e.key.split('/').last.toLowerCase();
    images[base] = Uint8List.fromList(data);
  }

  return LoadedBook(
    title: book.Title ?? '未知书名',
    author: book.Author ?? '未知作者',
    chapters: chapters,
    coverBytes: _pickCover(book),
    images: images,
  );
}

// ———— HTML → 块级富文本解析 ————
//
// 哨兵（正文不可能出现的控制符，全部用显式 \u 转义）：
//   <TAG>  块类型前缀（行首）
//    /     行内加粗 开 / 闭
//    /     行内斜体 开 / 闭
const _kBlockOpen = '\u0001';
const _kBlockClose = '\u0002';
const _kB1 = '\u000b', _kB2 = '\u000c', _kI1 = '\u000e', _kI2 = '\u000f';

final _blockMarker =
    RegExp('^\\s*$_kBlockOpen([^$_kBlockClose]*)$_kBlockClose');

/// 轻量 HTML → 块列表：标题分级 / 引用 / 插图 / 行内粗斜体，其余拍平为正文。
List<ParaBlock> htmlToBlocks(String html) {
  var s = html;
  s = s.replaceAll(
    RegExp(r'<(script|style|head)[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    '',
  );

  // 块类型开标签 → 换行 + 类型哨兵
  s = s.replaceAllMapped(RegExp(r'<h([1-6])[^>]*>', caseSensitive: false), (m) {
    final level = int.parse(m[1]!);
    final kind = level <= 1 ? 'H1' : (level == 2 ? 'H2' : 'H3');
    return '\n$_kBlockOpen$kind$_kBlockClose';
  });
  s = s.replaceAll(RegExp(r'<blockquote[^>]*>', caseSensitive: false),
      '\n${_kBlockOpen}Q$_kBlockClose');

  // 插图：抽出 src，独立成块
  s = s.replaceAllMapped(
      RegExp(r'''<img[^>]*src\s*=\s*["']([^"']+)["'][^>]*>''',
          caseSensitive: false),
      (m) => '\n${_kBlockOpen}IMG:${m[1]}$_kBlockClose\n');

  // 行内粗斜体 → 哨兵（先于「去掉其余标签」处理）
  s = s.replaceAll(RegExp(r'<(b|strong)[^>]*>', caseSensitive: false), _kB1);
  s = s.replaceAll(RegExp(r'</(b|strong)>', caseSensitive: false), _kB2);
  s = s.replaceAll(RegExp(r'<(i|em)[^>]*>', caseSensitive: false), _kI1);
  s = s.replaceAll(RegExp(r'</(i|em)>', caseSensitive: false), _kI2);

  // 块级结束标签 → 换行
  s = s.replaceAll(
    RegExp(
      r'</(p|div|h[1-6]|li|blockquote|tr|td|th|section|article)>',
      caseSensitive: false,
    ),
    '\n',
  );
  s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]+>'), '');

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

  final blocks = <ParaBlock>[];
  for (var line in s.split('\n')) {
    var kind = ParaKind.body;
    String? image;
    final marker = _blockMarker.firstMatch(line);
    if (marker != null) {
      final tag = marker[1]!;
      line = line.substring(marker.end);
      switch (tag) {
        case 'H1':
          kind = ParaKind.h1;
        case 'H2':
          kind = ParaKind.h2;
        case 'H3':
          kind = ParaKind.h3;
        case 'Q':
          kind = ParaKind.quote;
        default:
          if (tag.startsWith('IMG:')) {
            kind = ParaKind.image;
            image = tag.substring(4);
          }
      }
    }
    if (kind == ParaKind.image) {
      blocks.add(ParaBlock(text: '', kind: kind, image: image));
      continue;
    }

    // 行内哨兵 → 干净文本 + 粗斜体范围
    final buf = StringBuffer();
    final bold = <(int, int)>[];
    final italic = <(int, int)>[];
    int? bStart, iStart;
    for (final rune in line.runes) {
      final c = String.fromCharCode(rune);
      switch (c) {
        case _kB1:
          bStart = buf.length;
        case _kB2:
          if (bStart != null && buf.length > bStart) {
            bold.add((bStart, buf.length));
          }
          bStart = null;
        case _kI1:
          iStart = buf.length;
        case _kI2:
          if (iStart != null && buf.length > iStart) {
            italic.add((iStart, buf.length));
          }
          iStart = null;
        default:
          buf.write(c);
      }
    }
    if (bStart != null && buf.length > bStart) bold.add((bStart, buf.length));
    if (iStart != null && buf.length > iStart) italic.add((iStart, buf.length));

    var text = buf.toString();
    final lead = text.length - text.trimLeft().length;
    text = text.trim();
    if (text.isEmpty) continue;
    List<(int, int)> shift(List<(int, int)> rs) => [
          for (final r in rs)
            if (r.$2 - lead > 0 && r.$1 - lead < text.length)
              ((r.$1 - lead).clamp(0, text.length),
                  (r.$2 - lead).clamp(0, text.length))
        ];
    blocks.add(ParaBlock(
        text: text, kind: kind, bold: shift(bold), italic: shift(italic)));
  }
  return blocks;
}
