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
          // 真实 API 行为：非 200 状态码 + JSON 错误体（沙盒实测 401+3001）
          req.response.statusCode = 401;
          req.response.add(utf8.encode(jsonEncode({
            'code': 3001,
            'message': 'load grant: requested grant not found in SaaS storage'
          })));
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

    test('非 200 + JSON 错误体：解析出真实原因并给可操作提示（回归：曾只报 HTTP 401）',
        () async {
      final c = DoubaoTtsClient(
          appId: 'a', accessToken: 't', baseUrl: base);
      await expectLater(
        c.synthesize('FAIL'),
        throwsA(predicate((e) =>
            e.toString().contains('服务未开通或音色未授权') &&
            e.toString().contains('3001'))),
      );
    });

    test('describeError 错误码翻译', () {
      expect(DoubaoTtsClient.describeError(3001, 'grant not found', 401),
          contains('服务未开通'));
      // 大模型资源缺失（实测 resource_id 10029）→ 给经典音色替代方案
      expect(
          DoubaoTtsClient.describeError(3001,
              '[resource_id=volc.service_type.10029] requested resource not granted', 403),
          contains('经典音色'));
      expect(DoubaoTtsClient.describeError(3003, null, 200), contains('额度'));
      expect(DoubaoTtsClient.describeError(3011, null, 200), contains('音色'));
      expect(DoubaoTtsClient.describeError(null, null, 403), contains('鉴权失败'));
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
        expect(
            v.$1,
            matches(RegExp(
                r'^(BV\d+_streaming|zh_(female|male)_[a-z]+_moon_bigtts)$')),
            reason: '只允许平台官方经典（BV）或大模型音色命名空间');
      }
    });

    test('一段式凭证粘贴解析：多种分隔符与非法输入', () {
      expect(DoubaoTtsClient.parseCombinedKey('1234567890:AbCdEf123456'),
          ('1234567890', 'AbCdEf123456'));
      expect(DoubaoTtsClient.parseCombinedKey(' 1234567890 ； TokenXYZ12345 '),
          ('1234567890', 'TokenXYZ12345'));
      expect(
          DoubaoTtsClient.parseCombinedKey('1234567890\nAbCdEf123456'),
          ('1234567890', 'AbCdEf123456'));
      // 非法：纯 AppID、纯 token、格式不符 → null（当普通输入处理）
      expect(DoubaoTtsClient.parseCombinedKey('1234567890'), isNull);
      expect(DoubaoTtsClient.parseCombinedKey('AbCdEf:123'), isNull);
    });

    test('清甜温柔预设：参数在 API 合法区间且音色来自授权库', () {
      const p = DoubaoTtsClient.sweetGentlePreset;
      expect(p.speedRatio, inInclusiveRange(0.90, 0.98),
          reason: '用户指定语速区间 0.90~0.98');
      expect(p.pitchRatio, inInclusiveRange(1.2, 1.35),
          reason: 'APP 音高 +0.4~+0.7 的换算区间');
      expect(DoubaoTtsClient.presetVoices.any((v) => v.$1 == p.voice), isTrue,
          reason: '预设音色必须是已验证的官方授权音色');
    });
  });
}
