import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'proxy_http.dart';

/// 联网找封面（A6 元数据补全的一部分）。
/// 数据源：Open Library 公开封面库（合法免费）。
/// 已知限制：英文书覆盖很好，中文书条目普遍缺封面图（实测）。
class CoverFetcher {
  CoverFetcher({
    http.Client? client,
    this.searchBase = 'https://openlibrary.org',
    this.coversBase = 'https://covers.openlibrary.org',
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final String searchBase;
  final String coversBase;

  Future<Uint8List?> fetch(String title, {String? author}) async {
    final hasAuthor =
        author != null && author.trim().isNotEmpty && author != '未知作者';
    final uri = Uri.parse('$searchBase/search.json'
        '?title=${Uri.encodeQueryComponent(title)}'
        '${hasAuthor ? '&author=${Uri.encodeQueryComponent(author)}' : ''}'
        '&limit=10&fields=title,cover_i');
    final res = await _http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final docs = (data['docs'] as List? ?? []).cast<Map>();
    final coverId = docs
        .map((d) => (d['cover_i'] as num?)?.toInt())
        .firstWhere((c) => c != null, orElse: () => null);
    if (coverId == null) return null;

    final img = await _http
        .get(Uri.parse('$coversBase/b/id/$coverId-L.jpg'))
        .timeout(const Duration(seconds: 60));
    final b = img.bodyBytes;
    // 校验确实是图片（JPEG/PNG 魔数），且不是占位小图
    final isJpeg = b.length > 2 && b[0] == 0xFF && b[1] == 0xD8;
    final isPng = b.length > 4 && b[0] == 0x89 && b[1] == 0x50;
    if (img.statusCode != 200 || b.length < 5 * 1024 || (!isJpeg && !isPng)) {
      return null;
    }
    return b;
  }
}

/// 直连与本机常见代理并行竞速取封面（境内直连 openlibrary 不稳定）。
Future<Uint8List?> fetchCoverAuto(String title,
    {String? author, String proxyCfg = 'auto'}) {
  final attempts = <String?>[null];
  if (proxyCfg == 'auto') {
    attempts.addAll(commonLocalProxies);
  } else if (proxyCfg.isNotEmpty) {
    attempts.add(proxyCfg);
  }

  final completer = Completer<Uint8List?>();
  var pending = attempts.length;
  for (final proxy in attempts) {
    () async {
      try {
        final fetcher = CoverFetcher(
            client: proxy == null ? null : clientViaProxy(proxy));
        final bytes = await fetcher.fetch(title, author: author);
        if (bytes != null && !completer.isCompleted) completer.complete(bytes);
      } catch (_) {
        // 单路失败不影响其他通路
      } finally {
        pending -= 1;
        if (pending == 0 && !completer.isCompleted) completer.complete(null);
      }
    }();
  }
  return completer.future;
}
