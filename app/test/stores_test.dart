import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader/models/models.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/txt_loader.dart';

void main() {
  late Directory tmp;
  late LibraryStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('ai_reader_test');
    store = LibraryStore(tmp);
    await store.init();
  });

  tearDown(() => tmp.delete(recursive: true));

  Uint8List txtBytes(String s) => Uint8List.fromList(utf8.encode(s));

  group('LibraryStore', () {
    test('导入 TXT：入库、去重、可读回内容', () async {
      final bytes = txtBytes('第一章 起点\n\n你好世界。\n\n第二章 终点\n\n再见世界。');
      final b1 = await store.importBytes(bytes, '测试书.txt');
      expect(b1.title, '测试书');
      expect(b1.format, 'txt');

      // 相同内容再导入 → 去重，返回同一本
      final b2 = await store.importBytes(bytes, '改了名字.txt');
      expect(b2.id, b1.id);
      expect((await store.listBooks()).length, 1);

      final content = await store.loadContent(b1);
      expect(content.chapters.length, 2);
      expect(content.chapters[0].title, contains('第一章'));
      expect(content.chapters[1].paragraphs.first, '再见世界。');
    });

    test('移除书籍：元数据、文件、状态一并清理', () async {
      final b = await store.importBytes(txtBytes('内容'), 'x.txt');
      await store.saveState(b.id, BookState.empty());
      await store.removeBook(b.id);
      expect(await store.listBooks(), isEmpty);
      expect(File('${tmp.path}/state/${b.id}.json').existsSync(), false);
      expect(File('${tmp.path}/${b.filePath}').existsSync(), false);
    });

    test('BookState 持久化往返：进度/高亮/解释完整还原', () async {
      final b = await store.importBytes(txtBytes('内容'), 'y.txt');
      final st = BookState.empty();
      st.reading = ReadingState(
          chapterIndex: 3,
          scrollOffset: 120.5,
          percent: 0.42,
          updatedAt: DateTime(2026, 7, 18));
      st.highlights.add(Highlight(
          locator: const Locator(3, 7),
          colorIndex: 1,
          createdAt: DateTime(2026, 7, 18)));
      st.explanations.add(Explanation(
          id: 'abc',
          locator: const Locator(3, 7),
          term: '交换价值',
          contextExcerpt: '……上下文……',
          resultText: '通俗解释……',
          mode: 'explain',
          createdAt: DateTime(2026, 7, 18)));
      await store.saveState(b.id, st);

      final back = await store.loadState(b.id);
      expect(back.reading.chapterIndex, 3);
      expect(back.reading.percent, closeTo(0.42, 1e-9));
      expect(back.highlights.single.locator, const Locator(3, 7));
      expect(back.highlights.single.colorIndex, 1);
      expect(back.explanations.single.term, '交换价值');
      expect(back.explanations.single.mode, 'explain');
    });

    test('损坏的状态文件 → 安全回退为空状态', () async {
      final b = await store.importBytes(txtBytes('内容'), 'z.txt');
      await File('${tmp.path}/state/${b.id}.json').writeAsString('{{{bad');
      final st = await store.loadState(b.id);
      expect(st.reading.chapterIndex, 0);
      expect(st.highlights, isEmpty);
    });
  });

  group('txt_loader', () {
    test('无章节标记 → 单章', () {
      final book = loadTxt(txtBytes('只有一段。\n\n还有一段。'), fallbackTitle: 't');
      expect(book.chapters.length, 1);
      expect(book.chapters.first.paragraphs.length, 2);
    });

    test('中文数字章节标记可识别', () {
      final book = loadTxt(
          txtBytes('第一章 开始\n\n内容A\n\n第十二章 中途\n\n内容B\n\nChapter 3\n\ncontent C'),
          fallbackTitle: 't');
      expect(book.chapters.length, 3);
      expect(book.chapters[1].title, contains('第十二章'));
    });
  });

  group('Locator', () {
    test('往返与相等', () {
      expect(Locator.parse('4:12'), const Locator(4, 12));
      expect(const Locator(4, 12).toString(), '4:12');
      expect(Locator.parse('bad'), isNull);
    });
  });

  group('UserProfile', () {
    test('promptFragment 组装与开关', () {
      final p =
          UserProfile(occupation: '程序员', interests: '做饭', personalizeOn: true);
      expect(p.promptFragment(), contains('程序员'));
      expect(p.promptFragment(), contains('做饭'));
      p.personalizeOn = false;
      expect(p.promptFragment(), '');
      final empty = UserProfile();
      expect(empty.promptFragment(), '');
    });
  });
}
