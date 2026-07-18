import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';
import 'epub_loader.dart';
import 'txt_loader.dart';

/// 本地书库存储（B2）。目录布局与 docs/architecture.md §4 的
/// 「Syncthing 友好」约定一致，MVP 直接落 JSON：
///
///   <root>/
///     books/<id>.<ext>     书籍原文件
///     library.json         书目元数据
///     state/<id>.json      每本书的进度/高亮/解释
///
/// root 由调用方注入（App 用 path_provider 取，测试用临时目录）。
class LibraryStore {
  LibraryStore(this.rootDir);

  final Directory rootDir;

  Directory get _booksDir => Directory(p.join(rootDir.path, 'books'));
  Directory get _stateDir => Directory(p.join(rootDir.path, 'state'));
  File get _libraryFile => File(p.join(rootDir.path, 'library.json'));

  Future<void> init() async {
    await _booksDir.create(recursive: true);
    await _stateDir.create(recursive: true);
  }

  // ---------- 书目 ----------

  Future<List<Book>> listBooks() async {
    if (!await _libraryFile.exists()) return [];
    final raw = jsonDecode(await _libraryFile.readAsString());
    return ((raw as Map<String, dynamic>)['books'] as List? ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  Future<void> _saveBooks(List<Book> books) async {
    await _libraryFile.writeAsString(const JsonEncoder.withIndent('  ')
        .convert({'books': books.map((b) => b.toJson()).toList()}));
  }

  /// 导入一本书（A1）。返回新增或已存在的 Book。
  Future<Book> importBytes(Uint8List bytes, String originalName) async {
    await init();
    final id = sha1.convert(bytes).toString().substring(0, 16);
    final books = await listBooks();
    final existing = books.where((b) => b.id == id).firstOrNull;
    if (existing != null) return existing;

    final ext = p.extension(originalName).toLowerCase().replaceFirst('.', '');
    final format = ext == 'txt' ? 'txt' : 'epub';
    final rel = p.join('books', '$id.$format');
    await File(p.join(rootDir.path, rel)).writeAsBytes(bytes);

    String title = p.basenameWithoutExtension(originalName);
    String author = '未知作者';
    String lang = '';
    if (format == 'epub') {
      try {
        final parsed = await loadEpub(bytes);
        if (parsed.title.trim().isNotEmpty && parsed.title != '未知书名') {
          title = parsed.title;
        }
        author = parsed.author;
        lang = parsed.chapters
                .expand((c) => c.paragraphs)
                .take(5)
                .join()
                .contains(RegExp(r'[一-鿿]'))
            ? 'zh'
            : 'en';
      } catch (_) {
        // 解析失败仍允许入库，打开时报错
      }
    }

    final book = Book(
      id: id,
      title: title,
      author: author,
      filePath: rel,
      format: format,
      lang: lang,
      addedAt: DateTime.now(),
    );
    await _saveBooks([...books, book]);
    return book;
  }

  Future<void> removeBook(String id) async {
    final books = await listBooks();
    final book = books.where((b) => b.id == id).firstOrNull;
    if (book == null) return;
    await _saveBooks(books.where((b) => b.id != id).toList());
    final f = File(p.join(rootDir.path, book.filePath));
    if (await f.exists()) await f.delete();
    final s = _stateFile(id);
    if (await s.exists()) await s.delete();
  }

  /// 读取书的内容（阅读器用）。
  Future<LoadedBook> loadContent(Book book) async {
    final bytes = await File(p.join(rootDir.path, book.filePath)).readAsBytes();
    if (book.format == 'txt') {
      return loadTxt(bytes, fallbackTitle: book.title);
    }
    return loadEpub(bytes);
  }

  // ---------- 每本书的状态 ----------

  File _stateFile(String bookId) =>
      File(p.join(_stateDir.path, '$bookId.json'));

  Future<BookState> loadState(String bookId) async {
    final f = _stateFile(bookId);
    if (!await f.exists()) return BookState.empty();
    try {
      return BookState.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return BookState.empty();
    }
  }

  Future<void> saveState(String bookId, BookState state) async {
    await _stateDir.create(recursive: true);
    await _stateFile(bookId).writeAsString(jsonEncode(state.toJson()));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
