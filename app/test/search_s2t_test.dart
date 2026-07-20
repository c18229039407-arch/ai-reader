import 'dart:io';
import 'dart:typed_data';

import 'package:ai_reader/screens/search/search_screen.dart';
import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/s2t_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟 Gutenberg 行为：只有繁体书名能命中。
class _TraditionalOnlySource implements BookSource {
  @override
  String get id => 'fake';
  @override
  String get displayName => '测试源';
  @override
  String get licenseNote => '测试';

  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async {
    if (query == '吶喊') {
      return [
        BookSearchResult(
          sourceId: id,
          title: '吶喊',
          author: 'Lu Xun',
          lang: 'zh',
          downloadUrl: 'http://example.com/nahan.epub',
        ),
      ];
    }
    return [];
  }

  @override
  Future<Uint8List> download(BookSearchResult item) async => Uint8List(0);
}

void main() {
  group('简繁转换（s2t_map）', () {
    test('呐喊 → 吶喊', () {
      expect(toTraditional('呐喊'), '吶喊');
    });
    test('朝花夕拾 简繁同形，转换后不变', () {
      expect(toTraditional('朝花夕拾'), '朝花夕拾');
    });
    test('英文与标点原样保留', () {
      expect(toTraditional('Adam Smith 1776!'), 'Adam Smith 1776!');
    });
    test('混合文本只转换有映射的字', () {
      expect(toTraditional('阿Q正传'), '阿Q正傳');
    });
  });

  group('搜索页简繁回退', () {
    late LibraryStore store;

    setUp(() async {
      final tmp = await Directory.systemTemp.createTemp('s2t_search_test');
      store = LibraryStore(tmp);
    });

    Future<void> pumpSearch(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(store: store, sources: [_TraditionalOnlySource()]),
      ));
    }

    testWidgets('简体「呐喊」自动转繁体命中，并显示转换提示', (tester) async {
      await pumpSearch(tester);
      await tester.enterText(find.byType(TextField), '呐喊');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('吶喊'), findsOneWidget); // 结果条目
      expect(find.textContaining('已自动按繁体「吶喊」搜索'), findsOneWidget);
    });

    testWidgets('繁体直接命中时不显示转换提示', (tester) async {
      await pumpSearch(tester);
      await tester.enterText(find.byType(TextField), '吶喊');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('吶喊'), findsWidgets);
      expect(find.textContaining('已自动按繁体'), findsNothing);
    });

    testWidgets('真无结果时显示「没有找到」而非初始空态文案', (tester) async {
      await pumpSearch(tester);
      // 初始空态
      expect(find.text('输入书名开始搜索公版书'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '不存在的书名xyz');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('输入书名开始搜索公版书'), findsNothing);
      expect(find.textContaining('没有找到「不存在的书名xyz」'), findsOneWidget);
      // 文案必须解释「为什么搜不到」：版权边界 + 正版导入的出路
      expect(find.textContaining('版权'), findsOneWidget);
      expect(find.textContaining('导入书籍'), findsOneWidget);
    });
  });
}
