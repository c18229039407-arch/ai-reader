import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_reader/models/models.dart';
import 'package:ai_reader/screens/reader/reader_screen.dart';
import 'package:ai_reader/screens/shelf/shelf_screen.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/settings_store.dart';

// 注意：widget 测试运行于 FakeAsync 时钟，真实文件 IO 必须包在
// tester.runAsync(...) 中执行，否则 Future 永不完成导致挂起。

Uint8List bytesOf(String s) => Uint8List.fromList(utf8.encode(s));

Future<SettingsStore> mockSettings() async {
  SharedPreferences.setMockInitialValues({'privacy_ack': true});
  return SettingsStore.load();
}

void main() {
  late Directory tmp;
  late LibraryStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ai_reader_wtest');
    store = LibraryStore(tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('书架空态 + 导入按钮存在', (tester) async {
    final settings = await mockSettings();
    await tester.pumpWidget(
        MaterialApp(home: ShelfScreen(settings: settings, store: store)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('书架还是空的'), findsOneWidget);
    // 右下角 FAB + 空状态 CTA 各一个
    expect(find.text('导入书籍'), findsNWidgets(2));
    expect(find.text('搜公版书'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('首次启动弹隐私说明（F3）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    await tester.pumpWidget(
        MaterialApp(home: ShelfScreen(settings: settings, store: store)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('数据说明'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('数据说明'), findsNothing);
    expect(settings.privacyAcknowledged, true);
  });

  testWidgets('阅读器：渲染、锚点秒开、翻章、进度写盘', (tester) async {
    final settings = await mockSettings();

    late Book book;
    await tester.runAsync(() async {
      book = await store.importBytes(
        bytesOf('第一章 甲\n\n第一章第一段。\n\n第一章第二段。\n\n第二章 乙\n\n第二章第一段。'),
        '样书.txt',
      );
      final st = BookState.empty();
      st.explanations.add(Explanation(
          id: 'e1',
          locator: const Locator(0, 0),
          term: '第一章第一段',
          contextExcerpt: 'ctx',
          resultText: '这是留存的解释',
          mode: 'explain',
          createdAt: DateTime(2026, 7, 18)));
      await store.saveState(book.id, st);
    });

    await tester.pumpWidget(MaterialApp(
        home: ReaderScreen(book: book, store: store, settings: settings)));

    // 轮询等待真实 IO 加载完成（避免 pumpAndSettle 撞上加载动画）
    for (var i = 0;
        i < 100 && tester.any(find.byType(CircularProgressIndicator));
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('第一章第一段。'), findsOneWidget);
    expect(find.text('✦'), findsOneWidget); // D8 锚点

    // 点锚点 → 秒开留存内容（测试窗口宽 800 < 900 → 底部抽屉）
    await tester.tap(find.text('✦'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // 抽屉动画
    expect(find.text('这是留存的解释'), findsOneWidget);
    expect(find.textContaining('已留存'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // 点遮罩关抽屉
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 翻章（C9）——触发写盘，需要让真实 IO 完成
    await tester.tap(find.byTooltip('下一章'));
    await tester.pump();
    expect(find.text('第二章第一段。'), findsOneWidget);

    // 写盘是多段 await 的真实 IO：交错 runAsync（推进真实事件循环）与
    // pump（冲刷假时钟微任务）若干轮，确保链条走完（C4）
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
    final saved = await tester.runAsync(() => store.loadState(book.id));
    expect(saved!.reading.chapterIndex, 1);
  });
}
