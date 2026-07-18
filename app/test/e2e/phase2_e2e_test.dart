// Phase 2 端到端检查（真实网络 + 真实 Ollama），默认跳过：
//   E2E=1 flutter test test/e2e/phase2_e2e_test.dart
// 覆盖：Gutendex 真搜索/下载/入库（A2/A3）→ 批量翻译真模型跑通（G2）。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_reader/services/batch_translator.dart';
import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/epub_loader.dart';
import 'package:ai_reader/services/library_store.dart';
import 'package:ai_reader/services/ollama_client.dart';
import 'package:ai_reader/services/translation_store.dart';

void main() {
  final enabled = Platform.environment['E2E'] == '1';
  final ollamaUrl =
      Platform.environment['OLLAMA_URL'] ?? 'http://127.0.0.1:11434';

  test(
    'Gutendex 搜索→下载→入库→真模型批量翻译前2段',
    () async {
      // 1) 真实公版书搜索与下载
      final source = GutendexSource();
      final results = await source.search('吶喊');
      expect(results, isNotEmpty);
      final hit = results.first;
      // ignore: avoid_print
      print('命中: ${hit.title} / ${hit.author} / ${hit.lang}');

      final bytes = await source.download(hit);
      expect(bytes.length, greaterThan(10000));
      // ignore: avoid_print
      print('下载: ${bytes.length} bytes');

      final tmp = await Directory.systemTemp.createTemp('phase2_e2e');
      addTearDown(() => tmp.delete(recursive: true));
      final store = LibraryStore(tmp, deviceId: 'e2e');
      final book = await store.importBytes(bytes, '${hit.title}.epub');
      final content = await store.loadContent(book);
      expect(content.chapters, isNotEmpty);
      // ignore: avoid_print
      print('入库: 《${book.title}》章节 ${content.chapters.length}');

      // 2) 真模型批量翻译（前 2 段）
      final client = OllamaClient(ollamaUrl);
      expect(await client.healthCheck(), true,
          reason: 'Ollama 不可达（$ollamaUrl）');
      final models = await client.listModels();
      expect(models, isNotEmpty);

      final slice =
          LoadedBook(title: content.title, author: content.author, chapters: [
        ChapterText(
            title: content.chapters.first.title,
            paragraphs: content.chapters.first.paragraphs.take(2).toList()),
      ]);
      final tStore = TranslationStore(tmp);
      final translator = BatchTranslator(
        client: client,
        model: models.first,
        store: tStore,
        bookId: book.id,
        book: slice,
      );
      final sw = Stopwatch()..start();
      await translator.run();
      sw.stop();

      expect(translator.status.value, BatchStatus.completed);
      final t = await tStore.load(book.id);
      expect(t.of(0, 0), isNotNull);
      expect(t.of(0, 1), isNotNull);
      // ignore: avoid_print
      print('翻译耗时 ${sw.elapsed}');
      // ignore: avoid_print
      print('原文[0:0]: ${slice.chapters[0].paragraphs[0]}');
      // ignore: avoid_print
      print('译文[0:0]: ${t.of(0, 0)}');
      // ignore: avoid_print
      print('译文[0:1]: ${t.of(0, 1)}');
    },
    skip: enabled ? false : '设 E2E=1 启用（需要网络与 Ollama）',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
