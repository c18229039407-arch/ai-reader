import 'dart:async';

import 'package:flutter/foundation.dart';

import 'epub_loader.dart';
import 'explain_service.dart';
import 'ollama_client.dart';
import 'translation_store.dart';

enum BatchStatus { idle, running, paused, completed, error }

/// 全书批量翻译任务（G2）：逐段送模型，边跑边落盘，可暂停/续跑。
/// 进度通过 [progress]/[status] 通知 UI；同一时刻一本书只跑一个任务。
class BatchTranslator {
  BatchTranslator({
    required this.client,
    required this.model,
    required this.store,
    required this.bookId,
    required this.book,
  });

  final OllamaClient client;
  final String model;
  final TranslationStore store;
  final String bookId;
  final LoadedBook book;

  final progress = ValueNotifier<double>(0);
  final status = ValueNotifier<BatchStatus>(BatchStatus.idle);
  final lastError = ValueNotifier<String>('');

  bool _stopRequested = false;

  int get totalParagraphs =>
      book.chapters.fold(0, (n, c) => n + c.paragraphs.length);

  /// 需要翻译的段落判断：足够长且不是纯 ASCII 之外全部翻（MVP：全翻，
  /// 但跳过过短的段落如页码/分隔符）。
  static bool worthTranslating(String s) => s.trim().length >= 2;

  Future<void> run() async {
    if (status.value == BatchStatus.running) return;
    _stopRequested = false;
    status.value = BatchStatus.running;
    lastError.value = '';

    final t = await store.load(bookId);
    t.model = model;
    final total = totalParagraphs;
    var done = t.paras.length;
    progress.value = total == 0 ? 1 : done / total;

    try {
      var sinceSave = 0;
      for (var c = 0; c < book.chapters.length; c++) {
        final ch = book.chapters[c];
        for (var i = 0; i < ch.paragraphs.length; i++) {
          if (_stopRequested) {
            await store.save(bookId, t);
            status.value = BatchStatus.paused;
            return;
          }
          final key = '$c:$i';
          if (t.paras.containsKey(key)) continue;
          final src = ch.paragraphs[i];
          if (!worthTranslating(src)) {
            t.paras[key] = src;
          } else {
            final buf = StringBuffer();
            await for (final chunk in client.chatStream(
              model: model,
              system: ExplainService.translateSystem(),
              user: src,
            )) {
              buf.write(chunk);
            }
            t.paras[key] = buf.toString().trim();
          }
          done++;
          sinceSave++;
          progress.value = done / total;
          if (sinceSave >= 5) {
            await store.save(bookId, t); // 断点续跑的落盘粒度
            sinceSave = 0;
          }
        }
      }
      t.completed = true;
      await store.save(bookId, t);
      status.value = BatchStatus.completed;
    } catch (e) {
      await store.save(bookId, t);
      lastError.value = '$e';
      status.value = BatchStatus.error;
    }
  }

  void pause() => _stopRequested = true;
}
