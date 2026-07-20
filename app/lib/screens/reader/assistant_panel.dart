import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/explain_service.dart';
import '../../services/llm_client.dart';

/// AI 助读：针对整本书的多轮对话（「问这本书」）。
/// 复用 LlmClient 与 ExplainSession 的消息栈，带书名/章节/画像上下文与流式输出。
class AssistantPanel extends StatefulWidget {
  const AssistantPanel({
    super.key,
    required this.client,
    required this.model,
    required this.bookTitle,
    required this.author,
    required this.currentChapter,
    required this.currentExcerpt,
    required this.profile,
  });

  final LlmClient client;
  final String model;
  final String bookTitle;
  final String author;
  final String currentChapter;
  final String currentExcerpt; // 当前阅读位置附近的正文，供 AI 定位语境
  final UserProfile profile;

  @override
  State<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends State<AssistantPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<(String role, String text)> _turns = [];
  ExplainSession? _session;
  bool _busy = false;
  String _streaming = '';

  static const _suggestions = [
    '这一章讲了什么？',
    '这本书的核心观点是什么？',
    '刚读到的这段该怎么理解？',
    '作者是谁，什么背景？',
  ];

  String _system() {
    final personal = widget.profile.promptFragment();
    return '你是一位陪读助手，正在陪用户读《${widget.bookTitle}》'
        '${widget.author.isNotEmpty && widget.author != '未知作者' ? '（作者：${widget.author}）' : ''}。'
        '用户当前读到「${widget.currentChapter}」。'
        '以下是其当前阅读位置附近的原文，供你理解语境：\n---\n${widget.currentExcerpt}\n---\n'
        '$personal '
        '回答要求：紧扣这本书本身，用通俗中文；不知道就说不知道，不要编造书里没有的情节或事实；'
        '涉及尚未读到的章节时先提示「可能剧透」。回答控制在 300 字以内，直接说重点。';
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    setState(() {
      _turns.add(('user', text));
      _busy = true;
      _streaming = '';
    });
    _scrollToEnd();

    try {
      final session = _session ??= ExplainSession(
        client: widget.client,
        model: widget.model,
        system: _system(),
        firstUser: text,
      );
      if (_session != null && _turns.length > 1) {
        // 非首轮：把本轮 user 加入历史
        session.addFollowUp(text);
      }
      final buf = StringBuffer();
      await for (final chunk in session.send()) {
        buf.write(chunk);
        if (mounted) setState(() => _streaming = buf.toString());
        _scrollToEnd();
      }
      session.commitAssistant(buf.toString());
      if (mounted) {
        setState(() {
          _turns.add(('assistant', buf.toString()));
          _streaming = '';
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _turns.add(('assistant', '出问题了：$e\n\n检查 AI 服务是否可用（设置里可测试连接）。'));
          _streaming = '';
          _busy = false;
        });
      }
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('问这本书',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600))),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _turns.isEmpty && _streaming.isEmpty
              ? _emptyState(scheme)
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final t in _turns) _bubble(t.$1, t.$2, scheme),
                    if (_streaming.isNotEmpty)
                      _bubble('assistant', _streaming, scheme),
                    if (_busy && _streaming.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(children: [
                          const SizedBox(
                              width: 14,
                              height: 14,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('思考中…',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.outline)),
                        ]),
                      ),
                  ],
                ),
        ),
        // 输入区
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _busy ? null : _send,
                  decoration: InputDecoration(
                    hintText: '问关于这本书的任何问题…',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.arrow_upward, size: 20),
                onPressed: _busy ? null : () => _send(_input.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState(ColorScheme scheme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('随便问问这本书',
                  style: TextStyle(
                      fontSize: 14, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final s in _suggestions)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 12)),
                      onPressed: () => _send(s),
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _bubble(String role, String text, ColorScheme scheme) {
    final isUser = role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: SelectableText(text,
            style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: isUser
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface)),
      ),
    );
  }
}
