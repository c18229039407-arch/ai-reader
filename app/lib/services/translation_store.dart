import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 一本书的译文库（G2/G3）：段落定位符 "c:p" → 译文。
/// 存储于 <root>/translations/<bookId>.json，可断点续跑。
class BookTranslation {
  BookTranslation({
    required this.paras,
    required this.model,
    this.completed = false,
  });

  final Map<String, String> paras;
  String model;
  bool completed;

  Map<String, dynamic> toJson() =>
      {'paras': paras, 'model': model, 'completed': completed};

  factory BookTranslation.fromJson(Map<String, dynamic> j) => BookTranslation(
        paras: ((j['paras'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        model: j['model'] as String? ?? '',
        completed: j['completed'] as bool? ?? false,
      );

  static BookTranslation empty() =>
      BookTranslation(paras: {}, model: '', completed: false);

  String? of(int chapter, int paragraph) => paras['$chapter:$paragraph'];
}

class TranslationStore {
  TranslationStore(this.rootDir);

  final Directory rootDir;

  Directory get _dir => Directory(p.join(rootDir.path, 'translations'));
  File _file(String bookId) => File(p.join(_dir.path, '$bookId.json'));

  Future<BookTranslation> load(String bookId) async {
    final f = _file(bookId);
    if (!await f.exists()) return BookTranslation.empty();
    try {
      return BookTranslation.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return BookTranslation.empty();
    }
  }

  Future<void> save(String bookId, BookTranslation t) async {
    await _dir.create(recursive: true);
    await _file(bookId).writeAsString(jsonEncode(t.toJson()));
  }
}
