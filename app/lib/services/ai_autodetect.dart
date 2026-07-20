import 'llm_client.dart';
import 'ollama_client.dart';
import 'settings_store.dart';

/// 零配置 AI 探测（欢迎页与书架共用）：
/// Ollama(11434) → LM Studio(1234)。命中即写入设置并返回提示文案；
/// 都没有返回 null（由调用方引导填云端 Key）。
Future<String?> autoDetectLocalAi(SettingsStore s) async {
  final ollama = OllamaClient('http://127.0.0.1:11434');
  if (await ollama.healthCheck()) {
    final models = await ollama.listModels();
    if (models.isNotEmpty) {
      final preferred = models.firstWhere(
        (m) => m.contains('3b') || m.contains('1.5b') || m.contains('4b'),
        orElse: () => models.first,
      );
      s
        ..providerType = 'ollama'
        ..ollamaUrl = 'http://127.0.0.1:11434'
        ..model = preferred
        ..aiSetupDone = true;
      return '已连接本机 Ollama · $preferred';
    }
  }

  final lmStudio = OpenAiCompatClient(
      baseUrl: 'http://127.0.0.1:1234/v1', apiKey: 'lm-studio');
  if (await lmStudio.healthCheck()) {
    final models = await lmStudio.listModels();
    if (models.isNotEmpty) {
      s
        ..providerType = 'openai'
        ..openaiBaseUrl = 'http://127.0.0.1:1234/v1'
        ..openaiApiKey = 'lm-studio'
        ..openaiModel = models.first
        ..aiSetupDone = true;
      return '已连接本机 LM Studio · ${models.first}';
    }
  }
  return null;
}
