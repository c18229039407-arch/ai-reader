import 'llm_client.dart';

/// AI 书名翻译（检索增强第二层）。
///
/// 词典（title_atlas）覆盖不到的外国作品，用用户已配置的 AI
/// 把中文译名翻成「原著书名 + 作者姓氏」检索词，再搜公版库。
/// 词典是第一层（零成本、离线、秒回），AI 是通用兜底。
const _system = '你是图书检索助手。用户给出一个书名，它可能是外国作品的中文译名。'
    '如果是外国作品：只输出一行「原著语言书名 作者姓氏」，例如：Walden Thoreau。'
    '如果它是中文原创作品、或你不确定原著名：只输出 SAME。'
    '禁止输出任何解释、标点引号或多余文字。';

/// 清洗模型回复 → 可用检索词；不可用返回 null。
String? sanitizeTitleReply(String reply) {
  var line = reply.trim().split('\n').first.trim();
  // 去常见包裹符号
  line = line.replaceAll(RegExp(r'''["'“”《》()（）\[\]]'''), '').trim();
  if (line.isEmpty) return null;
  if (line.toUpperCase() == 'SAME') return null;
  // 必须含拉丁字母（Gutendex 只认原文检索词）且不过长
  if (!RegExp(r'[A-Za-z]').hasMatch(line)) return null;
  if (line.length > 80) return null;
  return line;
}

/// 让 AI 给出原著检索词；失败/不适用返回 null（调用方自行设超时）。
Future<String?> originalTitleQuery(
    String zhQuery, LlmClient client, String model) async {
  final buf = StringBuffer();
  await for (final chunk in client.chatStreamMessages(model: model, messages: [
    {'role': 'system', 'content': _system},
    {'role': 'user', 'content': zhQuery},
  ])) {
    buf.write(chunk);
    if (buf.length > 200) break; // 防跑偏长输出
  }
  return sanitizeTitleReply(buf.toString());
}
