import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader/services/txt_loader.dart';

Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('正文以「第一章…」开头不被误判为标题（回归：widget 测试暴露的 bug）', () {
    final book = loadTxt(b('第一章 甲\n\n第一章第一段。\n\n第一章第二段。\n\n第二章 乙\n\n第二章第一段。'),
        fallbackTitle: 't');
    expect(book.chapters.length, 2);
    expect(book.chapters[0].paragraphs, ['第一章第一段。', '第一章第二段。']);
    expect(book.chapters[1].paragraphs, ['第二章第一段。']);
  });

  test('标题后跟标点也可识别', () {
    final book =
        loadTxt(b('第一章：开端\n\n内容。\n\n第二章、发展\n\n内容2。'), fallbackTitle: 't');
    expect(book.chapters.length, 2);
  });

  test('超长的伪标题行不切章', () {
    final longLine = '第一章${'很长' * 30}';
    final book = loadTxt(b('$longLine\n\n正文。'), fallbackTitle: 't');
    expect(book.chapters.length, 1);
  });
}
