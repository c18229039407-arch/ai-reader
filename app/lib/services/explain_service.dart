import '../models/models.dart';
import 'epub_loader.dart';
import 'ollama_client.dart';

/// 解释编排器：组装 选段 + 前后文 + 书籍元信息 + 用户画像。
class ExplainService {
  ExplainService({required this.client, required this.model});

  final OllamaClient client;
  final String model;

  static const contextParagraphs = 2; // 前后各取 N 段（D3）

  static String buildContext(
      ChapterText chapter, int paragraphIndex, String selected) {
    final from = (paragraphIndex - contextParagraphs)
        .clamp(0, chapter.paragraphs.length);
    final to = (paragraphIndex + contextParagraphs + 1)
        .clamp(0, chapter.paragraphs.length);
    return chapter.paragraphs.sublist(from, to).join('\n');
  }

  static String explainSystem({
    required String bookTitle,
    required String chapterTitle,
    required String contextExcerpt,
    required UserProfile profile,
  }) {
    final personal = profile.promptFragment();
    return '你是一位擅长把难懂概念讲通俗的阅读助手。'
        '用户正在读《$bookTitle》的「$chapterTitle」一章，选中了其中一段话。'
        '以下是该段的上下文，供你理解语境（不必逐句解释上下文）：\n---\n$contextExcerpt\n---\n'
        '请针对用户选中的文字：'
        '1) 用通俗中文解释其中的核心概念，禁止用术语解释术语；'
        '2) 给一个具体的生活化例子；$personal '
        '3) 如该概念在本书语境中有特定含义，简要指出。'
        '控制在 250 字以内，直接输出解释，不要客套。';
  }

  static String translateSystem() => '你是翻译助手。把用户给出的段落翻译成流畅的简体中文，'
      '目标是让读者看懂，语义准确优先于文采。只输出译文。';

  /// 开启一次解释会话（支持追问/换例/深度，D5/D6）。
  ExplainSession explainSession({
    required String bookTitle,
    required ChapterText chapter,
    required int paragraphIndex,
    required String selectedText,
    required UserProfile profile,
  }) {
    return ExplainSession(
      client: client,
      model: model,
      system: explainSystem(
        bookTitle: bookTitle,
        chapterTitle: chapter.title,
        contextExcerpt: buildContext(chapter, paragraphIndex, selectedText),
        profile: profile,
      ),
      firstUser: selectedText,
    );
  }

  ExplainSession translateSession(String selectedText) => ExplainSession(
        client: client,
        model: model,
        system: translateSystem(),
        firstUser: selectedText,
      );
}

/// 多轮解释会话：保留完整消息历史，供「追问/换个例子/更深入」复用上下文。
class ExplainSession {
  ExplainSession({
    required this.client,
    required this.model,
    required String system,
    required String firstUser,
  }) : _messages = [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': firstUser},
        ];

  final OllamaClient client;
  final String model;
  final List<Map<String, String>> _messages;

  /// D6 深度指令（也含 D5 换例）。
  static const presets = <String, String>{
    'oneLiner': '用一句话概括刚才的解释。',
    'deeper': '在刚才解释的基础上更深入地展开，可以引入必要的背景知识，但依然保持通俗。',
    'anotherExample': '换一个不同生活领域的例子重新讲一遍，其他内容不必重复。',
  };

  List<Map<String, String>> get messages => List.unmodifiable(_messages);

  /// 发起当前轮（首轮直接调用；追问先 addFollowUp 再调用）。
  /// 完成后由调用方通过 [commitAssistant] 把完整回答写回历史。
  Stream<String> send() =>
      client.chatStreamMessages(model: model, messages: _messages);

  void addFollowUp(String userText) =>
      _messages.add({'role': 'user', 'content': userText});

  void commitAssistant(String fullText) =>
      _messages.add({'role': 'assistant', 'content': fullText});
}
