import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/epub_loader.dart';
import '../../services/explain_service.dart';
import '../../services/library_store.dart';
import '../../services/ollama_client.dart';
import '../../services/settings_store.dart';
import 'explain_panel.dart';

/// 高亮色板（C5）。
const highlightColors = [
  Color(0x66FFD54F), // 黄
  Color(0x6681C784), // 绿
  Color(0x6664B5F6), // 蓝
];

/// 阅读器（C1–C5/C9 + D1–D4/D8 锚点）。
/// 宽屏（≥900）解释显示为右侧常驻面板；窄屏为底部抽屉。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.store,
    required this.settings,
  });

  final Book book;
  final LibraryStore store;
  final SettingsStore settings;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  LoadedBook? _content;
  BookState _state = BookState.empty();
  Object? _loadError;

  int _chapterIndex = 0;
  final _scroll = ScrollController();
  Timer? _saveDebounce;

  String _selectedText = '';

  // 宽屏侧栏面板内容（null = 关闭）
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
      setState(() {
        _content = content;
        _state = state;
        _chapterIndex =
            state.reading.chapterIndex.clamp(0, content.chapters.length - 1);
      });
      // 恢复滚动位置（C4）
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
    _scroll.dispose();
    super.dispose();
  }

  // ---------- 定位与状态操作 ----------

  /// 用所选文本在当前章定位段落（MVP 段落级锚点）。
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

    final stream = translate
        ? svc.translate(selected)
        : svc.explain(
            bookTitle: _content!.title,
            chapter: ch,
            paragraphIndex: para ?? 0,
            selectedText: selected,
            profile: widget.settings.profile,
          );

    _showPanel(ExplainPanel(
      title: translate ? 'AI 翻译' : 'AI 解释',
      quotedText: selected,
      stream: stream,
      onDone: (full) => _persistExplanation(
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
    if (mounted) setState(() {}); // 让 ✦ 锚点出现
  }

  void _openSaved(int para) {
    final list = _explanationsAt(para);
    if (list.isEmpty) return;
    final e = list.first;
    _showPanel(ExplainPanel(
      title: e.mode == 'translate' ? 'AI 翻译' : 'AI 解释',
      quotedText: e.term,
      savedText: list.length > 1
          ? '${e.resultText}\n\n——共 ${list.length} 条留存，此为最新——'
          : e.resultText,
      onClose: _closePanel,
    ));
  }

  // ---------- 面板容器：宽屏侧栏 / 窄屏抽屉 ----------

  bool get _wide => MediaQuery.of(context).size.width >= 900;

  void _showPanel(Widget panel) {
    if (_wide) {
      setState(() => _sidePanel = panel);
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
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

  // ---------- 章节导航（C9） ----------

  void _goto(int index) {
    final content = _content;
    if (content == null) return;
    setState(() => _chapterIndex = index.clamp(0, content.chapters.length - 1));
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _saveProgress();
  }

  // ---------- 构建 ----------

  Color? _readerBackground(BuildContext context) {
    // C3：护眼纸质主题只影响阅读页背景
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

    return Scaffold(
      backgroundColor: _readerBackground(context),
      appBar: AppBar(
        title: Text('${content.title} · ${ch.title}',
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '排版设置',
            icon: const Icon(Icons.text_fields),
            onPressed: _showTypography,
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
      body: Row(
        children: [
          Expanded(child: _readerBody(ch, s)),
          if (_wide && _sidePanel != null)
            Container(
              width: 340,
              decoration: BoxDecoration(
                border: Border(
                    left: BorderSide(
                        color: Theme.of(context).dividerColor, width: 0.5)),
              ),
              child: _sidePanel,
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

    final text = Text(ch.paragraphs[i],
        style: TextStyle(fontSize: s.fontSize, height: s.lineHeight));

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
                  text,
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
            : text,
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
