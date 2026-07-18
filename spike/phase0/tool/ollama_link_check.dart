// Phase 0 链路检查脚本（纯 Dart，可在任何有 Ollama 兼容服务的机器上运行）：
//   dart run tool/ollama_link_check.dart [http://127.0.0.1:11434]
// 依次验证 healthCheck / listModels / chatStream（用 App 的真实解释提示词），
// 输出首字延迟与总耗时——与 App 内解释面板的验收指标一致。

import 'dart:io';

import 'package:ai_reader_spike/ollama_client.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'http://127.0.0.1:11434';
  final client = OllamaClient(url);
  stdout.writeln('== Ollama 链路检查: $url ==');

  final healthy = await client.healthCheck();
  stdout.writeln('1) healthCheck: ${healthy ? "PASS" : "FAIL"}');
  if (!healthy) exit(1);

  final models = await client.listModels();
  stdout
      .writeln('2) listModels: ${models.isNotEmpty ? "PASS" : "FAIL"} $models');
  if (models.isEmpty) exit(1);

  // 与 explain_sheet.dart 中一致的提示词结构
  const system = '你是一位擅长把难懂概念讲通俗的阅读助手。'
      '用户正在读《国富论》的「论分工」一章，会给你一段书中原文。请：'
      '1) 用通俗中文解释其中的核心概念，禁止用术语解释术语；'
      '2) 给一个具体的生活化例子；读者的职业/背景是：程序员，平时爱做饭。'
      '举例时请优先使用贴合这个背景的日常场景做类比。'
      '3) 如该概念在本书语境中有特定含义，简要指出。'
      '控制在 200 字以内，直接输出解释，不要客套。';
  const user = '劳动生产力上最大的增进，以及运用劳动时所表现的更大的熟练、'
      '技巧和判断力，似乎都是分工的结果。';

  final sw = Stopwatch()..start();
  int? firstMs;
  final buf = StringBuffer();
  await for (final chunk
      in client.chatStream(model: models.first, system: system, user: user)) {
    firstMs ??= sw.elapsedMilliseconds;
    buf.write(chunk);
  }
  sw.stop();

  stdout.writeln('3) chatStream: ${buf.isNotEmpty ? "PASS" : "FAIL"}');
  stdout.writeln('   首字延迟: ${firstMs}ms | 总耗时: ${sw.elapsedMilliseconds}ms'
      ' | 输出长度: ${buf.length} 字');
  stdout.writeln('---- 模型输出 ----');
  stdout.writeln(buf.toString());
  if (buf.isEmpty) exit(1);
}
