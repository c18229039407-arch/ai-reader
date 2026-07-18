import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader/models/models.dart';
import 'package:ai_reader/screens/reader/search_in_book_screen.dart';
import 'package:ai_reader/services/epub_loader.dart';
import 'package:ai_reader/services/explain_service.dart';
import 'package:ai_reader/services/library_store.dart';

Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('笔记/书签模型与合并（C6 + E3）', () {
    test('BookState 含笔记书签的持久化往返', () async {
      final tmp = await Directory.systemTemp.createTemp('p3');
      addTearDown(() => tmp.delete(recursive: true));
      final store = LibraryStore(tmp, deviceId: 'd1');
      await store.init();

      final st = BookState.empty();
      st.notes.add(NoteAnn(
          locator: const Locator(1, 2),
          text: '这段写得妙',
          createdAt: DateTime(2026, 7, 18)));
      st.bookmarks.add(Bookmark(
          chapterIndex: 3,
          scrollOffset: 456.7,
          label: '读到这里',
          createdAt: DateTime(2026, 7, 18)));
      await store.saveState('bk', st);

      final back = await store.loadState('bk');
      expect(back.notes.single.text, '这段写得妙');
      expect(back.notes.single.locator, const Locator(1, 2));
      expect(back.bookmarks.single.chapterIndex, 3);
      expect(back.bookmarks.single.scrollOffset, closeTo(456.7, 1e-9));
    });

    test('mergeStates 合并笔记与书签（去重求并集）', () {
      final a = BookState.empty()
        ..notes.add(NoteAnn(
            locator: const Locator(0, 0),
            text: 'n1',
            createdAt: DateTime(2026, 1, 1)));
      final bSt = BookState.empty()
        ..notes.add(NoteAnn(
            locator: const Locator(0, 0),
            text: 'n1',
            createdAt: DateTime(2026, 1, 1))) // 同一条
        ..bookmarks.add(Bookmark(
            chapterIndex: 1,
            scrollOffset: 0,
            label: '',
            createdAt: DateTime(2026, 1, 2)));
      final merged = LibraryStore.mergeStates([a, bSt]);
      expect(merged.notes.length, 1);
      expect(merged.bookmarks.length, 1);
    });
  });

  group('书内检索（C7）', () {
    final book = LoadedBook(title: 't', author: 'a', chapters: [
      ChapterText(title: '一', paragraphs: ['劳动分工提高效率。', '别的内容。']),
      ChapterText(title: '二', paragraphs: ['再谈分工与市场。']),
    ]);

    test('跨章命中并生成预览', () {
      final m = searchInBook(book, '分工');
      expect(m.length, 2);
      expect(m[0].chapter, 0);
      expect(m[0].paragraph, 0);
      expect(m[1].chapter, 1);
      expect(m[0].preview, contains('分工'));
    });

    test('大小写不敏感与空查询', () {
      final bookEn = LoadedBook(title: 't', author: 'a', chapters: [
        ChapterText(title: 'c', paragraphs: ['The Division of Labour.']),
      ]);
      expect(searchInBook(bookEn, 'division').length, 1);
      expect(searchInBook(bookEn, '  '), isEmpty);
    });
  });

  group('标签与书目（B3）', () {
    test('Book tags 序列化与 copyWith', () {
      final book = Book(
        id: 'x',
        title: 't',
        author: 'a',
        filePath: 'books/x.epub',
        format: 'epub',
        addedAt: DateTime(2026, 7, 18),
        tags: ['经济学'],
      );
      final json = book.toJson();
      final back = Book.fromJson(json);
      expect(back.tags, ['经济学']);
      final updated = back.copyWith(tags: ['经济学', '在读']);
      expect(updated.tags.length, 2);
      expect(updated.id, 'x');
    });

    test('updateBook 持久化标签', () async {
      final tmp = await Directory.systemTemp.createTemp('p3b');
      addTearDown(() => tmp.delete(recursive: true));
      final store = LibraryStore(tmp);
      final book = await store.importBytes(b('内容'), 'x.txt');
      await store.updateBook(book.copyWith(tags: ['tag1']));
      final books = await store.listBooks();
      expect(books.single.tags, ['tag1']);
    });
  });

  group('备份导出导入（B5）', () {
    test('导出 → 新库导入：书目与状态完整迁移、重复导入合并', () async {
      final tmpA = await Directory.systemTemp.createTemp('p3c1');
      final tmpB = await Directory.systemTemp.createTemp('p3c2');
      addTearDown(() => tmpA.delete(recursive: true));
      addTearDown(() => tmpB.delete(recursive: true));

      final a = LibraryStore(tmpA, deviceId: 'a');
      final book = await a.importBytes(b('第一章 x\n\n正文'), '书.txt');
      final st = BookState.empty()
        ..explanations.add(Explanation(
            id: 'e1',
            locator: const Locator(0, 0),
            term: 'x',
            contextExcerpt: '',
            resultText: 'r',
            mode: 'explain',
            createdAt: DateTime(2026, 7, 18)));
      await a.saveState(book.id, st);

      final bundle = await a.exportBundle();

      final bStore = LibraryStore(tmpB, deviceId: 'b');
      await bStore.init();
      final added = await bStore.importBundle(bundle);
      expect(added, 1);
      final books = await bStore.listBooks();
      expect(books.single.title, '书');
      final backState = await bStore.loadState(book.id);
      expect(backState.explanations.single.id, 'e1');

      // 重复导入 → 不重复新增，状态合并不重复
      final added2 = await bStore.importBundle(bundle);
      expect(added2, 0);
      expect((await bStore.loadState(book.id)).explanations.length, 1);
    });

    test('无效包被拒绝', () async {
      final tmp = await Directory.systemTemp.createTemp('p3d');
      addTearDown(() => tmp.delete(recursive: true));
      final store = LibraryStore(tmp);
      await store.init();
      expect(() => store.importBundle('{"format":"other"}'), throwsException);
    });
  });

  group('术语一致性（D9）', () {
    test('prior 注入 system 提示词', () {
      final sys = ExplainService.explainSystem(
        bookTitle: 'b',
        chapterTitle: 'c',
        contextExcerpt: 'ctx',
        profile: UserProfile(),
        priorExplanation: '之前的解释文本',
      );
      expect(sys, contains('之前的解释文本'));
      expect(sys, contains('口径与结论一致'));
      final sysNone = ExplainService.explainSystem(
        bookTitle: 'b',
        chapterTitle: 'c',
        contextExcerpt: 'ctx',
        profile: UserProfile(),
      );
      expect(sysNone, isNot(contains('口径与结论一致')));
    });
  });

  group('PDF 入库（C8 数据层）', () {
    test('pdf 扩展名识别为 pdf 格式', () async {
      final tmp = await Directory.systemTemp.createTemp('p3e');
      addTearDown(() => tmp.delete(recursive: true));
      final store = LibraryStore(tmp);
      final book = await store.importBytes(b('%PDF-1.4 fake'), '论文.pdf');
      expect(book.format, 'pdf');
      expect(store.absolutePath(book), contains('.pdf'));
    });
  });
}
