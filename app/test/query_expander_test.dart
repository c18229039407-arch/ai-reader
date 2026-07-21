import 'dart:io';
import 'dart:typed_data';

import 'package:ai_reader/screens/search/search_screen.dart';
import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/llm_client.dart';
import 'package:ai_reader/services/query_expander.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLlm implements LlmClient {
  _FakeLlm(this.chunks);
  final List<String> chunks;

  @override
  Future<bool> healthCheck({Duration timeout = const Duration(seconds: 2)}) async =>
      true;

  @override
  Future<List<String>> listModels() async => ['fake'];

  @override
  Stream<String> chatStreamMessages(
      {required String model,
      required List<Map<String, String>> messages}) async* {
    for (final c in chunks) {
      yield c;
    }
  }
}

class _EnglishOnlySource implements BookSource {
  @override
  String get id => 'fake-en';
  @override
  String get displayName => '测试源';
  @override
  String get licenseNote => '测试';
  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async =>
      query.contains('Moon Is Down')
          ? [
              BookSearchResult(
                  sourceId: id,
                  title: 'The Moon Is Down',
                  author: 'Steinbeck',
                  lang: 'en',
                  downloadUrl: 'http://example.com/moon.epub')
            ]
          : [];
  @override
  Future<Uint8List> download(BookSearchResult item) async => Uint8List(0);
}

void main() {
  group('AI 书名翻译（回复清洗）', () {
    test('正常回复直接可用', () {
      expect(sanitizeTitleReply('Walden Thoreau'), 'Walden Thoreau');
    });
    test('SAME / 空 / 纯中文 → null', () {
      expect(sanitizeTitleReply('SAME'), isNull);
      expect(sanitizeTitleReply('  same \n随便'), isNull);
      expect(sanitizeTitleReply(''), isNull);
      expect(sanitizeTitleReply('这是中文原创作品'), isNull);
    });
    test('剥引号书名号、只取首行', () {
      expect(sanitizeTitleReply('《"Walden Thoreau"》\n解释：……'),
          'Walden Thoreau');
    });
    test('超长输出拒绝', () {
      expect(sanitizeTitleReply('A' * 100), isNull);
    });

    test('originalTitleQuery 拼接流式分片', () async {
      final t = await originalTitleQuery(
          '月亮下去了', _FakeLlm(['The Moon', ' Is Down', ' Steinbeck']), 'fake');
      expect(t, 'The Moon Is Down Steinbeck');
    });

    test('originalTitleQuery 对 SAME 返回 null', () async {
      expect(await originalTitleQuery('呐喊', _FakeLlm(['SAME']), 'fake'),
          isNull);
    });
  });

  group('搜索页 AI 原名并行链路', () {
    late LibraryStore store;

    setUp(() async {
      final tmp = await Directory.systemTemp.createTemp('qe_test');
      store = LibraryStore(tmp);
    });

    testWidgets('词典没有的书：注入解析器（模拟 AI）→ 命中原著并标注 AI 识别',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(
          store: store,
          sources: [_EnglishOnlySource()],
          queryResolver: (q) async =>
              q == '月亮下去了' ? ('Moon Is Down Steinbeck', 'The Moon Is Down') : null,
        ),
      ));
      await tester.enterText(find.byType(TextField).first, '月亮下去了');
      await tester.tap(find.text('搜索'));
      await tester.pumpAndSettle();

      expect(find.text('The Moon Is Down'), findsWidgets);
      expect(find.textContaining('AI 识别'), findsOneWidget);
    });
  });
}
