import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/book_source.dart';
import '../../services/library_store.dart';
import '../../services/proxy_http.dart';
import '../../services/settings_store.dart';

/// 公版书搜索页（A2/A3）。
/// 网络策略：直连失败时自动探测本机常见代理端口（Clash 7890 等）——
/// 浏览器能访问境外站点时，App 也能拿到同样的通路（Dart 不读系统代理，需自行处理）。
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.store,
    this.settings,
    this.sources, // 测试注入用；为空则按 settings 构建
  });

  final LibraryStore store;
  final SettingsStore? settings;
  final List<BookSource>? sources;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<BookSearchResult> _results = [];
  List<BookSource> _activeSources = [];
  String? _usedProxy;
  bool _searching = false;
  String? _error;
  final Set<String> _downloading = {};

  List<BookSource> _buildSources(http.Client? client) {
    final s = widget.settings;
    return [
      GutendexSource(client: client),
      if (s != null)
        ...s.customSourceUrls.asMap().entries.map(
              (e) => GutendexSource(
                client: client,
                baseUrl: e.value.trim(),
                id: 'custom-${e.key}',
                displayName: Uri.tryParse(e.value)?.host ?? e.value,
                licenseNote: '用户自定义源，内容合规责任由配置者自负',
              ),
            ),
    ];
  }

  Future<List<BookSearchResult>> _searchAll(
      List<BookSource> sources, String q) async {
    final all = <BookSearchResult>[];
    Object? firstError;
    var anyOk = false;
    for (final s in sources) {
      try {
        all.addAll(await s.search(q));
        anyOk = true;
      } catch (e) {
        firstError ??= e;
      }
    }
    if (!anyOk && firstError != null) throw firstError;
    return all;
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
      _usedProxy = null;
    });

    // 测试注入路径：只用注入源直连
    if (widget.sources != null) {
      try {
        final all = await _searchAll(widget.sources!, q);
        setState(() {
          _results = all;
          _activeSources = widget.sources!;
        });
      } catch (e) {
        setState(() => _error = '$e');
      } finally {
        setState(() => _searching = false);
      }
      return;
    }

    // 直连 → 自动代理探测
    final cfg = widget.settings?.proxyAddress ?? 'auto';
    final attempts = <String?>[null];
    if (cfg == 'auto') {
      attempts.addAll(commonLocalProxies);
    } else if (cfg.isNotEmpty) {
      attempts.add(cfg);
    }

    Object? lastError;
    for (final proxy in attempts) {
      final client = proxy == null ? null : clientViaProxy(proxy);
      final sources = _buildSources(client);
      try {
        final all = await _searchAll(sources, q);
        setState(() {
          _results = all;
          _activeSources = sources;
          _usedProxy = proxy;
          _searching = false;
        });
        return;
      } catch (e) {
        lastError = e;
      }
    }

    setState(() {
      _searching = false;
      _error =
          '直连与本机常见代理端口（${commonLocalProxies.map((p) => p.split(':').last).join('/')}）都试过了，仍无法连上公版书源。\n\n'
          '若你的代理端口不是常见端口，请到「设置 → 书源代理」填写 host:port；'
          '或先用「导入书籍」读自己的文件。\n\n技术信息：$lastError';
    });
  }

  Future<void> _download(BookSearchResult item) async {
    final source = _activeSources.firstWhere((s) => s.id == item.sourceId);
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
    final infoSources = widget.sources ?? _buildSources(null);
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
                      hintText: '书名或作者（如：吶喊 / Adam Smith）',
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
                    '数据源：${infoSources.map((s) => '${s.displayName}（${s.licenseNote}）').join('；')}'
                    '${_usedProxy != null ? ' · 已通过本机代理 $_usedProxy 连接' : ''}',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text('搜索失败\n\n$_error',
                    style: TextStyle(
                        height: 1.6,
                        color: Theme.of(context).colorScheme.error)),
              ),
            )
          else
            Expanded(
              child: _results.isEmpty && !_searching
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
