import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/explain_service.dart';

/// 解释/翻译面板。三种用法：
/// 1) 新请求：传 [session]，流式输出，完成后可「换例/更深/一句话/追问」（D5/D6）；
/// 2) 锚点秒开：传 [savedText]，直接展示留存内容；
/// 宽屏嵌侧栏 / 窄屏进底部抽屉由外层决定，本组件只管内容。
class ExplainPanel extends StatefulWidget {
  const ExplainPanel({
    super.key,
    required this.title,
    required this.quotedText,
    this.session,
    this.savedText,
    this.onFirstAnswer,
    this.onClose,
  }) : assert(
            session != null || savedText != null, 'session 与 savedText 至少提供一个');

  final String title;
  final String quotedText;
  final ExplainSession? session;
  final String? savedText;

  /// 首轮回答完成的回调（用于 D8 留存；追问轮不再重复留存）。
  final void Function(String fullText)? onFirstAnswer;
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
  bool _streamDone = false;
  bool _firstRound = true;
  final _followUp = TextEditingController();

  bool get _isSaved => widget.savedText != null;

  @override
  void initState() {
    super.initState();
    if (_isSaved) {
      _buffer.write(widget.savedText);
      _streamDone = true;
    } else {
      _start();
    }
  }

  void _start() {
    _stopwatch
      ..reset()
      ..start();
    _firstTokenMs = null;
    _totalMs = null;
    _streamDone = false;
    _buffer.clear();
    _sub = widget.session!.send().listen(
      (chunk) {
        _firstTokenMs ??= _stopwatch.elapsedMilliseconds;
        if (mounted) setState(() => _buffer.write(chunk));
      },
      onError: (e) {
        if (mounted) setState(() => _error = e);
      },
      onDone: () {
        final full = _buffer.toString();
        widget.session!.commitAssistant(full);
        if (_firstRound && full.isNotEmpty) {
          widget.onFirstAnswer?.call(full);
          _firstRound = false;
        }
        if (mounted) {
          setState(() {
            _totalMs = _stopwatch.elapsedMilliseconds;
            _streamDone = true;
          });
        }
      },
    );
  }

  void _ask(String instruction) {
    if (!_streamDone || widget.session == null) return;
    widget.session!.addFollowUp(instruction);
    _sub?.cancel();
    setState(_start);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _stopwatch.stop();
    _followUp.dispose();
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
          // D5/D6：追问与深度控制（仅会话模式、且当前轮已完成时可用）
          if (!_isSaved) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('换个例子'),
                  onPressed: _streamDone
                      ? () => _ask(ExplainSession.presets['anotherExample']!)
                      : null,
                ),
                ActionChip(
                  label: const Text('更深入'),
                  onPressed: _streamDone
                      ? () => _ask(ExplainSession.presets['deeper']!)
                      : null,
                ),
                ActionChip(
                  label: const Text('一句话'),
                  onPressed: _streamDone
                      ? () => _ask(ExplainSession.presets['oneLiner']!)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _followUp,
                    enabled: _streamDone,
                    decoration: const InputDecoration(
                      hintText: '继续追问…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      _followUp.clear();
                      _ask(v.trim());
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _streamDone
                      ? () {
                          final v = _followUp.text.trim();
                          if (v.isEmpty) return;
                          _followUp.clear();
                          _ask(v);
                        }
                      : null,
                  icon: const Icon(Icons.send, size: 18),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
