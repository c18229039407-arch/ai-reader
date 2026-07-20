import 'dart:convert';
import 'dart:io';

import 'package:ai_reader/services/reading_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReadingStatsStore', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('stats_test');
    });

    test('累计与按日读取', () async {
      final store = ReadingStatsStore(tmp, deviceId: 'mac');
      final day = DateTime(2026, 7, 20, 10);
      await store.addSeconds('book-a', 30, at: day);
      await store.addSeconds('book-a', 30, at: day);
      await store.addSeconds('book-b', 60, at: day);

      final data = await store.loadMerged();
      expect(data.secondsByDay['2026-07-20'], 120);
      expect(data.secondsByDayByBook['2026-07-20']!['book-a'], 60);
      expect(data.secondsByDayByBook['2026-07-20']!['book-b'], 60);
    });

    test('多设备文件按日求和合并', () async {
      final mac = ReadingStatsStore(tmp, deviceId: 'mac');
      final phone = ReadingStatsStore(tmp, deviceId: 'phone');
      final day = DateTime(2026, 7, 20);
      await mac.addSeconds('book-a', 100, at: day);
      await phone.addSeconds('book-a', 50, at: day);

      // 用第三个实例读取，验证合并的是磁盘上所有设备文件
      final reader = ReadingStatsStore(tmp, deviceId: 'other');
      final data = await reader.loadMerged();
      expect(data.secondsByDay['2026-07-20'], 150);
      expect(data.totalByBook()['book-a'], 150);
    });

    test('日/周/月/年聚合', () async {
      final store = ReadingStatsStore(tmp, deviceId: 'mac');
      final now = DateTime(2026, 7, 20); // 周一
      await store.addSeconds('b', 60, at: now); // 今天
      await store.addSeconds('b', 60, at: now.subtract(const Duration(days: 1))); // 昨天（上周日）
      await store.addSeconds('b', 60, at: DateTime(2026, 7, 1)); // 本月早些
      await store.addSeconds('b', 60, at: DateTime(2026, 1, 5)); // 今年早些
      await store.addSeconds('b', 60, at: DateTime(2025, 12, 30)); // 去年

      final d = await store.loadMerged();
      expect(d.today(now), 60);
      expect(d.thisWeek(now), 60, reason: '周一起算，昨天属上周');
      expect(d.thisMonth(now), 180, reason: '7-20、7-19、7-1 都在 7 月');
      expect(d.thisYear(now), 240, reason: '本年 4 天，不含去年 12-30');
    });

    test('连续阅读天数', () async {
      final store = ReadingStatsStore(tmp, deviceId: 'mac');
      final now = DateTime(2026, 7, 20);
      for (final off in [0, 1, 2, 4]) {
        // 连读今天/昨天/前天，第 4 天断档
        await store.addSeconds('b', 60,
            at: now.subtract(Duration(days: off)));
      }
      final d = await store.loadMerged();
      expect(d.streak(now), 3);
    });

    test('今天没读但昨天读了，streak 从昨天算', () async {
      final store = ReadingStatsStore(tmp, deviceId: 'mac');
      final now = DateTime(2026, 7, 20);
      await store.addSeconds('b', 60, at: now.subtract(const Duration(days: 1)));
      await store.addSeconds('b', 60, at: now.subtract(const Duration(days: 2)));
      final d = await store.loadMerged();
      expect(d.streak(now), 2);
    });

    test('损坏文件不影响其他设备读取', () async {
      final mac = ReadingStatsStore(tmp, deviceId: 'mac');
      await mac.addSeconds('b', 100, at: DateTime(2026, 7, 20));
      await File('${tmp.path}/stats/reading.corrupt.json')
          .writeAsString('{ 坏 json');
      final data = await mac.loadMerged();
      expect(data.secondsByDay['2026-07-20'], 100);
    });

    test('空/零秒不写入', () async {
      final store = ReadingStatsStore(tmp, deviceId: 'mac');
      await store.addSeconds('b', 0);
      await store.addSeconds('b', -5);
      final data = await store.loadMerged();
      expect(data.secondsByDay.isEmpty, isTrue);
    });

    test('JSON 结构可被独立解析（跨设备兼容）', () async {
      final store = ReadingStatsStore(tmp, deviceId: 'mac');
      await store.addSeconds('b', 30, at: DateTime(2026, 7, 20));
      final raw = jsonDecode(
              await File('${tmp.path}/stats/reading.mac.json').readAsString())
          as Map<String, dynamic>;
      expect((raw['days'] as Map).containsKey('2026-07-20'), isTrue);
    });
  });
}
