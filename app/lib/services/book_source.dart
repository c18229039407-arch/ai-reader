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
class GutendexSource implements BookSource {
  GutendexSource({http.Client? client, this.baseUrl = 'https://gutendex.com'})
      : _http = client ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  @override
  String get id => 'gutendex';

  @override
  String get displayName => 'Project Gutenberg（公版书）';

  @override
  String get licenseNote => '美国公有领域作品，可自由下载与阅读';

  @override
  Future<List<BookSearchResult>> search(String query, {String? lang}) async {
    final uri =
        Uri.parse('$baseUrl/books/?search=${Uri.encodeQueryComponent(query)}'
            '${lang != null ? '&languages=$lang' : ''}');
    final res = await _http.get(uri).timeout(const Duration(seconds: 15));
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

/// 随包默认数据源注册表——仅合法源（可插拔机制的 MVP 形态）。
final List<BookSource> defaultSources = [GutendexSource()];
