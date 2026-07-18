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
  });

  final String title;
  final String author;
  final List<ChapterText> chapters;
}

/// 解析 EPUB 字节流为纯文本章节列表。
Future<LoadedBook> loadEpub(Uint8List bytes) async {
  final book = await EpubReader.readBook(bytes);
  final chapters = <ChapterText>[];

  void walk(List<EpubChapter> list, int depth) {
    for (final ch in list) {
      final text = _htmlToParagraphs(ch.HtmlContent ?? '');
      if (text.isNotEmpty) {
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
      final text = _htmlToParagraphs(f.Content ?? '');
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
      r'</(p|div|h[1-6]|li|blockquote|tr|section|article)>',
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
