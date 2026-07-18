import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 极简 Ollama 客户端：健康检查、模型列表、流式对话。
/// Phase 0 只验证链路，不做重试/超时策略等工程化处理。
class OllamaClient {
  OllamaClient(this.baseUrl);

  /// 形如 http://127.0.0.1:11434 或 http://192.168.x.x:11434
  final String baseUrl;

  Future<bool> healthCheck({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final res = await http.get(Uri.parse(baseUrl)).timeout(timeout);
      return res.statusCode == 200 && res.body.contains('Ollama');
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> listModels() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/tags'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final models = (data['models'] as List? ?? []);
    return models
        .map((m) => (m as Map<String, dynamic>)['name'] as String)
        .toList();
  }

  /// 流式返回增量文本片段。调用方自行拼接与展示。
  Stream<String> chatStream({
    required String model,
    required String system,
    required String user,
  }) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$baseUrl/api/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'model': model,
          'stream': true,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        });
      final res = await client.send(req);
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw Exception('Ollama HTTP ${res.statusCode}: $body');
      }
      // Ollama 流式响应：每行一个 JSON 对象
      final lines = res.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final obj = jsonDecode(line) as Map<String, dynamic>;
        if (obj['error'] != null) {
          throw Exception('Ollama error: ${obj['error']}');
        }
        final content =
            ((obj['message'] as Map<String, dynamic>?)?['content']
                as String?) ??
            '';
        if (content.isNotEmpty) yield content;
        if (obj['done'] == true) break;
      }
    } finally {
      client.close();
    }
  }
}
