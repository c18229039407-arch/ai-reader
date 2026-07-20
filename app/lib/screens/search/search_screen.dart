import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:url_launcher/url_launcher.dart';

import '../../services/book_source.dart';
import '../../services/find_online.dart';
import '../../services/library_store.dart';
import '../../services/proxy_http.dart';
import '../../services/s2t_map.dart';
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
  bool _searched = false; // 已完成过一次搜索（区分「未搜索」与「无结果」）
  String? _convertedQuery; // 非空 = 本次结果来自自动繁体转换
  String _lastQuery = '';
  List<String> _failedNames = []; // 本轮连不上的书源（结果可能不完整）
  String? _error;
  final Set<String> _downloading = {};

  List<BookSource> _buildSources(http.Client? client) {
    final s = widget.settings;
    return [
      GutendexSource(client: client),
      WikisourceZhSource(client: client),
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

  /// 搜索 + 简繁回退：Gutenberg 中文书名均为繁体，简体 0 结果时自动转繁体重试。
  /// 返回 (结果, 实际生效的繁体查询或 null)。
  Future<(List<BookSearchResult>, String?)> _searchWithFallback(
      List<BookSource> sources, String q) async {
    final all = await _searchAll(sources, q);
    if (all.isNotEmpty) return (all, null);
    final trad = toTraditional(q);
    if (trad == q) return (all, null);
    final retried = await _searchAll(sources, trad);
    return (retried, retried.isNotEmpty ? trad : null);
  }

  /// 单个书源的连通竞速：直连与各代理并行发起，最先成功者胜出。
  /// 全部失败返回 null（错误收集到 [errors]）。
  Future<_SourceResult?> _raceAttempts(
    BookSource Function(http.Client?) build,
    String q,
    List<String?> attempts,
    List<Object> errors,
  ) {
    final completer = Completer<_SourceResult?>();
    var pending = attempts.length;
    for (final proxy in attempts) {
      () async {
        try {
          final src = build(proxy == null ? null : clientViaProxy(proxy));
          final r = await src.search(q);
          if (!completer.isCompleted) {
            completer.complete(_SourceResult(src, r, proxy));
          }
        } catch (e) {
          errors.add(e);
        } finally {
          pending -= 1;
          if (pending == 0 && !completer.isCompleted) completer.complete(null);
        }
      }();
    }
    return completer.future;
  }

  /// 所有书源并行搜索（每源独立代理竞速——境内可达性各不相同）。
  Future<(List<_SourceResult?>, List<Object>)> _searchOnce(
      String q, List<String?> attempts) async {
    final errors = <Object>[];
    final count = _buildSources(null).length;
    final outcomes = await Future.wait(List.generate(
        count,
        (i) => _raceAttempts(
            (client) => _buildSources(client)[i], q, attempts, errors)));
    return (outcomes, errors);
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
      _usedProxy = null;
      _convertedQuery = null;
      _failedNames = [];
      _lastQuery = q;
    });

    // 测试注入路径：只用注入源直连
    if (widget.sources != null) {
      try {
        final (all, converted) = await _searchWithFallback(widget.sources!, q);
        setState(() {
          _results = all;
          _convertedQuery = converted;
          _activeSources = widget.sources!;
          _searched = true;
        });
      } catch (e) {
        setState(() => _error = '$e');
      } finally {
        setState(() => _searching = false);
      }
      return;
    }

    // 直连 → 自动代理探测（每个书源独立竞速，境内外可达性不同）
    final cfg = widget.settings?.proxyAddress ?? 'auto';
    final attempts = <String?>[null];
    if (cfg == 'auto') {
      attempts.addAll(commonLocalProxies);
    } else if (cfg.isNotEmpty) {
      attempts.add(cfg);
    }

    var (outcomes, errors) = await _searchOnce(q, attempts);
    var ok = outcomes.whereType<_SourceResult>().toList();
    var all = ok.expand((o) => o.results).toList();
    String? converted;

    // 简繁回退：有源可达但 0 结果时，转繁体再来一轮
    if (ok.isNotEmpty && all.isEmpty) {
      final trad = toTraditional(q);
      if (trad != q) {
        final (o2, _) = await _searchOnce(trad, attempts);
        final ok2 = o2.whereType<_SourceResult>().toList();
        final all2 = ok2.expand((o) => o.results).toList();
        if (all2.isNotEmpty) {
          ok = ok2;
          all = all2;
          converted = trad;
        }
      }
    }

    if (!mounted) return;
    if (ok.isEmpty) {
      setState(() {
        _searching = false;
        _error =
            '直连与本机常见代理端口（${commonLocalProxies.map((p) => p.split(':').last).join('/')}）都试过了，仍无法连上任何书源。\n\n'
            '若你的代理端口不是常见端口，请到「设置 → 书源代理」填写 host:port；'
            '或先用「导入书籍」读自己的文件。\n\n技术信息：${errors.isEmpty ? '无' : errors.last}';
      });
      return;
    }

    final okNames = ok.map((o) => o.source.displayName).toSet();
    setState(() {
      _results = all;
      _convertedQuery = converted;
      _activeSources = ok.map((o) => o.source).toList();
      _usedProxy =
          ok.map((o) => o.proxy).firstWhere((p) => p != null, orElse: () => null);
      _failedNames = _buildSources(null)
          .map((s) => s.displayName)
          .where((n) => !okNames.contains(n))
          .toList();
      _searching = false;
      _searched = true;
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
                      hintText: '书名或作者（如：呐喊 / 骆驼祥子 / Adam Smith）',
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
                    '${_usedProxy != null ? ' · 已通过本机代理 $_usedProxy 连接' : ''}'
                    '${_failedNames.isNotEmpty ? ' · ⚠ ${_failedNames.join('、')}暂时连不上，结果可能不完整' : ''}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],
            ),
          ),
          if (_convertedQuery != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.translate,
                      size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '「$_lastQuery」没有直接命中，已自动按繁体「$_convertedQuery」搜索（Gutenberg 中文书名均为繁体）',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary),
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
          else if (_searching)
            const Expanded(
                child: Center(child: CircularProgressIndicator(strokeWidth: 3)))
          else
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          !_searched
                              ? '输入书名开始搜索公版书'
                              : '没有找到「$_lastQuery」\n\n'
                                  '这里只能搜到公版书——版权已过期、可合法免费下载全文的书：\n'
                                  '· 中文：作者逝世满 50 年即公版，鲁迅、朱自清、老舍等近现代作品可搜\n'
                                  '· 英文：约 1929 年以前出版的作品，可试英文书名或作者名\n\n'
                                  '仍在版权保护期的书（近几十年出版的新书、畅销书、教材）\n'
                                  '不存在合法的免费全文来源，任何声称免费提供的站点都是盗版。\n'
                                  '可用下方入口去站外找这本书，拿到文件后\n'
                                  '用书架的「导入书籍」阅读——AI 解释、翻译等功能同样可用。',
                          textAlign:
                              !_searched ? TextAlign.center : TextAlign.left,
                          style: TextStyle(
                              height: 1.8,
                              color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                    )
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
          // A4 中立聚合搜索入口：站外找书，下载在 App 外由用户完成后再导入
          if (_searched && !_searching && _error == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('站外找「$_lastQuery」（浏览器打开，下载后可导入书架）',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final link in findOnlineLinks(_lastQuery))
                        Tooltip(
                          message: link.hint,
                          child: ActionChip(
                            avatar: const Icon(Icons.open_in_new, size: 15),
                            label: Text(link.label),
                            onPressed: () => launchUrl(link.uri,
                                mode: LaunchMode.externalApplication),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个书源一轮搜索的胜出结果：源实例（带可用连接）+ 结果 + 所用代理。
class _SourceResult {
  _SourceResult(this.source, this.results, this.proxy);

  final BookSource source;
  final List<BookSearchResult> results;
  final String? proxy;
}
