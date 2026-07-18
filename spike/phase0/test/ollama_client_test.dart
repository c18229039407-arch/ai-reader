// OllamaClient 协议层单元测试：在测试内起一个模拟 Ollama 流式协议的
// HttpServer，不依赖任何外部服务，可在 CI 与任何机器上运行。
// （端到端真实模型验证见 tool/ollama_link_check.dart。）

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader_spike/ollama_client.dart';

void main() {
  late HttpServer server;
  late String baseUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((req) async {
      if (req.method == 'GET' && req.uri.path == '/') {
        req.response.write('Ollama is running');
      } else if (req.method == 'GET' && req.uri.path == '/api/tags') {
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          'models': [
            {'name': 'qwen2.5:7b'},
            {'name': 'qwen2.5:14b'},
          ]
        }));
      } else if (req.method == 'POST' && req.uri.path == '/api/chat') {
        final body = jsonDecode(await utf8.decoder.bind(req).join())
            as Map<String, dynamic>;
        expect(body['stream'], true);
        expect((body['messages'] as List).length, 2);
        req.response.headers.set('Content-Type', 'application/x-ndjson');
        for (final piece in ['你好', '，', '世界']) {
          req.response.add(utf8.encode('${jsonEncode({
                'message': {'role': 'assistant', 'content': piece},
                'done': false
              })}\n'));
        }
        req.response.add(utf8.encode('${jsonEncode({
              'message': {'role': 'assistant', 'content': ''},
              'done': true
            })}\n'));
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('healthCheck 对正常服务返回 true', () async {
    expect(await OllamaClient(baseUrl).healthCheck(), true);
  });

  test('healthCheck 对不可达地址返回 false（不抛异常）', () async {
    expect(await OllamaClient('http://127.0.0.1:1').healthCheck(), false);
  });

  test('listModels 解析模型列表', () async {
    final models = await OllamaClient(baseUrl).listModels();
    expect(models, ['qwen2.5:7b', 'qwen2.5:14b']);
  });

  test('chatStream 按增量拼接并在 done 处结束', () async {
    final chunks = await OllamaClient(baseUrl)
        .chatStream(model: 'qwen2.5:7b', system: 's', user: 'u')
        .toList();
    expect(chunks.join(), '你好，世界');
  });

  test('chatStream 对服务端 error 字段抛异常', () async {
    final errServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    errServer.listen((req) async {
      req.response.write('${jsonEncode({'error': 'model not found'})}\n');
      await req.response.close();
    });
    final client = OllamaClient('http://127.0.0.1:${errServer.port}');
    expect(
      () => client.chatStream(model: 'x', system: 's', user: 'u').toList(),
      throwsException,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await errServer.close(force: true);
  });
}
