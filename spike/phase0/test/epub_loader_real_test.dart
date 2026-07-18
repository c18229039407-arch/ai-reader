// 用真实公版 EPUB 验证解析器（Phase 0 验收项 2 的自动化部分）。
// 运行前把 EPUB 放到 test/fixtures/（仓库不提交书文件，见 .gitignore）：
//   鲁迅《呐喊》: https://www.gutenberg.org/ebooks/25305.epub3.images
//   Alice in Wonderland: https://www.gutenberg.org/ebooks/11.epub3.images
// 没有文件时自动跳过，不算失败。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader_spike/epub_loader.dart';

void main() {
  Future<void> check(String path, {required bool expectChinese}) async {
    final file = File(path);
    if (!file.existsSync()) {
      markTestSkipped('缺少测试文件 $path，跳过');
      return;
    }
    final book = await loadEpub(await file.readAsBytes());

    expect(book.title.isNotEmpty, true);
    expect(book.chapters.isNotEmpty, true, reason: '章节列表不应为空');

    final allText = book.chapters.expand((c) => c.paragraphs).join();
    expect(allText.length > 1000, true, reason: '正文总量过少，疑似解析失败');
    // 不应残留 HTML 标签
    expect(allText.contains(RegExp(r'<[a-zA-Z]+')), false,
        reason: '正文残留 HTML 标签');
    if (expectChinese) {
      expect(allText.contains(RegExp(r'[一-鿿]')), true, reason: '中文书应含中文字符');
    }
    // 输出概要供人工核对
    // ignore: avoid_print
    print('《${book.title}》 作者:${book.author} 章节:${book.chapters.length} '
        '总字数:${allText.length}');
    // ignore: avoid_print
    print('  首章[${book.chapters.first.title}] 首段: '
        '${book.chapters.first.paragraphs.first.substring(0, book.chapters.first.paragraphs.first.length > 40 ? 40 : book.chapters.first.paragraphs.first.length)}');
  }

  test('真实 EPUB：鲁迅《呐喊》(中文)', () async {
    await check('test/fixtures/nahan.epub', expectChinese: true);
  });

  test('真实 EPUB：Alice in Wonderland (英文)', () async {
    await check('test/fixtures/alice.epub', expectChinese: false);
  });
}
