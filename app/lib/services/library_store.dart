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
  LibraryStore(this.rootDir, {this.deviceId = 'local'});

  final Directory rootDir;

  /// 本设备标识（E4）：决定本机状态文件名，避免多设备写同一文件。
  final String deviceId;

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
    final format = switch (ext) {
      'txt' => 'txt',
      'pdf' => 'pdf',
      _ => 'epub',
    };
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

  /// 更新书目元数据（B3 标签编辑等）。
  Future<void> updateBook(Book updated) async {
    final books = await listBooks();
    await _saveBooks(
        books.map((b) => b.id == updated.id ? updated : b).toList());
  }

  /// 书籍文件的绝对路径（PDF 查看器需要）。
  String absolutePath(Book book) => p.join(rootDir.path, book.filePath);

  /// 导出书架元数据 + 全部阅读状态（B5，不含书籍文件本体）。
  Future<String> exportBundle() async {
    final books = await listBooks();
    final states = <String, dynamic>{};
    for (final b in books) {
      states[b.id] = (await loadState(b.id)).toJson();
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'ai-reader-bundle-v1',
      'exportedAt': DateTime.now().toIso8601String(),
      'books': books.map((b) => b.toJson()).toList(),
      'states': states,
    });
  }

  /// 导入元数据包（B5）：书目按 id 合并（已存在的保留本地文件路径），
  /// 状态与本地状态做多设备合并。书籍文件本体不在包内，缺文件的书打开时会提示。
  Future<int> importBundle(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['format'] != 'ai-reader-bundle-v1') {
      throw Exception('不是有效的 AI Reader 导出包');
    }
    final incoming = ((data['books'] as List?) ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
    final local = await listBooks();
    final byId = {for (final b in local) b.id: b};
    var added = 0;
    for (final b in incoming) {
      if (!byId.containsKey(b.id)) {
        byId[b.id] = b;
        added++;
      } else {
        // 已存在：合并标签
        final merged = {...byId[b.id]!.tags, ...b.tags}.toList();
        byId[b.id] = byId[b.id]!.copyWith(tags: merged);
      }
    }
    await _saveBooks(byId.values.toList());

    final states = (data['states'] as Map?) ?? {};
    for (final entry in states.entries) {
      final incomingState =
          BookState.fromJson(entry.value as Map<String, dynamic>);
      final localState = await loadState(entry.key as String);
      await saveState(
          entry.key as String, mergeStates([localState, incomingState]));
    }
    return added;
  }

  Future<void> removeBook(String id) async {
    final books = await listBooks();
    final book = books.where((b) => b.id == id).firstOrNull;
    if (book == null) return;
    await _saveBooks(books.where((b) => b.id != id).toList());
    final f = File(p.join(rootDir.path, book.filePath));
    if (await f.exists()) await f.delete();
    // 清理该书所有设备的状态文件
    if (await _stateDir.exists()) {
      await for (final e in _stateDir.list()) {
        final name = p.basename(e.path);
        if (e is File &&
            name.endsWith('.json') &&
            (name == '$id.json' || name.startsWith('$id.'))) {
          await e.delete();
        }
      }
    }
  }

  /// 读取书的内容（阅读器用）。
  Future<LoadedBook> loadContent(Book book) async {
    final bytes = await File(p.join(rootDir.path, book.filePath)).readAsBytes();
    if (book.format == 'txt') {
      return loadTxt(bytes, fallbackTitle: book.title);
    }
    return loadEpub(bytes);
  }

  // ---------- 每本书的状态（E3/E4：按设备分文件写、读取时合并）----------
  //
  // 写入：state/<bookId>.<deviceId>.json —— 每台设备只写自己的文件，
  // Syncthing 同步目录时不会产生二进制冲突。
  // 读取：合并该书的所有设备文件（含旧版无 deviceId 的 legacy 文件）：
  //   reading   → 取 updatedAt 最新的一份
  //   highlights→ 按 locator+createdAt 去重求并集
  //   explanations → 按 id 去重求并集

  File _stateFile(String bookId) =>
      File(p.join(_stateDir.path, '$bookId.$deviceId.json'));

  Future<BookState> loadState(String bookId) async {
    final files = <File>[];
    if (await _stateDir.exists()) {
      await for (final e in _stateDir.list()) {
        final name = p.basename(e.path);
        if (e is File &&
            name.endsWith('.json') &&
            (name == '$bookId.json' || name.startsWith('$bookId.'))) {
          files.add(e);
        }
      }
    }
    if (files.isEmpty) return BookState.empty();

    final states = <BookState>[];
    for (final f in files) {
      try {
        states.add(BookState.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // 单个损坏文件不拖垮整体
      }
    }
    if (states.isEmpty) return BookState.empty();
    return mergeStates(states);
  }

  /// 合并多设备状态（纯函数，可测试）。
  static BookState mergeStates(List<BookState> states) {
    if (states.isEmpty) return BookState.empty();
    var reading = states.first.reading;
    final highlights = <String, Highlight>{};
    final explanations = <String, Explanation>{};
    final notes = <String, NoteAnn>{};
    final bookmarks = <String, Bookmark>{};
    for (final s in states) {
      if (s.reading.updatedAt.isAfter(reading.updatedAt)) {
        reading = s.reading;
      }
      for (final h in s.highlights) {
        highlights['${h.locator}|${h.createdAt.toIso8601String()}'] = h;
      }
      for (final e in s.explanations) {
        explanations[e.id] = e;
      }
      for (final n in s.notes) {
        notes['${n.locator}|${n.createdAt.toIso8601String()}'] = n;
      }
      for (final b in s.bookmarks) {
        bookmarks['${b.chapterIndex}|${b.createdAt.toIso8601String()}'] = b;
      }
    }
    List<T> sorted<T>(Iterable<T> it, DateTime Function(T) key) =>
        it.toList()..sort((a, b) => key(a).compareTo(key(b)));
    return BookState(
      reading: reading,
      highlights: sorted(highlights.values, (h) => h.createdAt),
      explanations: sorted(explanations.values, (e) => e.createdAt),
      notes: sorted(notes.values, (n) => n.createdAt),
      bookmarks: sorted(bookmarks.values, (b) => b.createdAt),
    );
  }

  Future<void> saveState(String bookId, BookState state) async {
    await _stateDir.create(recursive: true);
    await _stateFile(bookId).writeAsString(jsonEncode(state.toJson()));
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
