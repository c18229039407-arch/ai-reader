import 'dart:async';

import 'package:flutter/material.dart';

/// 解释/翻译展示面板：既用于「实时流式输出」（新请求），
/// 也用于「秒开留存内容」（D8 锚点点击，savedText != null）。
/// 宽屏嵌为侧栏，窄屏放进底部抽屉——由外层决定容器，本组件只管内容。
class ExplainPanel extends StatefulWidget {
  const ExplainPanel({
    super.key,
    required this.title,
    required this.quotedText,
    this.stream,
    this.savedText,
    this.onDone,
    this.onClose,
  }) : assert(stream != null || savedText != null, 'stream 与 savedText 至少提供一个');

  final String title;
  final String quotedText;
  final Stream<String>? stream;
  final String? savedText;

  /// 流式完成后回调完整文本（用于留存，D8）。
  final void Function(String fullText)? onDone;
  final VoidCallback? onClose;

  @override
  State<ExplainPanel> createState() => _ExplainPanelState();
}

class _ExplainPanelState extends State<ExplainPanel> {
  final _buffer = StringBuffer();
  StreamSubscription<String>? _sub;
  final _stopwatch = Stopwatch();
  int? _firstTokenMs;
  int? _totalMs;
  Object? _error;
  bool get _isSaved => widget.savedText != null;

  @override
  void initState() {
    super.initState();
    if (_isSaved) {
      _buffer.write(widget.savedText);
    } else {
      _stopwatch.start();
      _sub = widget.stream!.listen(
        (chunk) {
          _firstTokenMs ??= _stopwatch.elapsedMilliseconds;
          setState(() => _buffer.write(chunk));
        },
        onError: (e) => setState(() => _error = e),
        onDone: () {
          setState(() => _totalMs = _stopwatch.elapsedMilliseconds);
          if (_buffer.isNotEmpty) widget.onDone?.call(_buffer.toString());
        },
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _isSaved
        ? '本地留存 · 秒开'
        : [
            if (_firstTokenMs != null) '首字 ${_firstTokenMs}ms',
            if (_totalMs != null) '总计 ${_totalMs}ms',
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_isSaved ? '${widget.title}（已留存）' : widget.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (metrics.isNotEmpty)
                Text(metrics,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline)),
              if (widget.onClose != null)
                IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 18)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '「${widget.quotedText.length > 60 ? '${widget.quotedText.substring(0, 60)}…' : widget.quotedText}」',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.outline),
          ),
          const Divider(height: 18),
          Flexible(
            child: SingleChildScrollView(
              child: _error != null
                  ? Text('出错了：$_error\n\n请检查设置中的 Ollama 地址与模型。',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error))
                  : _buffer.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : SelectableText(_buffer.toString(),
                          style: const TextStyle(fontSize: 15, height: 1.7)),
            ),
          ),
        ],
      ),
    );
  }
}
