import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 阅读时长统计（对标主流阅读器的 stats 能力）。
///
/// 存储：stats/reading.<deviceId>.json —— 每台设备只写自己的文件，
/// Syncthing 同步目录不产生冲突；读取时把所有设备文件按日求和合并。
/// 结构：{ "days": { "2026-07-20": { "total": 秒, "books": { bookId: 秒 } } } }
class ReadingStatsStore {
  ReadingStatsStore(this.rootDir, {this.deviceId = 'local'});

  final Directory rootDir;
  final String deviceId;

  Directory get _dir => Directory(p.join(rootDir.path, 'stats'));
  File get _file => File(p.join(_dir.path, 'reading.$deviceId.json'));

  Map<String, dynamic> _own = {};
  bool _loaded = false;

  static String dayKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    if (await _file.exists()) {
      try {
        _own = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        _own = {};
      }
    }
    _loaded = true;
  }

  /// 累计阅读秒数（阅读器定期调用）。
  Future<void> addSeconds(String bookId, int seconds, {DateTime? at}) async {
    if (seconds <= 0) return;
    await _ensureLoaded();
    final key = dayKey(at ?? DateTime.now());
    final days = (_own['days'] as Map<String, dynamic>?) ?? {};
    final day = (days[key] as Map<String, dynamic>?) ?? {};
    final books = (day['books'] as Map<String, dynamic>?) ?? {};
    day['total'] = ((day['total'] as num?)?.toInt() ?? 0) + seconds;
    books[bookId] = ((books[bookId] as num?)?.toInt() ?? 0) + seconds;
    day['books'] = books;
    days[key] = day;
    _own['days'] = days;
    await _dir.create(recursive: true);
    await _file.writeAsString(jsonEncode(_own));
  }

  /// 合并读取所有设备的按日统计。
  Future<DailyStats> loadMerged() async {
    final totals = <String, int>{};
    final perBook = <String, Map<String, int>>{};
    if (await _dir.exists()) {
      await for (final e in _dir.list()) {
        if (e is! File || !p.basename(e.path).startsWith('reading.')) continue;
        try {
          final data =
              jsonDecode(await e.readAsString()) as Map<String, dynamic>;
          final days = (data['days'] as Map<String, dynamic>?) ?? {};
          for (final entry in days.entries) {
            final day = entry.value as Map<String, dynamic>;
            totals[entry.key] = (totals[entry.key] ?? 0) +
                ((day['total'] as num?)?.toInt() ?? 0);
            final books = (day['books'] as Map<String, dynamic>?) ?? {};
            final bucket = perBook.putIfAbsent(entry.key, () => {});
            for (final b in books.entries) {
              bucket[b.key] =
                  (bucket[b.key] ?? 0) + ((b.value as num?)?.toInt() ?? 0);
            }
          }
        } catch (_) {
          // 单个损坏文件不影响整体
        }
      }
    }
    return DailyStats(totals, perBook);
  }
}

/// 按日合并后的统计视图 + 聚合方法。
class DailyStats {
  DailyStats(this.secondsByDay, this.secondsByDayByBook);

  /// "yyyy-MM-dd" → 秒
  final Map<String, int> secondsByDay;
  final Map<String, Map<String, int>> secondsByDayByBook;

  int _sumRange(DateTime from, DateTime to) {
    var sum = 0;
    for (var d = DateTime(from.year, from.month, from.day);
        !d.isAfter(to);
        d = d.add(const Duration(days: 1))) {
      sum += secondsByDay[ReadingStatsStore.dayKey(d)] ?? 0;
    }
    return sum;
  }

  int today(DateTime now) => secondsByDay[ReadingStatsStore.dayKey(now)] ?? 0;

  /// 本周（周一起）。
  int thisWeek(DateTime now) =>
      _sumRange(now.subtract(Duration(days: now.weekday - 1)), now);

  int thisMonth(DateTime now) => _sumRange(DateTime(now.year, now.month), now);

  int thisYear(DateTime now) => _sumRange(DateTime(now.year), now);

  /// 全部时长按书聚合（跨所有天求和）。
  Map<String, int> totalByBook() {
    final out = <String, int>{};
    for (final day in secondsByDayByBook.values) {
      for (final e in day.entries) {
        out[e.key] = (out[e.key] ?? 0) + e.value;
      }
    }
    return out;
  }

  /// 连续阅读天数（从 now 往前数，今天没读则从昨天起算）。
  int streak(DateTime now) {
    var d = DateTime(now.year, now.month, now.day);
    if ((secondsByDay[ReadingStatsStore.dayKey(d)] ?? 0) == 0) {
      d = d.subtract(const Duration(days: 1));
    }
    var n = 0;
    while ((secondsByDay[ReadingStatsStore.dayKey(d)] ?? 0) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }
}
