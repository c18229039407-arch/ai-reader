import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/batch_translator.dart';
import '../../services/epub_loader.dart';
import '../../services/explain_service.dart';
import '../../services/library_store.dart';
import '../../services/llm_client.dart';
import '../../services/ollama_client.dart';
import '../../services/settings_store.dart';
import '../../services/translation_store.dart';
import 'annotations_screen.dart';
import 'concepts_screen.dart';
import 'explain_panel.dart';
import 'reader_papers.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(_onScroll);
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
        // 新书首次打开：跳过封面/版权等零碎前页，直达第一个有正文的章节
        if (state.reading.chapterIndex == 0 &&
            state.reading.scrollOffset == 0) {
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
    final frac = _scroll.hasClients && _scroll.position.maxScrollExtent > 0
        ? _scroll.offset / _scroll.position.maxScrollExtent
        : 0.0;
    _state.reading = ReadingState(
      chapterIndex: _chapterIndex,
      scrollOffset: _scroll.hasClients ? _scroll.offset : 0,
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
    _batch?.pause();
    _scroll.dispose();
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
    setState(() => _chapterIndex = index.clamp(0, content.chapters.length - 1));
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
                      _readerBody(ch, s),
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
            ...state.contextMenuButtonItems,
          ],
        );
      },
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.symmetric(horizontal: s.pageMargin, vertical: 20),
          itemCount: ch.paragraphs.length + 1,
          itemBuilder: (_, i) =>
              i < ch.paragraphs.length ? _paragraph(ch, i, s) : _chapterEnd(),
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

  /// 句级高亮渲染：把段落文本按高亮范围切成 TextSpan。
  Widget _richText(String text, List<Highlight> ranges, TextStyle style) {
    final marks = ranges
        .where((h) => h.start != null && h.start! < text.length)
        .map((h) => (
              h.start!.clamp(0, text.length),
              h.end!.clamp(0, text.length),
              h.colorIndex
            ))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <TextSpan>[];
    var pos = 0;
    for (final m in marks) {
      final start = m.$1 < pos ? pos : m.$1;
      final end = m.$2;
      if (end <= pos) continue;
      if (start > pos) spans.add(TextSpan(text: text.substring(pos, start)));
      spans.add(TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
              backgroundColor:
                  highlightColors[m.$3 % highlightColors.length])));
      pos = end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return Text.rich(TextSpan(style: style, children: spans));
  }

  Widget _paragraph(ChapterText ch, int i, SettingsStore s) {
    final allHls = _highlightsAt(i);
    final hl = allHls.where((h) => !h.isRange).firstOrNull; // 整段高亮（旧数据）
    final rangeHls = allHls.where((h) => h.isRange).toList(); // 句级高亮
    final hasExplain = _explanationsAt(i).isNotEmpty;
    final hasNote = _notesAt(i).isNotEmpty;
    final translated = _translation.of(_chapterIndex, i);

    // 正文用衬线字体（书感）；系统无宋体时逐级回退
    const serifFallback = [
      'Songti SC',
      'STSong',
      'Noto Serif SC',
      'Source Han Serif SC',
      'serif',
    ];
    final paperFg = _paper.fg;
    final baseStyle = TextStyle(
      fontSize: s.fontSize,
      height: s.lineHeight,
      fontFamilyFallback: serifFallback,
      letterSpacing: 0.2,
      color: paperFg,
    );
    final dimStyle = TextStyle(
      fontSize: s.fontSize - 1,
      height: s.lineHeight,
      fontFamilyFallback: serifFallback,
      color: paperFg?.withValues(alpha: .55) ??
          Theme.of(context).colorScheme.outline,
    );

    // 原文渲染：有句级高亮时用富文本按范围着色
    Widget original(TextStyle style) => rangeHls.isEmpty
        ? Text(ch.paragraphs[i], style: style)
        : _richText(ch.paragraphs[i], rangeHls, style);

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

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        decoration: hl != null
            ? BoxDecoration(
                color: highlightColors[hl.colorIndex % highlightColors.length],
                borderRadius: BorderRadius.circular(4))
            : null,
        padding: hl != null ? const EdgeInsets.symmetric(horizontal: 4) : null,
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
