import 'dart:io';
import 'dart:typed_data';

import 'package:ai_reader/screens/search/search_screen.dart';
import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/title_atlas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 模拟公版库：只有英文原名能命中（复刻 Gutenberg 行为）。
class _EnglishOnlySource implements BookSource {
  @override
  String get id => 'fake-en';
  @override
  String get displayName => '测试源';
  @override
  String get licenseNote => '测试';

  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async {
    if (query.contains('Walden')) {
      return [
        BookSearchResult(
            sourceId: id,
            title: 'Walden, and On The Duty Of Civil Disobedience',
            author: 'Thoreau, Henry David',
            lang: 'en',
            downloadUrl: 'http://example.com/walden.epub'),
      ];
    }
    return [];
  }

  @override
  Future<Uint8List> download(BookSearchResult item) async => Uint8List(0);
}

void main() {
  group('名著书名地图', () {
    test('用户反馈的四本公版名著全部有映射', () {
      for (final t in ['瓦尔登湖', '理想国', '苏格拉底的申辩', '社会契约论']) {
        expect(atlasLookup(t), isNotNull, reason: '$t 应有原名映射');
      }
    });

    test('《》与空白不影响匹配', () {
      expect(atlasLookup('《瓦尔登湖》')!.$2, 'Walden');
      expect(atlasLookup(' 理想国 ')!.$2, 'The Republic');
    });

    test('版权期内名著给出出版年（人类简史）', () {
      expect(knownUnavailableYear('人类简史'), 2011);
      expect(knownUnavailableYear('《三体》'), 2006);
      expect(knownUnavailableYear('呐喊'), isNull);
    });

    test('映射与版权表不重叠（一本书不能既公版又受限）', () {
      for (final k in titleAtlas.keys) {
        expect(knownUnavailable.containsKey(k), isFalse, reason: k);
      }
    });
  });

  group('搜索页原名回退', () {
    late LibraryStore store;

    setUp(() async {
      // 真实 IO 必须在 FakeAsync 之外（testWidgets 体内会永久挂起）
      final tmp = await Directory.systemTemp.createTemp('atlas_test');
      store = LibraryStore(tmp);
    });

    testWidgets('搜「瓦尔登湖」自动转搜 Walden 并显示版权说明', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(store: store, sources: [_EnglishOnlySource()]),
      ));
      await tester.enterText(find.byType(TextField).first, '瓦尔登湖');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Walden, and On The Duty'), findsOneWidget);
      expect(find.textContaining('已为你找到原著《Walden》'), findsOneWidget);
    });

    testWidgets('搜「人类简史」给出精确的版权期解释', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(store: store, sources: [_EnglishOnlySource()]),
      ));
      await tester.enterText(find.byType(TextField).first, '人类简史');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.textContaining('搜不到《人类简史》是正常的'), findsOneWidget);
      expect(find.textContaining('2011 年出版'), findsOneWidget);
    });
  });
}
