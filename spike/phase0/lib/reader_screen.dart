import 'package:flutter/material.dart';

import 'epub_loader.dart';
import 'explain_sheet.dart';
import 'ollama_client.dart';

/// 阅读界面：章节抽屉 + 正文 SelectionArea + 自定义右键/长按菜单（解释、翻译）。
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.ollamaUrl,
    required this.model,
    required this.occupation,
  });

  final LoadedBook book;
  final String ollamaUrl;
  final String model;
  final String occupation;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  int _chapterIndex = 0;
  String _selectedText = '';
  final _scrollController = ScrollController();

  ChapterText get _chapter => widget.book.chapters[_chapterIndex];

  void _openSheet(ExplainMode mode) {
    final text = _selectedText.trim();
    if (text.isEmpty) return;
    ContextMenuController.removeAny();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      builder: (_) => ExplainSheet(
        client: OllamaClient(widget.ollamaUrl),
        model: widget.model,
        mode: mode,
        selectedText: text,
        bookTitle: widget.book.title,
        chapterTitle: _chapter.title,
        occupation: widget.occupation,
      ),
    );
  }

  void _goto(int index) {
    setState(() => _chapterIndex = index);
    _scrollController.jumpTo(0);
    Navigator.of(context).maybePop(); // 关抽屉（若开着）
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.book.title} · ${_chapter.title}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '上一章',
            onPressed: _chapterIndex > 0
                ? () => _goto(_chapterIndex - 1)
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '下一章',
            onPressed: _chapterIndex < widget.book.chapters.length - 1
                ? () => _goto(_chapterIndex + 1)
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView.builder(
          itemCount: widget.book.chapters.length,
          itemBuilder: (_, i) => ListTile(
            dense: true,
            selected: i == _chapterIndex,
            title: Text(
              widget.book.chapters[i].title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _goto(i),
          ),
        ),
      ),
      body: SelectionArea(
        onSelectionChanged: (content) =>
            _selectedText = content?.plainText ?? '',
        contextMenuBuilder: (context, selectableRegionState) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: [
              ContextMenuButtonItem(
                label: 'AI 解释',
                onPressed: () => _openSheet(ExplainMode.explain),
              ),
              ContextMenuButtonItem(
                label: 'AI 翻译',
                onPressed: () => _openSheet(ExplainMode.translate),
              ),
              ...selectableRegionState.contextMenuButtonItems,
            ],
          );
        },
        child: Scrollbar(
          controller: _scrollController,
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
            itemCount: _chapter.paragraphs.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                _chapter.paragraphs[i],
                style: const TextStyle(fontSize: 17, height: 1.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
