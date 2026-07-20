import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/book_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WikisourceZhSource', () {
    late HttpServer server;
    late String apiBase;
    final requestedUris = <String>[];

    setUp(() async {
      requestedUris.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      apiBase = 'http://127.0.0.1:${server.port}/w/api.php';
      server.listen((req) {
        requestedUris.add(req.uri.toString());
        final body = jsonEncode({
          'query': {
            'searchinfo': {'totalhits': 4},
            'search': [
              {'ns': 0, 'title': '駱駝祥子'},
              {'ns': 0, 'title': '駱駝祥子/2'},
              {'ns': 0, 'title': '駱駝祥子/4'},
              {'ns': 0, 'title': '我怎樣寫《駱駝祥子》'},
            ],
          },
        });
        req.response.headers.contentType =
            ContentType('application', 'json', charset: 'utf-8');
        req.response.add(utf8.encode(body));
        req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('子页归并去重：駱駝祥子/2、/4 合并为主条目', () async {
      final src = WikisourceZhSource(apiBase: apiBase);
      final results = await src.search('骆驼祥子');

      expect(results, hasLength(2));
      expect(results[0].title, '駱駝祥子');
      expect(results[1].title, '我怎樣寫《駱駝祥子》');
      expect(results[0].sourceId, 'wikisource-zh');
      expect(results[0].downloadUrl,
          contains('format=epub&lang=zh&page=%E9%A7%B1%E9%A7%9D%E7%A5%A5%E5%AD%90'));
    });

    test('回归：查询必须限定标题（intitle:）且不带引号，避免全文噪音', () async {
      final src = WikisourceZhSource(apiBase: apiBase);
      await src.search('小岛"经济学"');

      expect(requestedUris, hasLength(1));
      final sr = Uri.parse(requestedUris.single).queryParameters['srsearch'];
      expect(sr, startsWith('intitle:'));
      expect(sr, isNot(contains('"')), reason: '引号会禁用简繁自动转换（实测）');
    });

    test('下载校验 EPUB 魔数：HTML 报错页会被拒绝', () async {
      final bad = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      bad.listen((req) {
        req.response.add(utf8.encode('<html>Error</html>'));
        req.response.close();
      });
      final src = WikisourceZhSource(apiBase: apiBase);
      final item = BookSearchResult(
        sourceId: 'wikisource-zh',
        title: 'x',
        author: '',
        lang: 'zh',
        downloadUrl: 'http://127.0.0.1:${bad.port}/',
      );
      await expectLater(
          src.download(item),
          throwsA(predicate(
              (e) => e.toString().contains('不是有效 EPUB'))));
      await bad.close(force: true);
    });
  });
}
