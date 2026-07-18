import 'package:flutter/material.dart';

import '../../models/models.dart';

/// 概念本（D10 的 MVP 形态）：一本书内全部留存解释的汇总列表。
class ConceptsScreen extends StatelessWidget {
  const ConceptsScreen({
    super.key,
    required this.bookTitle,
    required this.explanations,
    this.onJump,
  });

  final String bookTitle;
  final List<Explanation> explanations;

  /// 点击条目回跳原文（由阅读器传入）。
  final void Function(Locator locator)? onJump;

  @override
  Widget build(BuildContext context) {
    final list = [...explanations]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(title: Text('概念本 · $bookTitle')),
      body: list.isEmpty
          ? Center(
              child: Text('还没有留存的解释\n阅读中划选文字 →「AI 解释」即可自动沉淀',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.outline)))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final e = list[i];
                return Card(
                  child: ExpansionTile(
                    leading: Icon(
                        e.mode == 'translate'
                            ? Icons.translate
                            : Icons.auto_awesome,
                        size: 20),
                    title: Text(e.term,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '位置 ${e.locator} · ${e.createdAt.toLocal().toString().substring(0, 16)}',
                        style: const TextStyle(fontSize: 12)),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(e.resultText,
                            style: const TextStyle(fontSize: 14, height: 1.7)),
                      ),
                      if (onJump != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.my_location, size: 16),
                            label: const Text('跳到原文'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              onJump!(e.locator);
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
