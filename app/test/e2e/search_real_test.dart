import 'dart:io';

import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/s2t_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// 真实网络端到端：验证「简体输入 → 繁体回退」在真 Gutendex 上成立。
/// 运行：E2E=1 flutter test test/e2e/search_real_test.dart
void main() {
  final enabled = Platform.environment['E2E'] == '1';

  test('真实 Gutendex：简体「呐喊」经繁体回退能搜到结果', () async {
    if (!enabled) {
      markTestSkipped('设 E2E=1 才执行（需要外网）');
      return;
    }
    final source = GutendexSource();

    // 模拟 SearchScreen._searchWithFallback 的逻辑
    const q = '呐喊';
    var results = await source.search(q);
    String? converted;
    if (results.isEmpty) {
      final trad = toTraditional(q);
      expect(trad, '吶喊');
      results = await source.search(trad);
      if (results.isNotEmpty) converted = trad;
    }

    expect(results, isNotEmpty, reason: '简体呐喊经回退后必须有结果');
    expect(converted, '吶喊', reason: '应当是繁体回退命中的');
    expect(results.first.title, contains('吶喊'));
    // ignore: avoid_print
    print('✓ 「呐喊」→ 繁体回退 → ${results.length} 条：${results.first.title}（${results.first.author}）');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('真实 Gutendex：英文作者 Adam Smith 直接命中', () async {
    if (!enabled) {
      markTestSkipped('设 E2E=1 才执行（需要外网）');
      return;
    }
    final results = await GutendexSource().search('Adam Smith');
    expect(results, isNotEmpty);
    // ignore: avoid_print
    print('✓ 「Adam Smith」直接命中 ${results.length} 条');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
