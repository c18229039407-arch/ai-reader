import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/library_store.dart';
import '../../services/settings_store.dart';
import '../../services/ai_autodetect.dart';
import '../reader/pdf_reader_screen.dart';
import '../reader/reader_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// 书架封面色板（按书名散列取用，森林/自然系）。
const _coverPalettes = [
  [0xFF2E6B4F, 0xFF5D9B7C], // 松绿
  [0xFF7A5C3E, 0xFFB08D5F], // 枯木棕
  [0xFF3E5C76, 0xFF748CAB], // 山雾蓝
  [0xFF6B4A2E, 0xFF9B7C5D], // 陶土
  [0xFF4A2E6B, 0xFF7C5D9B], // 暮紫
  [0xFF2E5C6B, 0xFF5D8C9B], // 湖青
  [0xFF6B2E3E, 0xFF9B5D6C], // 果酱红
];

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
  Map<String, DateTime> _lastRead = {};
  bool _importing = false;

  // B4：搜索与排序；B3：标签过滤
  String _filter = '';
  String _sort = 'added'; // added | title | progress | recent
  String? _tagFilter;

  @override
  void initState() {
    super.initState();
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _maybeShowPrivacy();
      await _autoSetupAi();
      // 老书补封面（后台，一次性；新导入的书在导入时已提取）
      final added = await widget.store.backfillCovers();
      if (added > 0 && mounted) setState(() {});
    });
  }

  /// 零配置 AI：首次启动自动扫描本机模型服务（Ollama → LM Studio），
  /// 找到即自动接入；都没有才引导填云端 API Key。
  Future<void> _autoSetupAi() async {
    final s = widget.settings;
    if (s.aiSetupDone || !s.aiEnabled) return;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return; // 测试环境跳过

    final detected = await autoDetectLocalAi(s);
    if (detected != null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('✓ $detected，AI 开箱即用')));
      }
      return;
    }

    // 3) 没有本地模型 → 引导云端 Key
    if (!mounted) return;
    final keyController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置 AI（一次即可）'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '没有检测到本机模型服务（Ollama / LM Studio）。\n\n'
              '可以填一个云端 API Key 直接使用（推荐 DeepSeek，'
              '注册于 platform.deepseek.com，一次解释约几厘钱）；'
              '也可以稍后在设置中配置。',
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'DeepSeek API Key（sk-…）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.settings.aiSetupDone = true;
              Navigator.pop(ctx);
            },
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () {
              final key = keyController.text.trim();
              if (key.isNotEmpty) {
                widget.settings
                  ..providerType = 'openai'
                  ..openaiBaseUrl = 'https://api.deepseek.com'
                  ..openaiModel = 'deepseek-chat'
                  ..openaiApiKey = key;
              }
              widget.settings.aiSetupDone = true;
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final books = await widget.store.listBooks();
    final prog = <String, double>{};
    final last = <String, DateTime>{};
    for (final b in books) {
      final st = await widget.store.loadState(b.id);
      prog[b.id] = st.reading.percent;
      last[b.id] = st.reading.updatedAt;
    }
    if (mounted) {
      setState(() {
        _books = books;
        _progress = prog;
        _lastRead = last;
      });
    }
  }

  List<Book> get _visibleBooks {
    var list = _books.where((b) {
      final q = _filter.trim().toLowerCase();
      final okText = q.isEmpty ||
          b.title.toLowerCase().contains(q) ||
          b.author.toLowerCase().contains(q);
      final okTag = _tagFilter == null || b.tags.contains(_tagFilter);
      return okText && okTag;
    }).toList();
    switch (_sort) {
      case 'title':
        list.sort((a, b) => a.title.compareTo(b.title));
      case 'progress':
        list.sort(
            (a, b) => (_progress[b.id] ?? 0).compareTo(_progress[a.id] ?? 0));
      case 'recent':
        list.sort((a, b) => (_lastRead[b.id] ?? DateTime(2000))
            .compareTo(_lastRead[a.id] ?? DateTime(2000)));
        list = list.reversed.toList();
      default: // added
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    }
    return list;
  }

  Set<String> get _allTags => _books.expand((b) => b.tags).toSet();

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

  String _importLabel = '导入书籍';

  Future<void> _import() async {
    // withData: false + 按路径读取 —— 避免大文件经平台通道整体拷贝导致的卡顿
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt', 'pdf'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _importing = true);
    var ok = 0, fail = 0;
    String? lastError;
    final total = result.files.length;
    for (var i = 0; i < total; i++) {
      final f = result.files[i];
      setState(() => _importLabel = '导入中 ${i + 1}/$total…');
      try {
        Uint8List? bytes = f.bytes;
        if (bytes == null && f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        }
        if (bytes == null) throw Exception('无法读取文件');
        await widget.store.importBytes(bytes, f.name);
        ok++;
      } catch (e) {
        fail++;
        lastError = '$e';
      }
    }
    setState(() {
      _importing = false;
      _importLabel = '导入书籍';
    });
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('导入完成：成功 $ok 本'
              '${fail > 0 ? '，失败 $fail 本（$lastError）' : ''}')));
    }
  }

  Future<void> _open(Book book) async {
    if (book.format == 'pdf') {
      final st = await widget.store.loadState(book.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PdfReaderScreen(
          book: book,
          filePath: widget.store.absolutePath(book),
          initialPage: st.reading.chapterIndex + 1, // PDF 用 chapterIndex 存页码
          onPageChanged: (page, total) async {
            st.reading = ReadingState(
              chapterIndex: page - 1,
              scrollOffset: 0,
              percent: total > 0 ? page / total : 0,
              updatedAt: DateTime.now(),
            );
            await widget.store.saveState(book.id, st);
          },
        ),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReaderScreen(
            book: book, store: widget.store, settings: widget.settings),
      ));
    }
    _refresh(); // 返回时刷新进度
  }

  Future<void> _editTags(Book book) async {
    final controller = TextEditingController(text: book.tags.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑标签 ·《${book.title}》'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '用逗号分隔，如：经济学, 在读',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    final tags = result
        .split(RegExp(r'[,，]'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    await widget.store.updateBook(book.copyWith(tags: tags));
    _refresh();
  }

  Future<void> _showBookContextMenu(Book book, Offset pos) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(
            value: 'open',
            child: Row(children: [
              const Icon(Icons.menu_book_outlined, size: 18),
              const SizedBox(width: 10),
              Text('打开《${book.title}》',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
        const PopupMenuItem(
            value: 'tags',
            child: Row(children: [
              Icon(Icons.label_outline, size: 18),
              SizedBox(width: 10),
              Text('编辑标签'),
            ])),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'remove',
            child: Row(children: [
              Icon(Icons.delete_outline, size: 18),
              SizedBox(width: 10),
              Text('移除书籍'),
            ])),
      ],
    );
    switch (action) {
      case 'open':
        _open(book);
      case 'tags':
        _editTags(book);
      case 'remove':
        _confirmRemove(book);
    }
  }

  void _bookMenu(Book book) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('编辑标签'),
              onTap: () {
                Navigator.pop(ctx);
                _editTags(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('移除书籍'),
              onTap: () {
                Navigator.pop(ctx);
                _confirmRemove(book);
              },
            ),
          ],
        ),
      ),
    );
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
    final serif = ['Songti SC', 'STSong', 'Noto Serif SC', 'serif'];
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.add),
        label: Text(_importing ? _importLabel : '导入书籍'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('书架',
                          style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              fontFamilyFallback: serif)),
                      const SizedBox(width: 12),
                      if (_books.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('${_books.length} 本',
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Theme.of(context).colorScheme.outline)),
                        ),
                      const Spacer(),
                      if (_books.isNotEmpty) ...[
                        SizedBox(
                          width: 240,
                          height: 40,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: '搜索书名 / 作者',
                              hintStyle: const TextStyle(fontSize: 13),
                              prefixIcon: const Icon(Icons.search, size: 18),
                              isDense: true,
                              filled: true,
                              fillColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: .5),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (v) => setState(() => _filter = v),
                          ),
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          tooltip: '排序',
                          icon: const Icon(Icons.sort, size: 20),
                          initialValue: _sort,
                          onSelected: (v) => setState(() => _sort = v),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'added', child: Text('最近添加')),
                            PopupMenuItem(value: 'recent', child: Text('最近阅读')),
                            PopupMenuItem(value: 'title', child: Text('书名')),
                            PopupMenuItem(value: 'progress', child: Text('进度')),
                          ],
                        ),
                      ],
                      IconButton(
                        tooltip: '公版书搜索',
                        icon:
                            const Icon(Icons.travel_explore_outlined, size: 20),
                        onPressed: () async {
                          await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => SearchScreen(
                                  store: widget.store,
                                  settings: widget.settings)));
                          _refresh();
                        },
                      ),
                      IconButton(
                        tooltip: '设置',
                        icon: const Icon(Icons.settings_outlined, size: 20),
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SettingsScreen(
                                    settings: widget.settings,
                                    store: widget.store))),
                      ),
                    ],
                  ),
                  if (_allTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            FilterChip(
                              label: const Text('全部'),
                              visualDensity: VisualDensity.compact,
                              selected: _tagFilter == null,
                              onSelected: (_) =>
                                  setState(() => _tagFilter = null),
                            ),
                            ..._allTags.map((t) => Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: FilterChip(
                                    label: Text(t),
                                    visualDensity: VisualDensity.compact,
                                    selected: _tagFilter == t,
                                    onSelected: (_) => setState(() =>
                                        _tagFilter =
                                            _tagFilter == t ? null : t),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Expanded(
                      child: _books.isEmpty ? _empty(context) : _grid(context)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forest_outlined,
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
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          childAspectRatio: 0.62,
          crossAxisSpacing: 22,
          mainAxisSpacing: 26,
        ),
        itemCount: _visibleBooks.length,
        itemBuilder: (_, i) {
          final b = _visibleBooks[i];
          final pct = _progress[b.id] ?? 0;
          final palette =
              _coverPalettes[b.title.hashCode.abs() % _coverPalettes.length];
          final cover = widget.store.coverFile(b.id);
          final hasCover = cover.existsSync();
          return _Hoverable(
              child: GestureDetector(
                  onSecondaryTapUp: (d) =>
                      _showBookContextMenu(b, d.globalPosition),
                  onDoubleTap: () => _bookMenu(b),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open(b),
                    onLongPress: () => _bookMenu(b),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: hasCover
                                  ? null
                                  : LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(palette[0]),
                                        Color(palette[1])
                                      ],
                                    ),
                              boxShadow: [
                                BoxShadow(
                                  color: hasCover
                                      ? Colors.black.withValues(alpha: .22)
                                      : Color(palette[0])
                                          .withValues(alpha: .35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: hasCover
                                // 真实封面：EPUB 内嵌图（导入时提取）
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      cover,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      errorBuilder: (_, __, ___) => Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(palette[0]),
                                              Color(palette[1])
                                            ],
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.all(12),
                                        child: Text(b.title,
                                            maxLines: 4,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  )
                                : Stack(
                              children: [
                                // 书脊装饰线
                                Positioned(
                                  left: 10,
                                  top: 0,
                                  bottom: 0,
                                  child: Container(
                                    width: 1.5,
                                    color: Colors.white.withValues(alpha: .28),
                                  ),
                                ),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(22, 16, 14, 14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        b.title,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          height: 1.4,
                                          color: Colors.white,
                                          fontFamilyFallback: [
                                            'Songti SC',
                                            'STSong',
                                            'Noto Serif SC',
                                            'serif',
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(b.author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white
                                                  .withValues(alpha: .85))),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: .18),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(b.format.toUpperCase(),
                                            style: TextStyle(
                                                fontSize: 9,
                                                letterSpacing: 1,
                                                color: Colors.white
                                                    .withValues(alpha: .9))),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: LinearProgressIndicator(
                                  value: pct,
                                  minHeight: 3,
                                  borderRadius: BorderRadius.circular(2)),
                            ),
                            const SizedBox(width: 6),
                            Text('${(pct * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Theme.of(context).colorScheme.outline)),
                          ],
                        ),
                      ],
                    ),
                  )));
        },
      );
    });
  }
}

/// 桌面端悬停缩放（L2 动效）。
class _Hoverable extends StatefulWidget {
  const _Hoverable({required this.child});

  final Widget child;

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.045 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
