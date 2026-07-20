import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/batch_translator.dart';
import '../../services/doubao_tts.dart';
import '../../services/epub_loader.dart';
import '../../services/explain_service.dart';
import '../../services/library_store.dart';
import '../../services/llm_client.dart';
import '../../services/ollama_client.dart';
import '../../services/paginator.dart';
import '../../services/settings_store.dart';
import '../../services/translation_store.dart';
import '../../services/tts_service.dart';
import '../../ui/motion.dart';
import 'annotations_screen.dart';
import 'assistant_panel.dart';
import 'concepts_screen.dart';
import 'explain_panel.dart';
import 'reader_papers.dart';
import 'share_card.dart';
import 'search_in_book_screen.dart';

/// 高亮色板（C5）。
const highlightColors = [
  Color(0x66FFD54F), // 黄
  Color(0x6681C784), // 绿
  Color(0x6664B5F6), // 蓝
];

/// 正文显示模式（G3）。
enum DisplayMode { original, translated, bilingual }

/// 阅读器（C1–C5/C9 + D1–D8 + G1–G4）。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.store,
    required this.settings,
    this.translationStore,
  });

  final Book book;
  final LibraryStore store;
  final SettingsStore settings;
  final TranslationStore? translationStore;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  LoadedBook? _content;
  BookState _state = BookState.empty();
  Object? _loadError;

  late final TranslationStore _tStore =
      widget.translationStore ?? TranslationStore(widget.store.rootDir);
  BookTranslation _translation = BookTranslation.empty();
  BatchTranslator? _batch;
  DisplayMode _mode = DisplayMode.original;

  int _chapterIndex = 0;
  final _scroll = ScrollController();
  Timer? _saveDebounce;

  String _selectedText = '';
  bool _selBarVisible = false; // 划选后自动浮出的操作条
  Widget? _sidePanel;

  ChapterText? get _chapter =>
      (_content != null && _content!.chapters.isNotEmpty)
          ? _content!.chapters[_chapterIndex]
          : null;

  Timer? _statsTimer;
  final TtsService _tts = TtsService();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
    // 朗读到某段时高亮该段
    _tts.currentPara.addListener(() {
      if (mounted) setState(() {});
    });
    // 每 30 秒累计一次阅读时长（仅前台；退出时结算尾数）
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      widget.store.stats.addSeconds(widget.book.id, 30);
    });
  }

  Future<void> _load() async {
    try {
      final content = await widget.store.loadContent(widget.book);
      final state = await widget.store.loadState(widget.book.id);
      final translation = await _tStore.load(widget.book.id);
      setState(() {
        _content = content;
        _state = state;
        _translation = translation;
        _chapterIndex =
            state.reading.chapterIndex.clamp(0, content.chapters.length - 1);
        _anchorPara = state.reading.anchorPara;
        // 新书首次打开：跳过封面/版权等零碎前页，直达第一个有正文的章节
        if (state.reading.chapterIndex == 0 &&
            state.reading.scrollOffset == 0 &&
            state.reading.anchorPara == 0) {
          final first = content.chapters.indexWhere(
              (c) => c.paragraphs.join().length >= 200);
          if (first > 0) _chapterIndex = first;
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients &&
            state.reading.scrollOffset > 0 &&
            _scroll.position.maxScrollExtent > 0) {
          _scroll.jumpTo(state.reading.scrollOffset
              .clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    } catch (e) {
      setState(() => _loadError = e);
    }
  }

  void _onScroll() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _saveProgress);
  }

  Future<void> _saveProgress() async {
    final content = _content;
    if (content == null) return;
    final isPage = widget.settings.readingMode == 'page';
    final frac = isPage
        ? (_pages == null || _pages!.isEmpty
            ? 0.0
            : _pageIndex / _pages!.length)
        : (_scroll.hasClients && _scroll.position.maxScrollExtent > 0
            ? _scroll.offset / _scroll.position.maxScrollExtent
            : 0.0);
    _state.reading = ReadingState(
      chapterIndex: _chapterIndex,
      scrollOffset: !isPage && _scroll.hasClients ? _scroll.offset : 0,
      anchorPara: _anchorPara,
      percent:
          ((_chapterIndex + frac.clamp(0.0, 1.0)) / content.chapters.length)
              .clamp(0.0, 1.0),
      updatedAt: DateTime.now(),
    );
    await widget.store.saveState(widget.book.id, _state);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveProgress();
    _statsTimer?.cancel();
    _tts.dispose();
    _batch?.pause();
    _scroll.dispose();
    _pageCtrl?.dispose();
    super.dispose();
  }

  // ---------- 定位与状态 ----------

  int? _locateParagraph(String selected) {
    final ch = _chapter;
    if (ch == null || selected.trim().isEmpty) return null;
    final needle = selected.trim().replaceAll(RegExp(r'\s+'), '');
    final probe = needle.length > 24 ? needle.substring(0, 24) : needle;
    for (var i = 0; i < ch.paragraphs.length; i++) {
      if (ch.paragraphs[i].replaceAll(RegExp(r'\s+'), '').contains(probe)) {
        return i;
      }
    }
    return null;
  }

  List<Highlight> _highlightsAt(int para) {
    final loc = Locator(_chapterIndex, para);
    return _state.highlights.where((h) => h.locator == loc).toList();
  }

  List<Explanation> _explanationsAt(int para) {
    final loc = Locator(_chapterIndex, para);
    return _state.explanations.where((e) => e.locator == loc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _toggleHighlight(int colorIndex) async {
    final para = _locateParagraph(_selectedText);
    if (para == null) return;

    // 句级高亮：在段落里定位选中文字的字符范围；
    // 找不到（选区跨段等）时回退为整段高亮。
    final paraText = _chapter?.paragraphs[para] ?? '';
    final sel = _selectedText.trim();
    int? start;
    int? end;
    if (sel.isNotEmpty && sel.length < paraText.trim().length) {
      final idx = paraText.indexOf(sel);
      if (idx >= 0) {
        start = idx;
        end = idx + sel.length;
      }
    }

    final s0 = start;
    final e0 = end;
    final existing = _highlightsAt(para)
        .where((h) => s0 == null || e0 == null ? !h.isRange : h.overlaps(s0, e0))
        .firstOrNull;
    setState(() {
      if (existing != null) {
        _state.highlights.remove(existing);
      } else {
        _state.highlights.add(Highlight(
            locator: Locator(_chapterIndex, para),
            colorIndex: colorIndex,
            createdAt: DateTime.now(),
            start: start,
            end: end,
            snippet: start != null ? sel : null));
      }
    });
    await widget.store.saveState(widget.book.id, _state);
  }

  // ---------- AI ----------

  ExplainService? _service() {
    final s = widget.settings;
    if (!s.aiEnabled) return null;
    if (s.providerType == 'openai') {
      if (s.openaiApiKey.isEmpty || s.openaiModel.isEmpty) return null;
      return ExplainService(
        client: OpenAiCompatClient(
            baseUrl: s.openaiBaseUrl, apiKey: s.openaiApiKey),
        model: s.openaiModel,
      );
    }
    if (s.model.isEmpty) return null;
    return ExplainService(client: OllamaClient(s.ollamaUrl), model: s.model);
  }

  /// AI 客户端 + 模型名（用于助读对话）；未配置返回 null。
  (LlmClient, String)? _llm() {
    final s = widget.settings;
    if (!s.aiEnabled) return null;
    if (s.providerType == 'openai') {
      if (s.openaiApiKey.isEmpty || s.openaiModel.isEmpty) return null;
      return (
        OpenAiCompatClient(baseUrl: s.openaiBaseUrl, apiKey: s.openaiApiKey),
        s.openaiModel
      );
    }
    if (s.model.isEmpty) return null;
    return (OllamaClient(s.ollamaUrl), s.model);
  }

  void _openAssistant() {
    final content = _content;
    if (content == null) return;
    final llm = _llm();
    if (llm == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('尚未配置 AI，请到设置里接入本机模型或填 API Key')));
      return;
    }
    final ch = _chapter;
    // 当前位置附近的正文（前后几段）作为语境
    final around = ch == null
        ? ''
        : ch.paragraphs
            .skip((_anchorPara - 1).clamp(0, ch.paragraphs.length))
            .take(5)
            .join('\n');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: AssistantPanel(
            client: llm.$1,
            model: llm.$2,
            bookTitle: content.title,
            author: content.author,
            currentChapter: ch?.title ?? '',
            currentExcerpt: around,
            profile: widget.settings.profile,
          ),
        ),
      ),
    );
  }

  void _runAi({required bool translate}) {
    final selected = _selectedText.trim();
    if (selected.isEmpty) return;
    final para = _locateParagraph(selected);
    final ch = _chapter;
    if (ch == null) return;
    ContextMenuController.removeAny();

    final svc = _service();
    if (svc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('AI 未就绪：请到设置中检查 Ollama 连接与模型（或 AI 已被关闭）。')));
      return;
    }

    // D9 术语一致性：查找本书内相同/相近选文的既有解释，注入提示词
    String? prior;
    if (!translate) {
      final norm = selected.replaceAll(RegExp(r'\s+'), '');
      for (final e in _state.explanations.reversed) {
        if (e.mode != 'explain') continue;
        final t = e.term.replaceAll(RegExp(r'\s+'), '');
        if (t == norm || t.contains(norm) || norm.contains(t)) {
          prior = e.resultText;
          break;
        }
      }
    }

    final session = translate
        ? svc.translateSession(selected)
        : svc.explainSession(
            bookTitle: _content!.title,
            chapter: ch,
            paragraphIndex: para ?? 0,
            selectedText: selected,
            profile: widget.settings.profile,
            priorExplanation: prior,
          );

    _showPanel(ExplainPanel(
      title: translate ? 'AI 翻译' : 'AI 解释',
      quotedText: selected,
      session: session,
      onFirstAnswer: (full) => _persistExplanation(
          para: para, selected: selected, result: full, translate: translate),
      onClose: _closePanel,
    ));
  }

  Future<void> _persistExplanation({
    required int? para,
    required String selected,
    required String result,
    required bool translate,
  }) async {
    final loc = Locator(_chapterIndex, para ?? 0);
    final ch = _chapter!;
    _state.explanations.add(Explanation(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      locator: loc,
      term: selected.length > 80 ? selected.substring(0, 80) : selected,
      contextExcerpt: ExplainService.buildContext(ch, para ?? 0, selected),
      resultText: result,
      mode: translate ? 'translate' : 'explain',
      createdAt: DateTime.now(),
    ));
    await widget.store.saveState(widget.book.id, _state);
    if (mounted) setState(() {});
  }

  void _openSaved(int para) {
    final list = _explanationsAt(para);
    if (list.isEmpty) return;
    final e = list.first;
    _showPanel(ExplainPanel(
      title: e.mode == 'translate' ? 'AI 翻译' : 'AI 解释',
      quotedText: e.term,
      savedText: list.length > 1
          ? '${e.resultText}\n\n——共 ${list.length} 条留存，此为最新（概念本可看全部）——'
          : e.resultText,
      onClose: _closePanel,
    ));
  }

  // ---------- 笔记与书签（C6） ----------

  Future<void> _addNote() async {
    final para = _locateParagraph(_selectedText);
    if (para == null) return;
    ContextMenuController.removeAny();
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加笔记'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: '写点想法…', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    setState(() {
      _state.notes.add(NoteAnn(
          locator: Locator(_chapterIndex, para),
          text: text,
          createdAt: DateTime.now()));
    });
    await widget.store.saveState(widget.book.id, _state);
  }

  List<NoteAnn> _notesAt(int para) {
    final loc = Locator(_chapterIndex, para);
    return _state.notes.where((n) => n.locator == loc).toList();
  }

  Future<void> _toggleBookmark() async {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    // 同章 ±200px 内已有书签 → 视为取消
    final existing = _state.bookmarks
        .where((b) =>
            b.chapterIndex == _chapterIndex &&
            (b.scrollOffset - offset).abs() < 200)
        .toList();
    setState(() {
      if (existing.isNotEmpty) {
        _state.bookmarks.removeWhere((b) => existing.contains(b));
      } else {
        _state.bookmarks.add(Bookmark(
            chapterIndex: _chapterIndex,
            scrollOffset: offset,
            label: '',
            createdAt: DateTime.now()));
      }
    });
    await widget.store.saveState(widget.book.id, _state);
  }

  bool get _bookmarkedHere {
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    return _state.bookmarks.any((b) =>
        b.chapterIndex == _chapterIndex &&
        (b.scrollOffset - offset).abs() < 200);
  }

  void _showNotes(int para) {
    final notes = _notesAt(para);
    if (notes.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('本段笔记', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...notes.map((n) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.sticky_note_2_outlined, size: 18),
                  title: Text(n.text),
                  subtitle:
                      Text(n.createdAt.toLocal().toString().substring(0, 16)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      setState(() => _state.notes.remove(n));
                      await widget.store.saveState(widget.book.id, _state);
                      if (mounted) Navigator.of(context).pop();
                    },
                  ),
                )),
          ],
        ),
      ),
    );
  }

  // ---------- 批量翻译（G2/G4） ----------

  Future<void> _startBatchTranslate() async {
    final svc = _service();
    final content = _content;
    if (svc == null || content == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('AI 未就绪，无法批量翻译。')));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全书批量翻译'),
        content: Text(
          '将用本地模型（${widget.settings.model}）把整本书逐段翻译为中文，'
          '零 API 费用，但需要较长时间（可挂机，可随时暂停，断点续跑）。\n\n'
          '注意：本地模型译文为「辅助理解级」，非出版级。\n'
          '共 ${content.chapters.fold(0, (n, c) => n + c.paragraphs.length)} 段，'
          '已完成 ${_translation.paras.length} 段。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始/继续')),
        ],
      ),
    );
    if (go != true) return;

    final svcForBatch = _service()!;
    _batch = BatchTranslator(
      client: svcForBatch.client,
      model: svcForBatch.model,
      store: _tStore,
      bookId: widget.book.id,
      book: content,
    );
    _batch!.status.addListener(() async {
      if (!mounted) return;
      if (_batch!.status.value == BatchStatus.completed ||
          _batch!.status.value == BatchStatus.paused ||
          _batch!.status.value == BatchStatus.error) {
        _translation = await _tStore.load(widget.book.id);
        if (mounted) setState(() {});
      }
    });
    setState(() {});
    unawaited(_batch!.run());
  }

  // ---------- 面板容器 ----------

  bool get _wide => MediaQuery.of(context).size.width >= 900;

  void _showPanel(Widget panel) {
    if (_wide) {
      setState(() => _sidePanel = panel);
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.66),
        builder: (_) => SafeArea(child: panel),
      );
    }
  }

  void _closePanel() {
    if (_wide) {
      setState(() => _sidePanel = null);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ---------- 导航 ----------

  void _goto(int index, {int? paragraph}) {
    final content = _content;
    if (content == null) return;
    setState(() {
      _chapterIndex = index.clamp(0, content.chapters.length - 1);
      _anchorPara = paragraph ?? 0;
      _pages = null; // 换章重新分页
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // 段落级跳转（概念本回跳）：MVP 用固定估算滚动，V1 换精确测量
    if (paragraph != null && paragraph > 0 && _scroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target =
            (paragraph * 90.0).clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(target);
      });
    }
    _saveProgress();
  }

  // ---------- 构建 ----------

  ReaderPaper get _paper => readerPapers[
      widget.settings.readerTheme.clamp(0, readerPapers.length - 1)];

  Color? _readerBackground(BuildContext context) => _paper.bg;

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: Center(
            child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('这本书打不开：$_loadError'),
        )),
      );
    }
    final content = _content;
    final ch = _chapter;
    if (content == null || ch == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.book.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final s = widget.settings;
    final hasAnyTranslation = _translation.paras.isNotEmpty;

    return Scaffold(
      backgroundColor: _readerBackground(context),
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回书架',
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('${content.title} · ${ch.title}',
            overflow: TextOverflow.ellipsis),
        actions: [
          Builder(
            builder: (ctx) => IconButton(
              tooltip: '目录',
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          if (hasAnyTranslation)
            PopupMenuButton<DisplayMode>(
              tooltip: '显示模式（原文/译文/对照）',
              icon: const Icon(Icons.translate),
              initialValue: _mode,
              onSelected: (m) => setState(() => _mode = m),
              itemBuilder: (_) => const [
                PopupMenuItem(value: DisplayMode.original, child: Text('原文')),
                PopupMenuItem(value: DisplayMode.translated, child: Text('译文')),
                PopupMenuItem(
                    value: DisplayMode.bilingual, child: Text('双语对照')),
              ],
            ),
          IconButton(
            tooltip: '书内搜索',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SearchInBookScreen(
                book: content,
                onJump: (c, p) => _goto(c, paragraph: p),
              ),
            )),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _tts.playing,
            builder: (_, playing, __) => IconButton(
              tooltip: '朗读',
              icon: Icon(playing ? Icons.headset : Icons.headphones_outlined),
              onPressed: () => _openTtsSheet(content),
            ),
          ),
          if (widget.settings.aiEnabled)
            IconButton(
              tooltip: '问这本书',
              icon: const Icon(Icons.forum_outlined),
              onPressed: _openAssistant,
            ),
          IconButton(
            tooltip: _bookmarkedHere ? '取消书签' : '添加书签',
            icon:
                Icon(_bookmarkedHere ? Icons.bookmark : Icons.bookmark_outline),
            onPressed: _toggleBookmark,
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) async {
              switch (v) {
                case 'batch':
                  _startBatchTranslate();
                case 'pause':
                  _batch?.pause();
                case 'typo':
                  _showTypography();
                case 'mode':
                  setState(() {
                    final toPage = widget.settings.readingMode != 'page';
                    if (toPage && _scroll.hasClients) {
                      // 滚动 → 翻页：用滚动位置估算段落锚点（±1 段可接受）
                      _anchorPara = (_scroll.offset / 90.0).floor();
                    }
                    widget.settings.readingMode = toPage ? 'page' : 'scroll';
                    _pages = null;
                  });
                  _saveProgress();
                case 'concepts':
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ConceptsScreen(
                      bookTitle: content.title,
                      explanations: _state.explanations,
                      onJump: (loc) =>
                          _goto(loc.chapter, paragraph: loc.paragraph),
                    ),
                  ));
                case 'annotations':
                  await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AnnotationsScreen(
                      bookTitle: content.title,
                      state: _state,
                      chapterTitleOf: (i) => content.chapters[i].title,
                      onJump: (c, {paragraph, offset}) {
                        _goto(c, paragraph: paragraph);
                        if (offset != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scroll.hasClients) {
                              _scroll.jumpTo(offset.clamp(
                                  0, _scroll.position.maxScrollExtent));
                            }
                          });
                        }
                      },
                      onChanged: () =>
                          widget.store.saveState(widget.book.id, _state),
                    ),
                  ));
                  if (mounted) setState(() {});
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'annotations', child: Text('标注（书签/笔记/高亮）')),
              const PopupMenuItem(value: 'concepts', child: Text('概念本')),
              const PopupMenuItem(value: 'typo', child: Text('排版设置')),
              PopupMenuItem(
                  value: 'mode',
                  child: Text(widget.settings.readingMode == 'page'
                      ? '切换为上下滚动'
                      : '切换为左右翻页')),
              PopupMenuItem(
                  value: 'batch',
                  child: Text(_translation.completed
                      ? '重新检查批量翻译'
                      : '全书批量翻译${_translation.paras.isNotEmpty ? '（续跑）' : ''}')),
              if (_batch?.status.value == BatchStatus.running)
                const PopupMenuItem(value: 'pause', child: Text('暂停翻译')),
            ],
          ),
          IconButton(
            tooltip: '上一章',
            onPressed:
                _chapterIndex > 0 ? () => _goto(_chapterIndex - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '下一章',
            onPressed: _chapterIndex < content.chapters.length - 1
                ? () => _goto(_chapterIndex + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView.builder(
            itemCount: content.chapters.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              selected: i == _chapterIndex,
              title: Text(content.chapters[i].title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                _goto(i);
              },
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_batch != null)
            ValueListenableBuilder<BatchStatus>(
              valueListenable: _batch!.status,
              builder: (_, st, __) {
                if (st == BatchStatus.idle) return const SizedBox.shrink();
                return ValueListenableBuilder<double>(
                  valueListenable: _batch!.progress,
                  builder: (_, p, __) => Column(
                    children: [
                      LinearProgressIndicator(value: p, minHeight: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              switch (st) {
                                BatchStatus.running =>
                                  '批量翻译中 ${(p * 100).toStringAsFixed(1)}%（可关书，进度已实时落盘）',
                                BatchStatus.paused => '翻译已暂停（下次可续跑）',
                                BatchStatus.completed => '全书翻译完成 ✓',
                                BatchStatus.error =>
                                  '翻译出错：${_batch!.lastError.value}',
                                _ => '',
                              },
                              style: const TextStyle(fontSize: 12),
                            ),
                            const Spacer(),
                            if (st == BatchStatus.running)
                              TextButton(
                                  onPressed: () => _batch!.pause(),
                                  child: const Text('暂停',
                                      style: TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // 章节切换柔和过渡（淡入 + 轻上移；跟随系统减弱动效）
                      AnimatedSwitcher(
                        duration: reduceMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween(
                                    begin: const Offset(0, 0.015),
                                    end: Offset.zero)
                                .animate(anim),
                            child: child,
                          ),
                        ),
                        child: KeyedSubtree(
                          key: ValueKey('ch$_chapterIndex'),
                          child: _readerBody(ch, s),
                        ),
                      ),
                      // 划选后自动浮出的操作条（免右键，动效 L2）
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 18,
                        child: IgnorePointer(
                          ignoring: !_selBarVisible,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            offset: _selBarVisible
                                ? Offset.zero
                                : const Offset(0, 1.6),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _selBarVisible ? 1 : 0,
                              child: Center(child: _selectionBar(context)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 宽屏解释侧栏：滑入/滑出动效
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween<Offset>(
                            begin: const Offset(1, 0), end: Offset.zero)
                        .animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: (_wide && _sidePanel != null)
                      ? Container(
                          key: ValueKey(_sidePanel.hashCode),
                          width: 360,
                          decoration: BoxDecoration(
                            border: Border(
                                left: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                    width: 0.5)),
                          ),
                          child: _sidePanel,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 划选后浮出的快捷操作条（比右键菜单更顺手的主路径）。
  // ---------- TTS 朗读 ----------

  Future<void> _startTts(int fromPara) async {
    final ch = _chapter;
    if (ch == null) return;
    await _tts.start(
      ch.paragraphs,
      fromPara,
      onAdvance: () {
        // 朗读推进时，若当前段落已滚出视口可自动跟随（滚动模式）
        if (widget.settings.readingMode != 'page') {
          final i = _tts.currentPara.value;
          if (i >= 0 && _scroll.hasClients) {
            final target = (i * 90.0)
                .clamp(0.0, _scroll.position.maxScrollExtent);
            _scroll.animateTo(target,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut);
          }
        }
      },
      onChapterEnd: () async {
        // 读完本章：有下一章则续接
        final content = _content;
        if (content != null && _chapterIndex < content.chapters.length - 1) {
          _goto(_chapterIndex + 1);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          _tts.updateParas(_chapter?.paragraphs ?? []);
          return true;
        }
        return false;
      },
    );
  }

  void _applyTtsProvider() {
    final s = widget.settings;
    if (s.ttsProvider == 'doubao') {
      _tts.configureDoubao(
          appId: s.doubaoAppId, token: s.doubaoToken, voice: s.doubaoVoice);
    } else {
      _tts.configureDoubao(); // 清空 = 回系统 TTS
    }
  }

  Future<void> _openTtsSheet(LoadedBook content) async {
    await _tts.init();
    _applyTtsProvider();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('朗读', style: Theme.of(ctx).textTheme.titleMedium),
                    const Spacer(),
                    ValueListenableBuilder<Duration?>(
                      valueListenable: _tts.sleepRemaining,
                      builder: (_, r, __) => r == null
                          ? const SizedBox.shrink()
                          : Text('定时 ${r.inMinutes}:${(r.inSeconds % 60).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Theme.of(ctx).colorScheme.primary)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 引擎选择：系统（免费）/ 豆包语音大模型（自备 Key）
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('系统语音')),
                    ButtonSegment(value: 'doubao', label: Text('豆包语音大模型')),
                  ],
                  selected: {widget.settings.ttsProvider},
                  onSelectionChanged: (sel) {
                    widget.settings.ttsProvider = sel.first;
                    _tts.stop();
                    _applyTtsProvider();
                    setSheet(() {});
                  },
                ),
                if (widget.settings.ttsProvider == 'doubao') ...[
                  const SizedBox(height: 10),
                  if (widget.settings.doubaoAppId.isEmpty ||
                      widget.settings.doubaoToken.isEmpty)
                    Text(
                      '需要火山引擎「豆包语音」的 AppID 与 Access Token'
                      '（console.volcengine.com 开通，有免费额度）。'
                      '仅使用官方授权音色库，不支持克隆任何真人声音。',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: Theme.of(ctx).colorScheme.outline),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(
                        text: widget.settings.doubaoAppId),
                    decoration: const InputDecoration(
                        labelText: 'AppID',
                        isDense: true,
                        border: OutlineInputBorder()),
                    onChanged: (v) => widget.settings.doubaoAppId = v,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(
                        text: widget.settings.doubaoToken),
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Access Token',
                        isDense: true,
                        border: OutlineInputBorder()),
                    onChanged: (v) => widget.settings.doubaoToken = v,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // 一键预设：清甜温柔（婉婉小荷 + 语速0.94 + 音高1.25）
                      ActionChip(
                        avatar: const Icon(Icons.auto_fix_high, size: 15),
                        label: const Text('清甜温柔预设',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          const p = DoubaoTtsClient.sweetGentlePreset;
                          widget.settings.doubaoVoice = p.voice;
                          _tts.rate = p.speedRatio / 2; // speed = rate*2
                          _tts.pitch = p.pitchRatio;
                          _applyTtsProvider();
                          _tts.applyParams();
                          setSheet(() {});
                        },
                      ),
                      for (final v in DoubaoTtsClient.presetVoices)
                        ChoiceChip(
                          label: Text(v.$2,
                              style: const TextStyle(fontSize: 12)),
                          selected: widget.settings.doubaoVoice == v.$1,
                          onSelected: (_) {
                            widget.settings.doubaoVoice = v.$1;
                            _applyTtsProvider();
                            setSheet(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: TextEditingController(
                        text: DoubaoTtsClient.presetVoices
                                .any((v) => v.$1 == widget.settings.doubaoVoice)
                            ? ''
                            : widget.settings.doubaoVoice),
                    decoration: const InputDecoration(
                        labelText: '自定义音色代码（可选，控制台音色列表里复制）',
                        hintText: 'zh_female_..._moon_bigtts',
                        isDense: true,
                        border: OutlineInputBorder()),
                    onChanged: (v) {
                      if (v.trim().isNotEmpty) {
                        widget.settings.doubaoVoice = v.trim();
                        _applyTtsProvider();
                      }
                    },
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _tts.lastError,
                    builder: (_, err, __) => err == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(err,
                                style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(ctx).colorScheme.error)),
                          ),
                  ),
                ],
                const SizedBox(height: 4),
                // 播放控制
                ValueListenableBuilder<bool>(
                  valueListenable: _tts.playing,
                  builder: (_, playing, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filledTonal(
                        iconSize: 32,
                        icon: Icon(playing
                            ? Icons.pause
                            : Icons.play_arrow),
                        onPressed: () {
                          if (playing) {
                            _tts.pause();
                          } else if (_tts.currentPara.value >= 0) {
                            _tts.resume();
                          } else {
                            // 从当前视口首段开始
                            final from = widget.settings.readingMode == 'page'
                                ? _anchorPara
                                : (_scroll.hasClients
                                    ? (_scroll.offset / 90.0).floor()
                                    : 0);
                            _startTts(from);
                          }
                        },
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.stop),
                        onPressed: () => _tts.stop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                // 语速
                Text('语速', style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                Slider(
                  value: _tts.rate,
                  min: 0.2,
                  max: 1.0,
                  onChanged: (v) => setSheet(() => _tts.rate = v),
                  onChangeEnd: (_) => _tts.applyParams(),
                ),
                // 音调
                Text('音调', style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                Slider(
                  value: _tts.pitch,
                  min: 0.5,
                  max: 2.0,
                  onChanged: (v) => setSheet(() => _tts.pitch = v),
                  onChangeEnd: (_) => _tts.applyParams(),
                ),
                // 音色（系统引擎）
                if (widget.settings.ttsProvider == 'system' &&
                    _tts.voices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('音色', style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final v in _tts.voices
                            .where((v) => v['locale']!
                                .toLowerCase()
                                .startsWith('zh'))
                            .take(12))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(v['name']!.split(RegExp(r'[.\-]')).last,
                                  style: const TextStyle(fontSize: 12)),
                              selected: _tts.voiceName == v['name'],
                              onSelected: (_) {
                                setSheet(() => _tts.voiceName = v['name']);
                                _tts.applyParams();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 24),
                // 定时关闭
                Text('定时关闭', style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in [15, 30, 60])
                      ActionChip(
                        label: Text('$m 分钟'),
                        onPressed: () {
                          _tts.setSleep(minutes: m);
                          setSheet(() {});
                        },
                      ),
                    ActionChip(
                      label: const Text('读完本章'),
                      onPressed: () {
                        _tts.setSleep(atChapterEnd: true);
                        setSheet(() {});
                      },
                    ),
                    ActionChip(
                      label: const Text('取消定时'),
                      onPressed: () {
                        _tts.setSleep(minutes: null);
                        setSheet(() {});
                      },
                    ),
                  ],
                ),
                if (widget.settings.ttsProvider == 'system' &&
                    _tts.voices.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '未检测到系统语音引擎。macOS 一般自带；Android 需在系统设置里'
                    '安装 TTS 引擎（如 Google 文字转语音）后重开。',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.outline,
                        height: 1.6),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  /// 书摘分享卡片：选主题 → 预览 → 导出 PNG 到下载目录。
  Future<void> _openShareCard(String quote) async {
    if (quote.isEmpty) return;
    final content = _content;
    final boundaryKey = GlobalKey();
    var themeIdx = widget.settings.readerTheme.clamp(0, 1) == 0 &&
            !(_paper.isDark)
        ? 0
        : 1;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final theme = shareCardThemes[themeIdx];
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('分享书摘', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                // 预览（RepaintBoundary 即导出源）
                RepaintBoundary(
                  key: boundaryKey,
                  child: ShareCard(
                    quote: quote,
                    bookTitle: content?.title ?? widget.book.title,
                    author: content?.author ?? widget.book.author,
                    theme: theme,
                  ),
                ),
                const SizedBox(height: 18),
                // 主题选择
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < shareCardThemes.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: ChoiceChip(
                          label: Text(shareCardThemes[i].name),
                          selected: themeIdx == i,
                          onSelected: (_) => setSheet(() => themeIdx = i),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('保存图片'),
                  onPressed: () async {
                    try {
                      final path = await exportCardPng(
                          boundaryKey, content?.title ?? widget.book.title);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('已保存到：$path')));
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('保存失败：$e')));
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _selectionBar(BuildContext context) {
    final aiOn = widget.settings.aiEnabled;
    final scheme = Theme.of(context).colorScheme;
    Widget action(IconData icon, String label, VoidCallback onTap) {
      return InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 17, color: scheme.onPrimaryContainer),
            const SizedBox(width: 5),
            Text(label,
                style:
                    TextStyle(fontSize: 13, color: scheme.onPrimaryContainer)),
          ]),
        ),
      );
    }

    return Material(
      color: scheme.primaryContainer,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .3),
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (aiOn)
            action(Icons.auto_awesome, 'AI 解释', () {
              _runAi(translate: false);
            }),
          if (aiOn)
            action(Icons.translate, '翻译', () {
              _runAi(translate: true);
            }),
          action(Icons.border_color_outlined, '高亮', () {
            _toggleHighlight(0);
            setState(() => _selBarVisible = false);
          }),
          action(Icons.sticky_note_2_outlined, '笔记', _addNote),
          action(Icons.ios_share, '卡片', () {
            setState(() => _selBarVisible = false);
            _openShareCard(_selectedText.trim());
          }),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close,
                size: 16,
                color: scheme.onPrimaryContainer.withValues(alpha: .6)),
            onPressed: () => setState(() => _selBarVisible = false),
          ),
        ],
      ),
    );
  }

  // —— 翻页模式状态 ——
  List<BookPage>? _pages;
  PaginateSpec? _pagesSpec;
  int _pagesChapter = -1;
  PageController? _pageCtrl;
  int _pageIndex = 0;
  int _anchorPara = 0; // 当前页首段（进度锚点）

  Widget _pagedBody(ChapterText ch, SettingsStore s) {
    return LayoutBuilder(builder: (context, cons) {
      final contentWidth =
          (cons.maxWidth.clamp(0, 720.0)) - s.pageMargin * 2;
      final spec = PaginateSpec(
        width: contentWidth.toDouble(),
        height: cons.maxHeight - 72, // 上下留白 + 页码指示
        fontSize: s.fontSize,
        lineHeight: s.lineHeight,
        letterSpacing: s.letterSpacing,
        paraSpacing: s.paraSpacing,
      );
      if (_pages == null || _pagesSpec != spec || _pagesChapter != _chapterIndex) {
        _pages = paginateChapter(ch, spec);
        _pagesSpec = spec;
        _pagesChapter = _chapterIndex;
        _pageIndex = pageForParagraph(_pages!, _anchorPara);
        _pageCtrl?.dispose();
        _pageCtrl = PageController(initialPage: _pageIndex);
      }
      final pages = _pages!;
      final dim = _paper.fg?.withValues(alpha: .45) ??
          Theme.of(context).colorScheme.outline;

      return Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageCtrl,
              itemCount: pages.length + 1, // 末页 = 章末连读区
              onPageChanged: (p) {
                _pageIndex = p;
                if (p < pages.length) {
                  _anchorPara = pages[p].firstPara;
                }
                _saveProgress();
                setState(() {});
              },
              itemBuilder: (_, p) {
                if (p == pages.length) {
                  return Center(
                      child: SingleChildScrollView(child: _chapterEnd()));
                }
                return Center(
                  child: SizedBox(
                    width: contentWidth.toDouble(),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final slice in pages[p].slices)
                            _paragraph(ch, slice.para, s,
                                subStart: slice.start,
                                subEnd: slice.end == 0 &&
                                        ch.blocks[slice.para].kind ==
                                            ParaKind.image
                                    ? null
                                    : slice.end),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 页码指示 + 翻页按钮（触达目标 ≥ 44）
          SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '上一页',
                  onPressed: _pageIndex > 0
                      ? () => _pageCtrl?.previousPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic)
                      : (_chapterIndex > 0
                          ? () => _goto(_chapterIndex - 1)
                          : null),
                  icon: Icon(Icons.chevron_left, color: dim),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      _pageIndex < pages.length
                          ? '${_pageIndex + 1} / ${pages.length}'
                          : '本章完',
                      style: TextStyle(fontSize: 12, color: dim),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一页',
                  onPressed: _pageIndex < pages.length
                      ? () => _pageCtrl?.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic)
                      : null,
                  icon: Icon(Icons.chevron_right, color: dim),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _readerBody(ChapterText ch, SettingsStore s) {
    return SelectionArea(
      onSelectionChanged: (c) {
        _selectedText = c?.plainText ?? '';
        final has = _selectedText.trim().isNotEmpty;
        if (has != _selBarVisible) {
          setState(() => _selBarVisible = has);
        }
      },
      contextMenuBuilder: (context, state) {
        final aiOn = widget.settings.aiEnabled;
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            if (aiOn)
              ContextMenuButtonItem(
                  label: 'AI 解释', onPressed: () => _runAi(translate: false)),
            if (aiOn)
              ContextMenuButtonItem(
                  label: 'AI 翻译', onPressed: () => _runAi(translate: true)),
            ContextMenuButtonItem(
                label: '高亮',
                onPressed: () {
                  ContextMenuController.removeAny();
                  _toggleHighlight(0);
                }),
            ContextMenuButtonItem(label: '笔记', onPressed: _addNote),
            ContextMenuButtonItem(
                label: '卡片',
                onPressed: () {
                  ContextMenuController.removeAny();
                  _openShareCard(_selectedText.trim());
                }),
            ...state.contextMenuButtonItems,
          ],
        );
      },
      child: widget.settings.readingMode == 'page'
          ? _pagedBody(ch, s)
          : Scrollbar(
              controller: _scroll,
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.symmetric(
                    horizontal: s.pageMargin, vertical: 20),
                itemCount: ch.paragraphs.length + 1,
                itemBuilder: (_, i) => i < ch.paragraphs.length
                    ? _paragraph(ch, i, s)
                    : _chapterEnd(),
              ),
            ),
    );
  }

  /// 章末连读区：读完一章不必去目录，直接点大按钮进下一章（C2 连续阅读）。
  Widget _chapterEnd() {
    final content = _content;
    if (content == null) return const SizedBox.shrink();
    final hasNext = _chapterIndex < content.chapters.length - 1;
    final hasPrev = _chapterIndex > 0;
    final dim = _paper.fg?.withValues(alpha: .45) ??
        Theme.of(context).colorScheme.outline;

    Widget rule() => Expanded(child: Divider(color: dim.withValues(alpha: .4)));

    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 72),
      child: Column(
        children: [
          Row(children: [
            rule(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(hasNext ? '本章完' : '全书完',
                  style: TextStyle(fontSize: 12, color: dim, letterSpacing: 2)),
            ),
            rule(),
          ]),
          const SizedBox(height: 24),
          if (hasNext)
            FilledButton.tonalIcon(
              onPressed: () => _goto(_chapterIndex + 1),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(
                '继续阅读：${content.chapters[_chapterIndex + 1].title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            Text('— 感谢阅读 —', style: TextStyle(color: dim)),
          if (hasPrev) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => _goto(_chapterIndex - 1),
              child: Text('← 回看上一章', style: TextStyle(color: dim, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  /// 富文本渲染：把粗体 / 斜体 / 句级高亮范围合成分段 TextSpan。
  /// 范围均为该 text 内的半开区间；hls 为 (start, end, colorIndex)。
  Widget _spansText(
    String text, {
    required TextStyle style,
    List<(int, int)> bold = const [],
    List<(int, int)> italic = const [],
    List<(int, int, int)> hls = const [],
  }) {
    if (bold.isEmpty && italic.isEmpty && hls.isEmpty) {
      return Text(text, style: style);
    }
    final n = text.length;
    final cuts = <int>{0, n};
    for (final r in bold) {
      cuts.addAll([r.$1.clamp(0, n), r.$2.clamp(0, n)]);
    }
    for (final r in italic) {
      cuts.addAll([r.$1.clamp(0, n), r.$2.clamp(0, n)]);
    }
    for (final r in hls) {
      cuts.addAll([r.$1.clamp(0, n), r.$2.clamp(0, n)]);
    }
    final points = cuts.toList()..sort();
    final spans = <TextSpan>[];
    for (var k = 0; k + 1 < points.length; k++) {
      final a = points[k], b = points[k + 1];
      if (b <= a) continue;
      final isBold = bold.any((r) => r.$1 <= a && b <= r.$2);
      final isItalic = italic.any((r) => r.$1 <= a && b <= r.$2);
      final hl = hls.where((r) => r.$1 <= a && b <= r.$2).firstOrNull;
      spans.add(TextSpan(
        text: text.substring(a, b),
        style: TextStyle(
          fontWeight: isBold ? FontWeight.w600 : null, // 中文加粗上限 600
          fontStyle: isItalic ? FontStyle.italic : null,
          backgroundColor: hl != null
              ? highlightColors[hl.$3 % highlightColors.length]
              : null,
        ),
      ));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  /// 渲染一个段落块；[subStart]/[subEnd] 用于翻页模式的跨页切片。
  Widget _paragraph(ChapterText ch, int i, SettingsStore s,
      {int subStart = 0, int? subEnd}) {
    final block = i < ch.blocks.length
        ? ch.blocks[i]
        : ParaBlock(text: ch.paragraphs[i]);

    // 书内插图
    if (block.kind == ParaKind.image) {
      final name = block.image?.split('/').last.toLowerCase();
      final bytes = name == null ? null : _content?.images[name];
      if (bytes == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes,
                fit: BoxFit.contain,
                // 翻页模式按占位高度约束，滚动模式给上限
                height: 320,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ),
      );
    }

    final fullText = block.text;
    final sliceEnd = (subEnd ?? fullText.length).clamp(0, fullText.length);
    final sliceStart = subStart.clamp(0, sliceEnd);
    final isFullPara = sliceStart == 0 && sliceEnd == fullText.length;
    final text = fullText.substring(sliceStart, sliceEnd);

    List<(int, int)> clip(List<(int, int)> rs) => [
          for (final r in rs)
            if (r.$2 > sliceStart && r.$1 < sliceEnd)
              (
                (r.$1 - sliceStart).clamp(0, text.length),
                (r.$2 - sliceStart).clamp(0, text.length)
              )
        ];

    final allHls = _highlightsAt(i);
    final hl = allHls.where((h) => !h.isRange).firstOrNull; // 整段高亮（旧数据）
    final rangeHls = [
      for (final h in allHls.where((h) => h.isRange))
        if (h.end! > sliceStart && h.start! < sliceEnd)
          (
            (h.start! - sliceStart).clamp(0, text.length),
            (h.end! - sliceStart).clamp(0, text.length),
            h.colorIndex
          )
    ];
    final boldRs = clip(block.bold);
    final italicRs = clip(block.italic);
    final hasExplain = isFullPara && _explanationsAt(i).isNotEmpty;
    final hasNote = isFullPara && _notesAt(i).isNotEmpty;
    final translated = isFullPara ? _translation.of(_chapterIndex, i) : null;

    // 正文用衬线字体（书感）；系统无宋体时逐级回退
    const serifFallback = [
      'Songti SC',
      'STSong',
      'Noto Serif SC',
      'Source Han Serif SC',
      'serif',
    ];
    final paperFg = _paper.fg;
    // 标题分级：字号增量与字重同 paginator._styleFor 保持一致（分页测量依赖）
    final (sizeDelta, weight, height) = switch (block.kind) {
      ParaKind.h1 => (8.0, FontWeight.w600, 1.4),
      ParaKind.h2 => (5.0, FontWeight.w600, 1.4),
      ParaKind.h3 => (3.0, FontWeight.w600, 1.4),
      _ => (0.0, FontWeight.w400, s.lineHeight),
    };
    final baseStyle = TextStyle(
      fontSize: s.fontSize + sizeDelta,
      height: height,
      fontWeight: weight,
      fontFamilyFallback: serifFallback,
      letterSpacing: s.letterSpacing,
      color: block.kind == ParaKind.quote
          ? paperFg?.withValues(alpha: .78)
          : paperFg,
    );
    // 中文正文首行缩进两字（标题/引用/图不缩进）
    final indent = (s.firstLineIndent &&
            block.kind == ParaKind.body &&
            isFullPara &&
            RegExp(r'^[一-鿿]').hasMatch(text))
        ? '　　'
        : '';
    final dimStyle = TextStyle(
      fontSize: s.fontSize - 1,
      height: s.lineHeight,
      fontFamilyFallback: serifFallback,
      color: paperFg?.withValues(alpha: .55) ??
          Theme.of(context).colorScheme.outline,
    );

    // 原文渲染：粗斜体 + 句级高亮合成
    final shift = indent.length;
    List<(int, int)> off2(List<(int, int)> rs) =>
        shift == 0 ? rs : [for (final r in rs) (r.$1 + shift, r.$2 + shift)];
    List<(int, int, int)> off3(List<(int, int, int)> rs) => shift == 0
        ? rs
        : [for (final r in rs) (r.$1 + shift, r.$2 + shift, r.$3)];
    Widget original(TextStyle style) => _spansText(indent + text,
        style: style,
        bold: off2(boldRs),
        italic: off2(italicRs),
        hls: off3(rangeHls));

    Widget body;
    switch (_mode) {
      case DisplayMode.original:
        body = original(baseStyle);
      case DisplayMode.translated:
        body = translated != null
            ? Text(translated, style: baseStyle)
            : original(dimStyle);
      case DisplayMode.bilingual:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            original(baseStyle),
            if (translated != null) ...[
              const SizedBox(height: 4),
              Text(translated, style: dimStyle),
            ],
          ],
        );
    }

    // 引用块：左侧竖线 + 缩进（对齐主流阅读器的 blockquote 处理）
    if (block.kind == ParaKind.quote) {
      body = Container(
        padding: const EdgeInsets.fromLTRB(14, 2, 0, 2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: (paperFg ?? Theme.of(context).colorScheme.outline)
                  .withValues(alpha: .35),
              width: 3,
            ),
          ),
        ),
        child: body,
      );
    }

    // 朗读到本段：整段浅色底提示
    final isReading = isFullPara && _tts.currentPara.value == i;
    return Padding(
      padding: EdgeInsets.only(bottom: s.paraSpacing),
      child: Container(
        decoration: hl != null
            ? BoxDecoration(
                color: highlightColors[hl.colorIndex % highlightColors.length],
                borderRadius: BorderRadius.circular(4))
            : (isReading
                ? BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(4))
                : null),
        padding: (hl != null || isReading)
            ? const EdgeInsets.symmetric(horizontal: 4, vertical: 2)
            : null,
        child: (hasExplain || hasNote)
            ? Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  body,
                  if (hasExplain)
                    GestureDetector(
                      onTap: () => _openSaved(i),
                      // ✦ 锚点出现时的弹性缩放动效（L2）
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.4, end: 1.0),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.elasticOut,
                        builder: (_, v, child) =>
                            Transform.scale(scale: v, child: child),
                        child: Container(
                          margin: const EdgeInsets.only(left: 6, bottom: 2),
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Theme.of(context).colorScheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: .4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Text('✦',
                              style:
                                  TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                      ),
                    ),
                  if (hasNote)
                    GestureDetector(
                      onTap: () => _showNotes(i),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: Icon(Icons.sticky_note_2,
                            size: 16,
                            color: Theme.of(context).colorScheme.tertiary),
                      ),
                    ),
                ],
              )
            : body,
      ),
    );
  }

  void _showTypography() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final s = widget.settings;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('排版设置', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 72, child: Text('字号')),
                  Expanded(
                    child: Slider(
                      value: s.fontSize,
                      min: 13,
                      max: 26,
                      divisions: 13,
                      label: s.fontSize.toStringAsFixed(0),
                      onChanged: (v) {
                        s.fontSize = v;
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                  ),
                ]),
                Row(children: [
                  const SizedBox(width: 72, child: Text('行距')),
                  Expanded(
                    child: Slider(
                      value: s.lineHeight,
                      min: 1.4,
                      max: 2.6,
                      divisions: 12,
                      label: s.lineHeight.toStringAsFixed(1),
                      onChanged: (v) {
                        s.lineHeight = v;
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                  ),
                ]),
                Row(children: [
                  const SizedBox(width: 72, child: Text('页边距')),
                  Expanded(
                    child: Slider(
                      value: s.pageMargin,
                      min: 12,
                      max: 80,
                      divisions: 17,
                      label: s.pageMargin.toStringAsFixed(0),
                      onChanged: (v) {
                        s.pageMargin = v;
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                  ),
                ]),
                Row(children: [
                  const SizedBox(width: 72, child: Text('字间距')),
                  Expanded(
                    child: Slider(
                      value: s.letterSpacing,
                      min: 0,
                      max: 3,
                      divisions: 15,
                      label: s.letterSpacing.toStringAsFixed(1),
                      onChanged: (v) {
                        s.letterSpacing = v;
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                  ),
                ]),
                Row(children: [
                  const SizedBox(width: 72, child: Text('段间距')),
                  Expanded(
                    child: Slider(
                      value: s.paraSpacing,
                      min: 6,
                      max: 40,
                      divisions: 17,
                      label: s.paraSpacing.toStringAsFixed(0),
                      onChanged: (v) {
                        s.paraSpacing = v;
                        setSheet(() {});
                        setState(() {});
                      },
                    ),
                  ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('中文段落首行缩进'),
                  value: s.firstLineIndent,
                  onChanged: (v) {
                    s.firstLineIndent = v;
                    setSheet(() {});
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                        width: 72,
                        child: Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text('纸张'))),
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (var i = 0; i < readerPapers.length; i++)
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                s.readerTheme = i;
                                setSheet(() {});
                                setState(() {});
                              },
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: readerPapers[i].bg ??
                                          Theme.of(ctx)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                      border: Border.all(
                                        width: s.readerTheme == i ? 3 : 1,
                                        color: s.readerTheme == i
                                            ? Theme.of(ctx).colorScheme.primary
                                            : Theme.of(ctx).dividerColor,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('文',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: readerPapers[i].fg ??
                                                Theme.of(ctx)
                                                    .colorScheme
                                                    .onSurface)),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(readerPapers[i].name,
                                      style: const TextStyle(fontSize: 10)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
