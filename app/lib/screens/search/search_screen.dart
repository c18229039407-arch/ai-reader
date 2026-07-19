import 'package:flutter/material.dart';

import '../../services/book_source.dart';
import '../../services/library_store.dart';

/// 公版书搜索页（A2/A3）：搜索合法源 → 一键下载入库。
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.store, this.sources});

  final LibraryStore store;
  final List<BookSource>? sources;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final List<BookSource> _sources = widget.sources ?? defaultSources;
  final _query = TextEditingController();
  List<BookSearchResult> _results = [];
  bool _searching = false;
  String? _error;
  final Set<String> _downloading = {};

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final all = <BookSearchResult>[];
      for (final s in _sources) {
        all.addAll(await s.search(q));
      }
      setState(() => _results = all);
    } catch (e) {
      setState(() => _error = '连接公版书源失败。\n\n'
          '内置源（Project Gutenberg）的服务器在境外，部分网络环境无法直接访问。'
          '你可以：\n'
          '① 换个网络环境重试；\n'
          '② 在「设置 → 自定义公版书源」添加可访问的镜像源；\n'
          '③ 直接用书架的「导入书籍」读自己的文件——阅读和 AI 功能完全不受影响。\n\n'
          '技术信息：$e');
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _download(BookSearchResult item) async {
    final source = _sources.firstWhere((s) => s.id == item.sourceId);
    setState(() => _downloading.add(item.downloadUrl));
    try {
      final bytes = await source.download(item);
      final book =
          await widget.store.importBytes(bytes, '${item.title}.${item.format}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('《${book.title}》已加入书架')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('下载失败：$e')));
    } finally {
      if (mounted) setState(() => _downloading.remove(item.downloadUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('公版书搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      hintText: '书名或作者（如：呐喊 / Adam Smith）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _searching ? null : _search,
                    child: Text(_searching ? '搜索中…' : '搜索')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Icon(Icons.verified_outlined,
                    size: 14, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '数据源：${_sources.map((s) => '${s.displayName}（${s.licenseNote}）').join('；')}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('搜索出错：$_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Expanded(
            child: _results.isEmpty && !_searching && _error == null
                ? Center(
                    child: Text('输入书名开始搜索公版书',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.outline)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      final busy = _downloading.contains(r.downloadUrl);
                      return ListTile(
                        title: Text(r.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${r.author} · ${r.lang} · EPUB'),
                        trailing: busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : FilledButton.tonal(
                                onPressed: () => _download(r),
                                child: const Text('入书架')),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
