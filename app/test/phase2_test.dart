import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_reader/models/models.dart';
import 'package:ai_reader/services/batch_translator.dart';
import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/epub_loader.dart';
import 'package:ai_reader/services/explain_service.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/ollama_client.dart';
import 'package:ai_reader/services/translation_store.dart';

void main() {
  group('多设备状态合并（E3/E4）', () {
    test('进度取最新、高亮/解释求并集去重', () {
      final mac = BookState(
        reading: ReadingState(
            chapterIndex: 2,
            scrollOffset: 10,
            percent: 0.2,
            updatedAt: DateTime(2026, 7, 18, 9)),
        highlights: [
          Highlight(
              locator: const Locator(0, 1),
              colorIndex: 0,
              createdAt: DateTime(2026, 7, 18, 8)),
        ],
        explanations: [
          Explanation(
              id: 'a',
              locator: const Locator(0, 1),
              term: 't1',
              contextExcerpt: '',
              resultText: 'r1',
              mode: 'explain',
              createdAt: DateTime(2026, 7, 18, 8)),
        ],
      );
      final phone = BookState(
        reading: ReadingState(
            chapterIndex: 5,
            scrollOffset: 99,
            percent: 0.5,
            updatedAt: DateTime(2026, 7, 18, 12)), // 更新
        highlights: [
          // 与 mac 相同的一条（应去重）+ 新的一条
          Highlight(
              locator: const Locator(0, 1),
              colorIndex: 0,
              createdAt: DateTime(2026, 7, 18, 8)),
          Highlight(
              locator: const Locator(3, 4),
              colorIndex: 1,
              createdAt: DateTime(2026, 7, 18, 11)),
        ],
        explanations: [
          Explanation(
              id: 'b',
              locator: const Locator(3, 4),
              term: 't2',
              contextExcerpt: '',
              resultText: 'r2',
              mode: 'explain',
              createdAt: DateTime(2026, 7, 18, 11)),
        ],
      );

      final merged = LibraryStore.mergeStates([mac, phone]);
      expect(merged.reading.chapterIndex, 5); // 最新的赢
      expect(merged.highlights.length, 2); // 去重后并集
      expect(merged.explanations.map((e) => e.id).toSet(), {'a', 'b'});
    });

    test('两个设备分别写盘后 loadState 能合并读出', () async {
      final tmp = await Directory.systemTemp.createTemp('merge_test');
      addTearDown(() => tmp.delete(recursive: true));

      final macStore = LibraryStore(tmp, deviceId: 'mac');
      final phoneStore = LibraryStore(tmp, deviceId: 'phone');
      await macStore.init();

      final st1 = BookState.empty()
        ..explanations.add(Explanation(
            id: 'from-mac',
            locator: const Locator(0, 0),
            term: 'x',
            contextExcerpt: '',
            resultText: 'r',
            mode: 'explain',
            createdAt: DateTime(2026, 7, 18)));
      await macStore.saveState('book1', st1);

      final st2 = BookState.empty()
        ..explanations.add(Explanation(
            id: 'from-phone',
            locator: const Locator(1, 1),
            term: 'y',
            contextExcerpt: '',
            resultText: 'r2',
            mode: 'explain',
            createdAt: DateTime(2026, 7, 18)));
      await phoneStore.saveState('book1', st2);

      final merged = await macStore.loadState('book1');
      expect(merged.explanations.map((e) => e.id).toSet(),
          {'from-mac', 'from-phone'});
    });
  });

  group('翻译存储与批量翻译（G2/G3）', () {
    test('BookTranslation 持久化往返', () async {
      final tmp = await Directory.systemTemp.createTemp('trans_test');
      addTearDown(() => tmp.delete(recursive: true));
      final store = TranslationStore(tmp);

      final t = BookTranslation.empty()
        ..paras['0:0'] = '译文一'
        ..model = 'qwen2.5:7b';
      await store.save('b1', t);

      final back = await store.load('b1');
      expect(back.of(0, 0), '译文一');
      expect(back.of(0, 1), isNull);
      expect(back.model, 'qwen2.5:7b');
      expect(back.completed, false);
    });

    test('BatchTranslator：全书翻译、断点续跑跳过已译段', () async {
      final tmp = await Directory.systemTemp.createTemp('batch_test');
      addTearDown(() => tmp.delete(recursive: true));
      final store = TranslationStore(tmp);

      // 预置一段已译 → 续跑应跳过它
      final pre = BookTranslation.empty()..paras['0:0'] = '已有译文';
      await store.save('b1', pre);

      var calls = 0;
      final mock = MockClient.streaming((req, _) async {
        calls++;
        final body = '${jsonEncode({
              'message': {'role': 'assistant', 'content': '译文'},
              'done': false
            })}\n'
            '${jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true
            })}\n';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });

      final book = LoadedBook(title: 't', author: 'a', chapters: [
        ChapterText(title: 'c1', paragraphs: ['段一', '段二']),
        ChapterText(title: 'c2', paragraphs: ['段三']),
      ]);

      final translator = BatchTranslator(
        client: _MockOllama(mock),
        model: 'm',
        store: store,
        bookId: 'b1',
        book: book,
      );
      await translator.run();

      expect(translator.status.value, BatchStatus.completed);
      expect(calls, 2); // 3 段中 1 段已译，只调 2 次
      final t = await store.load('b1');
      expect(t.of(0, 0), '已有译文');
      expect(t.of(0, 1), '译文');
      expect(t.of(1, 0), '译文');
      expect(t.completed, true);
      expect(translator.progress.value, 1.0);
    });
  });

  group('Gutendex 公版书源（A2/A3）', () {
    test('search 解析结果并选取 epub 链接', () async {
      final mock = MockClient((req) async {
        expect(req.url.path, '/books/');
        expect(req.url.queryParameters['search'], '呐喊');
        return http.Response(
            jsonEncode({
              'results': [
                {
                  'title': '吶喊',
                  'authors': [
                    {'name': 'Lu, Xun'}
                  ],
                  'languages': ['zh'],
                  'formats': {
                    'application/epub+zip': 'https://example.com/27166.epub',
                    'text/html': 'https://example.com/27166.html',
                  },
                },
                {
                  'title': 'No Epub Book',
                  'authors': [],
                  'languages': ['en'],
                  'formats': {'text/html': 'https://example.com/x.html'},
                },
              ]
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      });

      final source = GutendexSource(client: mock);
      final results = await source.search('呐喊');
      expect(results.length, 1); // 无 epub 的条目被过滤
      expect(results.first.title, '吶喊');
      expect(results.first.author, 'Lu, Xun');
      expect(results.first.downloadUrl, 'https://example.com/27166.epub');
      expect(source.licenseNote, isNotEmpty); // 合规：许可说明必须存在
    });
  });

  group('解释会话（D5/D6）', () {
    test('追问轮保留完整历史，assistant 回答入历史', () {
      final session = ExplainSession(
        client: OllamaClient('http://x'),
        model: 'm',
        system: 'sys',
        firstUser: '选中的文字',
      );
      expect(session.messages.length, 2);

      session.commitAssistant('第一轮回答');
      session.addFollowUp(ExplainSession.presets['deeper']!);
      expect(session.messages.length, 4);
      expect(session.messages[2]['content'], '第一轮回答');
      expect(session.messages[3]['role'], 'user');
      expect(session.messages[3]['content'], contains('更深入'));
    });
  });
}

/// 用 MockClient 替换 OllamaClient 内部 http 的轻量桩：
/// 通过覆写 chatStreamMessages 直接走 mock streaming。
class _MockOllama extends OllamaClient {
  _MockOllama(this._mock) : super('http://mock');

  final http.BaseClient _mock;

  @override
  Stream<String> chatStreamMessages({
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final req = http.Request('POST', Uri.parse('http://mock/api/chat'))
      ..body = jsonEncode({'model': model, 'messages': messages});
    final res = await _mock.send(req);
    final lines =
        res.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final obj = jsonDecode(line) as Map<String, dynamic>;
      final content =
          ((obj['message'] as Map<String, dynamic>?)?['content'] as String?) ??
              '';
      if (content.isNotEmpty) yield content;
      if (obj['done'] == true) break;
    }
  }
}
