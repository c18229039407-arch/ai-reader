import 'dart:async';

import 'package:flutter/material.dart';

import 'ollama_client.dart';

enum ExplainMode { explain, translate }

/// 解释/翻译结果面板：流式渲染 + 首字延迟计时（Phase 0 验收指标）。
class ExplainSheet extends StatefulWidget {
  const ExplainSheet({
    super.key,
    required this.client,
    required this.model,
    required this.mode,
    required this.selectedText,
    required this.bookTitle,
    required this.chapterTitle,
    required this.occupation,
  });

  final OllamaClient client;
  final String model;
  final ExplainMode mode;
  final String selectedText;
  final String bookTitle;
  final String chapterTitle;
  final String occupation;

  @override
  State<ExplainSheet> createState() => _ExplainSheetState();
}

class _ExplainSheetState extends State<ExplainSheet> {
  final _buffer = StringBuffer();
  StreamSubscription<String>? _sub;
  final _stopwatch = Stopwatch();
  int? _firstTokenMs;
  int? _totalMs;
  Object? _error;

  String get _system {
    switch (widget.mode) {
      case ExplainMode.explain:
        final profile = widget.occupation.trim().isEmpty
            ? ''
            : '读者的职业/背景是：${widget.occupation}。举例时请优先使用贴合这个背景的日常场景做类比。';
        return '你是一位擅长把难懂概念讲通俗的阅读助手。'
            '用户正在读《${widget.bookTitle}》的「${widget.chapterTitle}」一章，'
            '会给你一段书中原文。请：'
            '1) 用通俗中文解释其中的核心概念，禁止用术语解释术语；'
            '2) 给一个具体的生活化例子；$profile '
            '3) 如该概念在本书语境中有特定含义，简要指出。'
            '控制在 200 字以内，直接输出解释，不要客套。';
      case ExplainMode.translate:
        return '你是翻译助手。把用户给出的段落翻译成流畅的简体中文，'
            '目标是让读者看懂，语义准确优先于文采。只输出译文。';
    }
  }

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _sub = widget.client
        .chatStream(
      model: widget.model,
      system: _system,
      user: widget.selectedText,
    )
        .listen(
      (chunk) {
        _firstTokenMs ??= _stopwatch.elapsedMilliseconds;
        setState(() => _buffer.write(chunk));
      },
      onError: (e) => setState(() => _error = e),
      onDone: () => setState(() => _totalMs = _stopwatch.elapsedMilliseconds),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.mode == ExplainMode.explain ? 'AI 解释' : 'AI 翻译';
    final metrics = [
      if (_firstTokenMs != null) '首字 ${_firstTokenMs}ms',
      if (_totalMs != null) '总计 ${_totalMs}ms',
    ].join(' · ');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (metrics.isNotEmpty)
                  Text(
                    metrics,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '「${widget.selectedText.length > 60 ? '${widget.selectedText.substring(0, 60)}…' : widget.selectedText}」',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const Divider(height: 20),
            Flexible(
              child: SingleChildScrollView(
                child: _error != null
                    ? Text(
                        '出错了：$_error\n\n请检查设置页的 Ollama 地址与模型。',
                        style: const TextStyle(color: Colors.red),
                      )
                    : _buffer.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : SelectableText(
                            _buffer.toString(),
                            style: const TextStyle(fontSize: 15, height: 1.6),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
