import 'dart:io';
import 'dart:typed_data';

import 'package:ai_reader/screens/search/search_screen.dart';
import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/find_online.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmptySource implements BookSource {
  @override
  String get id => 'empty';
  @override
  String get displayName => '空源';
  @override
  String get licenseNote => '测试';
  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async =>
      [];
  @override
  Future<Uint8List> download(BookSearchResult item) async => Uint8List(0);
}

void main() {
  group('A4 站外找书链接', () {
    late LibraryStore store;

    setUp(() async {
      // 注意：真实 IO 必须在 FakeAsync 之外（testWidgets 体内会永久挂起）
      final tmp = await Directory.systemTemp.createTemp('find_online_test');
      store = LibraryStore(tmp);
    });

    test('四个入口且书名正确编码', () {
      final links = findOnlineLinks('小岛经济学');
      expect(links.map((l) => l.label),
          ['网页搜索', '豆瓣图书', '微信读书', '孔夫子旧书网']);
      for (final l in links) {
        expect(l.uri.scheme, 'https');
        expect(l.uri.queryParameters.values.join(), contains('小岛经济学'));
      }
    });

    test('特殊字符不破坏 URL', () {
      final links = findOnlineLinks('C++ Primer & 你好/世界');
      for (final l in links) {
        expect(l.uri.toString(), isNot(contains(' ')));
        expect(() => Uri.parse(l.uri.toString()), returnsNormally);
      }
    });

    testWidgets('搜索后（无结果）显示站外找书入口', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(store: store, sources: [_EmptySource()]),
      ));

      // 搜索前不显示
      expect(find.textContaining('站外找'), findsNothing);

      await tester.enterText(find.byType(TextField), '小岛经济学');
      await tester.tap(find.text('搜索'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.textContaining('站外找「小岛经济学」'), findsOneWidget);
      expect(find.text('网页搜索'), findsOneWidget);
      expect(find.text('豆瓣图书'), findsOneWidget);
      expect(find.text('微信读书'), findsOneWidget);
      expect(find.text('孔夫子旧书网'), findsOneWidget);
    });
  });
}
