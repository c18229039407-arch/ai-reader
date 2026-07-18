import 'dart:convert';
import 'dart:typed_data';

import 'epub_loader.dart';

/// TXT → 章节列表（A1）。
/// 章节切分启发式：形如「第X章/回/节/卷/部」或「Chapter N」的行视为章节标题；
/// 无法识别时整本作为单章。
LoadedBook loadTxt(Uint8List bytes, {String fallbackTitle = '未知书名'}) {
  String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    // 常见 GBK 文件：MVP 不引入编码库，提示用户转码（README 说明）。
    text = latin1.decode(bytes);
  }

  final lines = text.split(RegExp(r'\r?\n'));
  // 「第X章」后必须跟空白/行尾/常见标点，避免把正文中「第一章第一段」这类
  // 开头的段落误判为标题；标题行长度另设上限兜底。
  final headingRe = RegExp(
      r'^\s*(第\s*[0-9一二三四五六七八九十百千零〇两]{1,10}\s*[章回节卷部](?=\s|$|[：:、.。·—-])|Chapter\s+\d+|CHAPTER\s+\d+)');
  bool isHeading(String line) =>
      headingRe.hasMatch(line) && line.trim().length <= 40;

  final chapters = <ChapterText>[];
  var currentTitle = '';
  var buf = <String>[];

  void flush() {
    final paras = buf.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (paras.isNotEmpty) {
      chapters.add(ChapterText(
          title: currentTitle.isEmpty ? '正文' : currentTitle,
          paragraphs: paras));
    }
    buf = <String>[];
  }

  for (final line in lines) {
    if (isHeading(line)) {
      flush();
      currentTitle = line.trim();
    } else {
      buf.add(line);
    }
  }
  flush();

  if (chapters.isEmpty) {
    chapters.add(ChapterText(title: '正文', paragraphs: ['（空文件）']));
  }

  return LoadedBook(title: fallbackTitle, author: '未知作者', chapters: chapters);
}
