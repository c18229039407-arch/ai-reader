// OpenAI 兼容客户端（云端 Provider）单元测试：在测试内起 HttpServer 模拟
// SSE 流式协议，不依赖任何真实服务商。

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader/services/llm_client.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      // 鉴权校验
      if (req.headers.value('authorization') != 'Bearer test-key') {
        req.response.statusCode = 401;
        await req.response.close();
        return;
      }
      if (req.method == 'GET' && req.uri.path == '/models') {
        req.response.headers.contentType = ContentType.json;
        req.response.add(utf8.encode(jsonEncode({
          'data': [
            {'id': 'deepseek-chat'},
            {'id': 'deepseek-reasoner'},
          ]
        })));
      } else if (req.method == 'POST' && req.uri.path == '/chat/completions') {
        final body = jsonDecode(await utf8.decoder.bind(req).join())
            as Map<String, dynamic>;
        expect(body['stream'], true);
        req.response.headers.set('Content-Type', 'text/event-stream');
        for (final piece in ['你', '好', '呀']) {
          req.response.add(utf8.encode('data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': piece}
                  }
                ]
              })}\n\n'));
        }
        req.response.add(utf8.encode('data: [DONE]\n\n'));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('healthCheck：key 正确为 true，key 错误为 false', () async {
    expect(
        await OpenAiCompatClient(baseUrl: baseUrl, apiKey: 'test-key')
            .healthCheck(),
        true);
    expect(
        await OpenAiCompatClient(baseUrl: baseUrl, apiKey: 'wrong')
            .healthCheck(),
        false);
  });

  test('listModels 解析 data[].id', () async {
    final models =
        await OpenAiCompatClient(baseUrl: baseUrl, apiKey: 'test-key')
            .listModels();
    expect(models, ['deepseek-chat', 'deepseek-reasoner']);
  });

  test('chatStreamMessages 解析 SSE 增量并在 [DONE] 结束', () async {
    final chunks =
        await OpenAiCompatClient(baseUrl: baseUrl, apiKey: 'test-key')
            .chatStream(model: 'deepseek-chat', system: 's', user: 'u')
            .toList();
    expect(chunks.join(), '你好呀');
  });

  test('尾部斜杠地址可正常拼接', () async {
    final ok =
        await OpenAiCompatClient(baseUrl: '$baseUrl/', apiKey: 'test-key')
            .healthCheck();
    expect(ok, true);
  });
}
