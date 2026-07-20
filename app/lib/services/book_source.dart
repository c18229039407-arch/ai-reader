import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 数据源适配器接口（docs/architecture.md §2.2）。
/// 红线：仓库内只实现合法公版/授权源（见 CONTRIBUTING.md）。
abstract class BookSource {
  String get id;
  String get displayName;

  /// 该源内容的许可性质说明，UI 必须展示（合规要求）。
  String get licenseNote;

  Future<List<BookSearchResult>> search(String query, {String? lang});

  Future<Uint8List> download(BookSearchResult item);
}

class BookSearchResult {
  BookSearchResult({
    required this.sourceId,
    required this.title,
    required this.author,
    required this.lang,
    required this.downloadUrl,
    this.format = 'epub',
  });

  final String sourceId;
  final String title;
  final String author;
  final String lang;
  final String downloadUrl;
  final String format;
}

/// Project Gutenberg（经 Gutendex API）——公版书，合法免费（A2/A3）。
/// 也可指向任何 Gutendex 兼容服务，作为用户自定义源（A5）。
class GutendexSource implements BookSource {
  GutendexSource({
    http.Client? client,
    this.baseUrl = 'https://gutendex.com',
    String? id,
    String? displayName,
    String? licenseNote,
  })  : _http = client ?? http.Client(),
        _id = id ?? 'gutendex',
        _displayName = displayName ?? 'Project Gutenberg（公版书）',
        _licenseNote = licenseNote ?? '美国公有领域作品，可自由下载与阅读';

  final http.Client _http;
  final String baseUrl;
  final String _id;
  final String _displayName;
  final String _licenseNote;

  @override
  String get id => _id;

  @override
  String get displayName => _displayName;

  @override
  String get licenseNote => _licenseNote;

  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async {
    final uri =
        Uri.parse('$baseUrl/books/?search=${Uri.encodeQueryComponent(query)}'
            '${lang != null ? '&languages=$lang' : ''}');
    final res = await _http.get(uri).timeout(const Duration(seconds: 25));
    if (res.statusCode != 200) {
      throw Exception('Gutendex HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final results = <BookSearchResult>[];
    for (final raw in (data['results'] as List? ?? [])) {
      final b = raw as Map<String, dynamic>;
      final formats = (b['formats'] as Map?) ?? {};
      // 优先无图 epub，其次任意 epub
      final epub = (formats['application/epub+zip'] ??
          formats.entries
              .where((e) => e.key.toString().contains('epub'))
              .map((e) => e.value)
              .cast<String?>()
              .firstWhere((_) => true, orElse: () => null)) as String?;
      if (epub == null) continue;
      final authors = (b['authors'] as List? ?? [])
          .map((a) => (a as Map)['name'].toString())
          .join(', ');
      results.add(BookSearchResult(
        sourceId: id,
        title: b['title']?.toString() ?? '未知书名',
        author: authors.isEmpty ? '未知作者' : authors,
        lang: (b['languages'] as List? ?? []).join(','),
        downloadUrl: epub,
      ));
    }
    return results;
  }

  @override
  Future<Uint8List> download(BookSearchResult item) async {
    final res = await _http
        .get(Uri.parse(item.downloadUrl))
        .timeout(const Duration(minutes: 2));
    if (res.statusCode != 200) {
      throw Exception('下载失败 HTTP ${res.statusCode}');
    }
    return res.bodyBytes;
  }
}

/// 中文维基文库（Wikisource zh）——公有领域/自由许可作品。
/// 重要价值：中国版权法下作者逝世满 50 年即入公有领域，
/// 因此鲁迅、朱自清、老舍等近现代作品在此可合法获取（Gutenberg 只到 1929）。
/// 下载走 Wikisource 官方 WSExport 服务，现场生成 EPUB（自动合并子页/章节）。
class WikisourceZhSource implements BookSource {
  WikisourceZhSource({
    http.Client? client,
    this.apiBase = 'https://zh.wikisource.org/w/api.php',
    this.exportBase = 'https://ws-export.wmcloud.org',
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final String apiBase;
  final String exportBase;

  @override
  String get id => 'wikisource-zh';

  @override
  String get displayName => '中文维基文库';

  @override
  String get licenseNote => '公有领域或自由许可作品，含已过版权期的近现代中文著作';

  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async {
    // intitle: 限定标题命中——否则 MediaWiki 全文检索会把正文里
    // 碰巧含相同字词的公文、判决书等都当结果返回（相关性灾难）。
    // 注意：不能给短语加引号，引号会禁用简→繁自动转换（实测）。
    final cleaned = query.replaceAll('"', ' ').trim();
    final uri = Uri.parse(
        '$apiBase?action=query&list=search&format=json&srlimit=20&srnamespace=0'
        '&srsearch=${Uri.encodeQueryComponent('intitle:$cleaned')}');
    final res = await _http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Wikisource HTTP ${res.statusCode}');
    }
    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final hits =
        ((data['query'] as Map?)?['search'] as List? ?? []).cast<Map>();

    // 章节以子页存在（如「駱駝祥子/2」）——归并到主标题并去重
    final seen = <String>{};
    final results = <BookSearchResult>[];
    for (final h in hits) {
      final full = h['title']?.toString() ?? '';
      if (full.isEmpty) continue;
      final base = full.split('/').first;
      if (!seen.add(base)) continue;
      results.add(BookSearchResult(
        sourceId: id,
        title: base,
        author: '维基文库（作者见书内）',
        lang: 'zh',
        downloadUrl:
            '$exportBase/?format=epub&lang=zh&page=${Uri.encodeQueryComponent(base)}',
      ));
    }
    return results;
  }

  @override
  Future<Uint8List> download(BookSearchResult item) async {
    // WSExport 现场生成 EPUB，可能较慢
    final res = await _http
        .get(Uri.parse(item.downloadUrl))
        .timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      throw Exception('下载失败 HTTP ${res.statusCode}');
    }
    // EPUB 是 zip：校验魔数，避免把报错页当书存下
    if (res.bodyBytes.length < 4 ||
        res.bodyBytes[0] != 0x50 ||
        res.bodyBytes[1] != 0x4B) {
      throw Exception('导出服务返回的不是有效 EPUB，请稍后重试');
    }
    return res.bodyBytes;
  }
}

/// 随包默认数据源注册表——仅合法源（可插拔机制的 MVP 形态）。
final List<BookSource> defaultSources = [GutendexSource(), WikisourceZhSource()];
