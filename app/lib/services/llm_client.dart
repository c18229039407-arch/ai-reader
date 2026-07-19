import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// LLM Provider 抽象（PRD F1b）：Ollama 本地与 OpenAI 兼容云端共用此接口。
abstract class LlmClient {
  Future<bool> healthCheck({Duration timeout});

  Future<List<String>> listModels();

  Stream<String> chatStreamMessages({
    required String model,
    required List<Map<String, String>> messages,
  });
}

/// 单轮便捷入口。
extension LlmClientChat on LlmClient {
  Stream<String> chatStream({
    required String model,
    required String system,
    required String user,
  }) =>
      chatStreamMessages(model: model, messages: [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ]);
}

/// OpenAI 兼容云端客户端（DeepSeek / OpenAI / Moonshot / 智谱 等均适用）。
/// baseUrl 约定：填到版本路径为止，如
///   DeepSeek: https://api.deepseek.com   （其 /chat/completions 直接可用）
///   OpenAI:   https://api.openai.com/v1
class OpenAiCompatClient implements LlmClient {
  OpenAiCompatClient({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  String get _base => baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  @override
  Future<bool> healthCheck(
      {Duration timeout = const Duration(seconds: 6)}) async {
    try {
      final res = await http
          .get(Uri.parse('$_base/models'), headers: _headers)
          .timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> listModels() async {
    try {
      final res = await http
          .get(Uri.parse('$_base/models'), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return [];
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return ((data['data'] as List?) ?? [])
          .map((m) => (m as Map)['id'].toString())
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Stream<String> chatStreamMessages({
    required String model,
    required List<Map<String, String>> messages,
  }) async* {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse('$_base/chat/completions'))
        ..headers.addAll(_headers)
        ..body = jsonEncode({
          'model': model,
          'stream': true,
          'messages': messages,
        });
      final res = await client.send(req);
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw Exception('API HTTP ${res.statusCode}: $body');
      }
      // SSE：每条形如 "data: {json}"，以 "data: [DONE]" 结束
      final lines =
          res.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload == '[DONE]') break;
        final obj = jsonDecode(payload) as Map<String, dynamic>;
        final content = (((obj['choices'] as List?)?.firstOrNull
                as Map<String, dynamic>?)?['delta']
            as Map<String, dynamic>?)?['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      }
    } finally {
      client.close();
    }
  }
}

extension<T> on List<T>? {
  T? get firstOrNull {
    final l = this;
    return (l == null || l.isEmpty) ? null : l.first;
  }
}
