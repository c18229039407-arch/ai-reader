import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/doubao_tts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('豆包语音 TTS 客户端', () {
    late HttpServer server;
    late String base;
    Map<String, dynamic>? lastRequest;
    final fakeMp3 = List<int>.generate(2048, (i) => i % 251);

    setUp(() async {
      lastRequest = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        lastRequest = jsonDecode(body) as Map<String, dynamic>;
        final text =
            ((lastRequest!['request'] as Map)['text'] as String?) ?? '';
        req.response.headers.contentType = ContentType.json;
        if (text == 'FAIL') {
          req.response.add(utf8.encode(
              jsonEncode({'code': 3001, 'message': 'invalid token'})));
        } else {
          req.response.add(utf8.encode(jsonEncode(
              {'code': 3000, 'message': 'ok', 'data': base64Encode(fakeMp3)})));
        }
        await req.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('合成成功：base64 解码回 mp3 字节，请求带音色与语速', () async {
      final c = DoubaoTtsClient(
        appId: 'app1',
        accessToken: 'tok1',
        voiceType: 'zh_female_wanwanxiaohe_moon_bigtts',
        baseUrl: base,
      );
      final bytes = await c.synthesize('你好，林间阅读。', speed: 1.2, pitch: 0.9);
      expect(bytes, fakeMp3);

      final audio = lastRequest!['audio'] as Map;
      expect(audio['voice_type'], 'zh_female_wanwanxiaohe_moon_bigtts');
      expect(audio['speed_ratio'], 1.2);
      expect(audio['pitch_ratio'], 0.9);
      expect((lastRequest!['app'] as Map)['appid'], 'app1');
      expect((lastRequest!['request'] as Map)['operation'], 'query');
    });

    test('错误码给可操作的提示（3001 提示检查 Key）', () async {
      final c = DoubaoTtsClient(
          appId: 'a', accessToken: 't', baseUrl: base);
      await expectLater(
        c.synthesize('FAIL'),
        throwsA(predicate((e) =>
            e.toString().contains('3001') &&
            e.toString().contains('AppID/Token'))),
      );
    });

    test('语速越界被收敛到合法区间', () async {
      final c = DoubaoTtsClient(
          appId: 'a', accessToken: 't', baseUrl: base);
      await c.synthesize('文本', speed: 9.9, pitch: 0.1);
      final audio = lastRequest!['audio'] as Map;
      expect(audio['speed_ratio'], 2.0);
      expect(audio['pitch_ratio'], 0.5);
    });

    test('预置音色全部来自官方授权库（不含任何真人克隆项）', () {
      for (final v in DoubaoTtsClient.presetVoices) {
        expect(v.$1, matches(RegExp(r'^zh_(female|male)_[a-z]+_moon_bigtts$')),
            reason: '只允许平台官方大模型音色命名空间');
      }
    });
  });
}
