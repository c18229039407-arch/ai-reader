import 'package:flutter/material.dart';

import '../../models/models.dart';

/// 标注汇总页（C6）：书签 / 笔记 / 高亮 三类，支持跳转与删除。
class AnnotationsScreen extends StatefulWidget {
  const AnnotationsScreen({
    super.key,
    required this.bookTitle,
    required this.state,
    required this.chapterTitleOf,
    required this.onJump,
    required this.onChanged,
  });

  final String bookTitle;
  final BookState state;
  final String Function(int chapterIndex) chapterTitleOf;
  final void Function(int chapterIndex, {int? paragraph, double? offset})
      onJump;

  /// 任何删除/修改后回调（外层负责持久化）。
  final VoidCallback onChanged;

  @override
  State<AnnotationsScreen> createState() => _AnnotationsScreenState();
}

class _AnnotationsScreenState extends State<AnnotationsScreen> {
  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('标注 · ${widget.bookTitle}'),
          bottom: TabBar(tabs: [
            Tab(text: '书签 (${st.bookmarks.length})'),
            Tab(text: '笔记 (${st.notes.length})'),
            Tab(text: '高亮 (${st.highlights.length})'),
          ]),
        ),
        body: TabBarView(
          children: [
            _bookmarks(context, st),
            _notes(context, st),
            _highlights(context, st),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text) => Center(
      child: Text(text,
          style: TextStyle(color: Theme.of(context).colorScheme.outline)));

  Widget _bookmarks(BuildContext context, BookState st) {
    if (st.bookmarks.isEmpty) return _empty('阅读页右上角 🔖 可添加书签');
    final list = [...st.bookmarks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final b = list[i];
        return ListTile(
          leading: const Icon(Icons.bookmark_outline),
          title: Text(b.label.isEmpty
              ? widget.chapterTitleOf(b.chapterIndex)
              : b.label),
          subtitle: Text(
              '${widget.chapterTitleOf(b.chapterIndex)} · ${b.createdAt.toLocal().toString().substring(0, 16)}'),
          onTap: () {
            Navigator.pop(context);
            widget.onJump(b.chapterIndex, offset: b.scrollOffset);
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () {
              setState(() => st.bookmarks.remove(b));
              widget.onChanged();
            },
          ),
        );
      },
    );
  }

  Widget _notes(BuildContext context, BookState st) {
    if (st.notes.isEmpty) return _empty('划选文字 → 右键/长按 →「笔记」');
    final list = [...st.notes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final n = list[i];
        return ListTile(
          leading: const Icon(Icons.sticky_note_2_outlined),
          title: Text(n.text, maxLines: 3, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${widget.chapterTitleOf(n.locator.chapter)} · 段落 ${n.locator.paragraph + 1}'),
          onTap: () {
            Navigator.pop(context);
            widget.onJump(n.locator.chapter, paragraph: n.locator.paragraph);
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () {
              setState(() => st.notes.remove(n));
              widget.onChanged();
            },
          ),
        );
      },
    );
  }

  Widget _highlights(BuildContext context, BookState st) {
    if (st.highlights.isEmpty) return _empty('划选文字 → 右键/长按 →「高亮」');
    final list = [...st.highlights]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final h = list[i];
        return ListTile(
          leading: const Icon(Icons.border_color_outlined),
          title: Text(
              '${widget.chapterTitleOf(h.locator.chapter)} · 段落 ${h.locator.paragraph + 1}'),
          subtitle: Text(h.createdAt.toLocal().toString().substring(0, 16)),
          onTap: () {
            Navigator.pop(context);
            widget.onJump(h.locator.chapter, paragraph: h.locator.paragraph);
          },
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () {
              setState(() => st.highlights.remove(h));
              widget.onChanged();
            },
          ),
        );
      },
    );
  }
}
