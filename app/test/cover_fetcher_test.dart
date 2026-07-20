import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_reader/services/cover_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoverFetcher（Open Library）', () {
    late HttpServer server;
    late String base;
    final fakeJpeg = Uint8List.fromList(
        [0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(8 * 1024, 0x11)]);

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) {
        if (req.uri.path == '/search.json') {
          final body = jsonEncode({
            'docs': [
              {'title': 'No cover book'},
              {'title': 'The Wealth of Nations', 'cover_i': 12816911},
            ]
          });
          req.response.headers.contentType = ContentType.json;
          req.response.add(utf8.encode(body));
        } else if (req.uri.path == '/b/id/12816911-L.jpg') {
          req.response.add(fakeJpeg);
        } else {
          req.response.statusCode = 404;
        }
        req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('跳过无封面条目，取到第一个有 cover_i 的并下载校验', () async {
      final f = CoverFetcher(searchBase: base, coversBase: base);
      final bytes = await f.fetch('Wealth of Nations');
      expect(bytes, isNotNull);
      expect(bytes!.length, fakeJpeg.length);
      expect(bytes[0], 0xFF); // JPEG 魔数
    });

    test('全部无封面时返回 null 而非抛错', () async {
      final empty = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      empty.listen((req) {
        req.response.headers.contentType = ContentType.json;
        req.response.add(utf8.encode(jsonEncode({'docs': []})));
        req.response.close();
      });
      final f = CoverFetcher(
          searchBase: 'http://127.0.0.1:${empty.port}',
          coversBase: 'http://127.0.0.1:${empty.port}');
      expect(await f.fetch('小岛经济学'), isNull);
      await empty.close(force: true);
    });
  });
}
