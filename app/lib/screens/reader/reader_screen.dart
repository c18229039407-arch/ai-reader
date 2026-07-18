import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/batch_translator.dart';
import '../../services/epub_loader.dart';
import '../../services/explain_service.dart';
import '../../services/library_store.dart';
import '../../services/ollama_client.dart';
import '../../services/settings_store.dart';
import '../../services/translation_store.dart';
import 'concepts_screen.dart';
import 'explain_panel.dart';

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

  Highlight? _highlightAt(int para) {
    final loc = Locator(_chapterIndex, para);
    for (final h in _state.highlights) {
      if (h.locator == loc) return h;
    }
    return null;
  }

  List<Explanation> _explanationsAt(int para) {
    final loc = Locator(_chapterIndex, para);
    return _state.explanations.where((e) => e.locator == loc).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _toggleHighlight(int colorIndex) async {
    final para = _locateParagraph(_selectedText);
    if (para == null) return;
    final existing = _highlightAt(para);
    setState(() {
      if (existing != null) {
        _state.highlights.remove(existing);
      } else {
        _state.highlights.add(Highlight(
            locator: Locator(_chapterIndex, para),
            colorIndex: colorIndex,
            createdAt: DateTime.now()));
      }
    });
    await widget.store.saveState(widget.book.id, _state);
  }

  // ---------- AI ----------

  ExplainService? _service() {
    if (!widget.settings.aiEnabled) return null;
    final model = widget.settings.model;
    if (model.isEmpty) return null;
    return ExplainService(
        client: OllamaClient(widget.settings.ollamaUrl), model: model);
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

    final session = translate
        ? svc.translateSession(selected)
        : svc.explainSession(
            bookTitle: _content!.title,
            chapter: ch,
            paragraphIndex: para ?? 0,
            selectedText: selected,
            profile: widget.settings.profile,
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

    _batch = BatchTranslator(
      client: OllamaClient(widget.settings.ollamaUrl),
      model: widget.settings.model,
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

  Color? _readerBackground(BuildContext context) {
    if (widget.settings.readerTheme == 3 &&
        Theme.of(context).brightness == Brightness.light) {
      return const Color(0xFFF5ECD9);
    }
    return null;
  }

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
        title: Text('${content.title} · ${ch.title}',
            overflow: TextOverflow.ellipsis),
        actions: [
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
            tooltip: '概念本',
            icon: const Icon(Icons.collections_bookmark_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ConceptsScreen(
                bookTitle: content.title,
                explanations: _state.explanations,
                onJump: (loc) => _goto(loc.chapter, paragraph: loc.paragraph),
              ),
            )),
          ),
          PopupMenuButton<String>(
            tooltip: '更多',
            onSelected: (v) {
              if (v == 'batch') _startBatchTranslate();
              if (v == 'pause') _batch?.pause();
              if (v == 'typo') _showTypography();
            },
            itemBuilder: (_) => [
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
                Expanded(child: _readerBody(ch, s)),
                if (_wide && _sidePanel != null)
                  Container(
                    width: 360,
                    decoration: BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: Theme.of(context).dividerColor,
                              width: 0.5)),
                    ),
                    child: _sidePanel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readerBody(ChapterText ch, SettingsStore s) {
    return SelectionArea(
      onSelectionChanged: (c) => _selectedText = c?.plainText ?? '',
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
            ...state.contextMenuButtonItems,
          ],
        );
      },
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.symmetric(horizontal: s.pageMargin, vertical: 20),
          itemCount: ch.paragraphs.length,
          itemBuilder: (_, i) => _paragraph(ch, i, s),
        ),
      ),
    );
  }

  Widget _paragraph(ChapterText ch, int i, SettingsStore s) {
    final hl = _highlightAt(i);
    final hasExplain = _explanationsAt(i).isNotEmpty;
    final translated = _translation.of(_chapterIndex, i);

    final baseStyle = TextStyle(fontSize: s.fontSize, height: s.lineHeight);
    final dimStyle = TextStyle(
        fontSize: s.fontSize - 1,
        height: s.lineHeight,
        color: Theme.of(context).colorScheme.outline);

    Widget body;
    switch (_mode) {
      case DisplayMode.original:
        body = Text(ch.paragraphs[i], style: baseStyle);
      case DisplayMode.translated:
        body = Text(translated ?? ch.paragraphs[i],
            style: translated != null ? baseStyle : dimStyle);
      case DisplayMode.bilingual:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ch.paragraphs[i], style: baseStyle),
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
        child: hasExplain
            ? Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  body,
                  GestureDetector(
                    onTap: () => _openSaved(i),
                    child: Container(
                      margin: const EdgeInsets.only(left: 6, bottom: 2),
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Text('✦',
                          style: TextStyle(fontSize: 10, color: Colors.white)),
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
                Row(children: [
                  const SizedBox(width: 72, child: Text('主题')),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('跟随系统')),
                      ButtonSegment(value: 1, label: Text('日间')),
                      ButtonSegment(value: 2, label: Text('夜间')),
                      ButtonSegment(value: 3, label: Text('纸质')),
                    ],
                    selected: {s.readerTheme},
                    onSelectionChanged: (sel) {
                      s.readerTheme = sel.first;
                      setSheet(() {});
                      setState(() {});
                    },
                  ),
                ]),
              ],
            ),
          ),
        );
      }),
    );
  }
}
