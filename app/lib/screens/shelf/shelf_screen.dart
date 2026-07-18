import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import '../reader/reader_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// 书架（B1/B2）+ 导入（A1）+ 首次隐私说明（F3）。
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key, required this.settings, required this.store});

  final SettingsStore settings;
  final LibraryStore store;

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  List<Book> _books = [];
  Map<String, double> _progress = {};
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPrivacy());
  }

  Future<void> _refresh() async {
    final books = await widget.store.listBooks();
    final prog = <String, double>{};
    for (final b in books) {
      prog[b.id] = (await widget.store.loadState(b.id)).reading.percent;
    }
    if (mounted)
      setState(() {
        _books = books;
        _progress = prog;
      });
  }

  Future<void> _maybeShowPrivacy() async {
    if (widget.settings.privacyAcknowledged || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('数据说明'),
        content: const SingleChildScrollView(
          child: Text(
            '• 你的书籍文件、阅读进度、高亮和 AI 解释记录，全部只存在本机。\n\n'
            '• 没有账号、没有云端、没有任何行为上报。\n\n'
            '• 只有当你主动点「AI 解释 / 翻译」时，所选文字及其前后几段会发送给你配置的 AI 服务'
            '（默认是本机 Ollama，数据不出设备）。\n\n'
            '• 可在设置中随时彻底关闭 AI 功能。',
            style: TextStyle(height: 1.6),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              widget.settings.privacyAcknowledged = true;
              Navigator.of(ctx).pop();
            },
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    setState(() => _importing = true);
    var ok = 0, fail = 0;
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) {
        fail++;
        continue;
      }
      try {
        await widget.store.importBytes(bytes, f.name);
        ok++;
      } catch (_) {
        fail++;
      }
    }
    setState(() => _importing = false);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('导入完成：成功 $ok 本${fail > 0 ? '，失败 $fail 本' : ''}')));
    }
  }

  Future<void> _open(Book book) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(
          book: book, store: widget.store, settings: widget.settings),
    ));
    _refresh(); // 返回时刷新进度
  }

  Future<void> _confirmRemove(Book book) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('移除《${book.title}》？'),
        content: const Text('将删除本机的书籍文件及其阅读记录（进度/高亮/解释）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (yes == true) {
      await widget.store.removeBook(book.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        actions: [
          IconButton(
            tooltip: '公版书搜索',
            icon: const Icon(Icons.travel_explore_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => SearchScreen(store: widget.store)));
              _refresh();
            },
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(settings: widget.settings))),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(_importing ? '导入中…' : '导入书籍'),
      ),
      body: _books.isEmpty ? _empty(context) : _grid(context),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 72, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('书架还是空的'),
            const SizedBox(height: 8),
            Text('点右下角「导入书籍」，支持 EPUB / TXT',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.outline,
                    fontSize: 13)),
          ],
        ),
      );

  Widget _grid(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cross = (constraints.maxWidth / 180).floor().clamp(2, 8);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          childAspectRatio: 0.68,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _books.length,
        itemBuilder: (_, i) {
          final b = _books[i];
          final pct = _progress[b.id] ?? 0;
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _open(b),
            onLongPress: () => _confirmRemove(b),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.secondaryContainer,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.title,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const Spacer(),
                        Text(b.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    .withValues(alpha: .7))),
                        Text(b.format.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    .withValues(alpha: .5))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                    value: pct,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2)),
                const SizedBox(height: 2),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline)),
              ],
            ),
          );
        },
      );
    });
  }
}
