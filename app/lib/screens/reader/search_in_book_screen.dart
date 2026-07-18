import 'package:flutter/material.dart';

import '../../services/epub_loader.dart';

class InBookMatch {
  InBookMatch(this.chapter, this.paragraph, this.preview);

  final int chapter;
  final int paragraph;
  final String preview;
}

/// 书内全文检索（C7）：纯内存遍历（MVP，整书在内存中；FTS 属 V-next）。
List<InBookMatch> searchInBook(LoadedBook book, String query,
    {int limit = 200}) {
  final q = query.trim();
  if (q.isEmpty) return [];
  final lower = q.toLowerCase();
  final out = <InBookMatch>[];
  for (var c = 0; c < book.chapters.length && out.length < limit; c++) {
    final paras = book.chapters[c].paragraphs;
    for (var i = 0; i < paras.length && out.length < limit; i++) {
      final idx = paras[i].toLowerCase().indexOf(lower);
      if (idx < 0) continue;
      final start = (idx - 20).clamp(0, paras[i].length);
      final end = (idx + q.length + 40).clamp(0, paras[i].length);
      out.add(InBookMatch(c, i,
          '${start > 0 ? '…' : ''}${paras[i].substring(start, end)}${end < paras[i].length ? '…' : ''}'));
    }
  }
  return out;
}

class SearchInBookScreen extends StatefulWidget {
  const SearchInBookScreen({
    super.key,
    required this.book,
    required this.onJump,
  });

  final LoadedBook book;
  final void Function(int chapter, int paragraph) onJump;

  @override
  State<SearchInBookScreen> createState() => _SearchInBookScreenState();
}

class _SearchInBookScreenState extends State<SearchInBookScreen> {
  final _query = TextEditingController();
  List<InBookMatch> _matches = [];
  bool _searched = false;

  void _run() {
    setState(() {
      _matches = searchInBook(widget.book, _query.text);
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: '书内搜索…', border: InputBorder.none),
          onSubmitted: (_) => _run(),
        ),
        actions: [
          IconButton(onPressed: _run, icon: const Icon(Icons.search)),
        ],
      ),
      body: !_searched
          ? const SizedBox.shrink()
          : _matches.isEmpty
              ? Center(
                  child: Text('无匹配',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.outline)))
              : ListView.builder(
                  itemCount: _matches.length,
                  itemBuilder: (_, i) {
                    final m = _matches[i];
                    return ListTile(
                      dense: true,
                      title: Text(m.preview,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${widget.book.chapters[m.chapter].title} · 段落 ${m.paragraph + 1}'),
                      onTap: () {
                        Navigator.pop(context);
                        widget.onJump(m.chapter, m.paragraph);
                      },
                    );
                  },
                ),
    );
  }
}
