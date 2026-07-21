import 'dart:io';

import 'package:ai_reader/services/book_source.dart';
import 'package:ai_reader/services/cover_fetcher.dart';
import 'package:ai_reader/services/epub_loader.dart';
import 'package:ai_reader/services/s2t_map.dart';
import 'package:ai_reader/services/title_atlas.dart';
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

  test('真实维基文库：简体「骆驼祥子」命中近现代作品并可下载 EPUB', () async {
    if (!enabled) {
      markTestSkipped('设 E2E=1 才执行（需要外网）');
      return;
    }
    final source = WikisourceZhSource();
    final results = await source.search('骆驼祥子');
    expect(results, isNotEmpty, reason: '老舍 1966 年逝世，其作品在中国已入公有领域');
    final main = results.firstWhere((r) => r.title == '駱駝祥子');

    final bytes = await source.download(main);
    expect(bytes.length, greaterThan(10 * 1024));
    expect(bytes[0], 0x50); // 'P'
    expect(bytes[1], 0x4B); // 'K' — EPUB(zip) 魔数

    // 阅读器真能打开：epubx 解析出章节与正文
    final loaded = await loadEpub(bytes);
    expect(loaded.chapters, isNotEmpty, reason: '下载的 EPUB 必须能被阅读器解析');
    final totalChars = loaded.chapters
        .fold<int>(0, (n, c) => n + c.paragraphs.join().length);
    expect(totalChars, greaterThan(1000));

    // 清理回归：不残留 WSExport 的导航条/导出说明/about 页
    final allText = loaded.chapters.expand((c) => c.paragraphs).join('\n');
    expect(allText, isNot(contains('上一章')));
    expect(allText, isNot(contains('从维基文库导出')));
    expect(allText, isNot(contains('Wsexport')));
    // ignore: avoid_print
    print('✓ 维基文库「骆驼祥子」→ ${results.length} 条，EPUB ${bytes.length ~/ 1024}KB，'
        '解析 ${loaded.chapters.length} 章 / $totalChars 字');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('真实维基文库反例：版权期内新书「小岛经济学」必须 0 结果（不返回无关公文）', () async {
    if (!enabled) {
      markTestSkipped('设 E2E=1 才执行（需要外网）');
      return;
    }
    final results = await WikisourceZhSource().search('小岛经济学');
    expect(results, isEmpty,
        reason: '标题限定后不应再把正文碰巧含「经济」等字样的判决书/公文当结果');
    // ignore: avoid_print
    print('✓ 反例「小岛经济学」→ 0 条（此前全文检索会返回判决书等噪音）');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('真实 Gutendex：名著地图四本书的原名检索词全部命中', () async {
    if (!enabled) {
      markTestSkipped('设 E2E=1 才执行（需要外网）');
      return;
    }
    final source = GutendexSource();
    for (final zh in ['瓦尔登湖', '理想国', '苏格拉底的申辩', '社会契约论']) {
      final hit = atlasLookup(zh)!;
      final results = await source.search(hit.$1);
      expect(results, isNotEmpty, reason: '$zh → ${hit.$1} 应命中');
      // ignore: avoid_print
      print('✓ $zh → ${hit.$2}：${results.first.title}');
    }
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('真实 Open Library：英文书能联网取到封面', () async {
    if (!enabled) {
      markTestSkipped('设 E2E=1 才执行（需要外网）');
      return;
    }
    final bytes = await CoverFetcher().fetch('The Wealth of Nations');
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(5 * 1024));
    // ignore: avoid_print
    print('✓ Open Library 封面 ${bytes.length ~/ 1024}KB');
  }, timeout: const Timeout(Duration(minutes: 3)));

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
