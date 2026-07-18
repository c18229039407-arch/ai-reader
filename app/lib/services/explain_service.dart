import '../models/models.dart';
import 'epub_loader.dart';
import 'ollama_client.dart';

/// 解释编排器（docs/architecture.md §2.3 的 MVP 实现）：
/// 组装 选段 + 前后文 + 书籍元信息 + 用户画像 → 流式调用。
class ExplainService {
  ExplainService({required this.client, required this.model});

  final OllamaClient client;
  final String model;

  static const contextParagraphs = 2; // 前后各取 N 段（D3）

  /// 构造上下文摘录：所选段落前后各 [contextParagraphs] 段。
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

  Stream<String> explain({
    required String bookTitle,
    required ChapterText chapter,
    required int paragraphIndex,
    required String selectedText,
    required UserProfile profile,
  }) {
    final ctx = buildContext(chapter, paragraphIndex, selectedText);
    return client.chatStream(
      model: model,
      system: explainSystem(
        bookTitle: bookTitle,
        chapterTitle: chapter.title,
        contextExcerpt: ctx,
        profile: profile,
      ),
      user: selectedText,
    );
  }

  Stream<String> translate(String selectedText) => client.chatStream(
        model: model,
        system: translateSystem(),
        user: selectedText,
      );
}
