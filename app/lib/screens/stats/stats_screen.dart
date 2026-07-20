import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/reading_stats.dart';

String fmtDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final m = seconds ~/ 60;
  if (m < 60) return '$m 分钟';
  return '${(m / 60).toStringAsFixed(1)} 小时';
}

/// 阅读统计页：日/周/月/年聚合 + 连续天数 + 单书排行 + 26 周热力图。
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.stats, required this.books});

  final ReadingStatsStore stats;
  final List<Book> books;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  DailyStats? _data;
  String? _selectedDay; // 热力图点选的日期

  @override
  void initState() {
    super.initState();
    widget.stats.loadMerged().then((d) {
      if (mounted) setState(() => _data = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final now = DateTime.now();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('阅读统计')),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // —— 四档聚合 + 连续天数 ——
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _tile(context, '今日', fmtDuration(data.today(now))),
                    _tile(context, '本周', fmtDuration(data.thisWeek(now))),
                    _tile(context, '本月', fmtDuration(data.thisMonth(now))),
                    _tile(context, '今年', fmtDuration(data.thisYear(now))),
                    _tile(context, '连续阅读', '${data.streak(now)} 天'),
                  ],
                ),
                const SizedBox(height: 28),

                // —— 热力图 ——
                Text('过去半年',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface)),
                const SizedBox(height: 12),
                _Heatmap(
                  data: data,
                  now: now,
                  onTap: (day) => setState(() =>
                      _selectedDay = _selectedDay == day ? null : day),
                  selected: _selectedDay,
                ),
                const SizedBox(height: 8),
                // 图例：少 → 多（浓度阶）
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('少 ',
                        style:
                            TextStyle(fontSize: 11, color: scheme.outline)),
                    for (var lv = 0; lv <= 4; lv++)
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: _Heatmap.levelColor(context, lv),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    Text(' 多',
                        style:
                            TextStyle(fontSize: 11, color: scheme.outline)),
                  ],
                ),
                if (_selectedDay != null) _dayDetail(context, data),
                const SizedBox(height: 28),

                // —— 单书排行 ——
                Text('各书累计',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface)),
                const SizedBox(height: 8),
                ..._bookRanking(context, data),
                if (data.secondsByDay.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      children: [
                        Icon(Icons.hourglass_empty,
                            size: 40, color: scheme.outline),
                        const SizedBox(height: 12),
                        const Text('还没有阅读记录'),
                        const SizedBox(height: 6),
                        Text('打开一本书读几分钟，这里就会开始记录。',
                            style: TextStyle(
                                fontSize: 13, color: scheme.outline)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _tile(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant, width: .8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          // 数值走文本色（不是色阶色）——dataviz 规范
          Text(value,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _dayDetail(BuildContext context, DailyStats data) {
    final scheme = Theme.of(context).colorScheme;
    final day = _selectedDay!;
    final total = data.secondsByDay[day] ?? 0;
    final byBook = data.secondsByDayByBook[day] ?? {};
    String titleOf(String id) =>
        widget.books.where((b) => b.id == id).firstOrNull?.title ?? '已移除的书';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant, width: .8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$day · ${fmtDuration(total)}',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          for (final e in byBook.entries)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('《${titleOf(e.key)}》 ${fmtDuration(e.value)}',
                  style: TextStyle(
                      fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  List<Widget> _bookRanking(BuildContext context, DailyStats data) {
    final scheme = Theme.of(context).colorScheme;
    final totals = data.totalByBook().entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = totals.isEmpty ? 1 : totals.first.value;
    String titleOf(String id) =>
        widget.books.where((b) => b.id == id).firstOrNull?.title ?? '已移除的书';
    return [
      for (final e in totals.take(10))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 160,
                child: Text('《${titleOf(e.key)}》',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: e.value / max,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 64,
                child: Text(fmtDuration(e.value),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ),
            ],
          ),
        ),
    ];
  }
}

/// GitHub 式热力图：26 周 × 7 天，松绿单色浓度阶（单色渐变对色盲天然安全）。
class _Heatmap extends StatelessWidget {
  const _Heatmap(
      {required this.data,
      required this.now,
      required this.onTap,
      this.selected});

  final DailyStats data;
  final DateTime now;
  final void Function(String day) onTap;
  final String? selected;

  static const _weeks = 26;

  static Color levelColor(BuildContext context, int level) {
    final seed = Theme.of(context).colorScheme.primary;
    return switch (level) {
      0 => Theme.of(context).colorScheme.surfaceContainerHighest,
      1 => seed.withValues(alpha: .28),
      2 => seed.withValues(alpha: .5),
      3 => seed.withValues(alpha: .74),
      _ => seed,
    };
  }

  static int levelOf(int seconds) {
    if (seconds <= 0) return 0;
    final m = seconds / 60;
    if (m < 10) return 1;
    if (m < 30) return 2;
    if (m < 60) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    // 从本周往回 26 周；列 = 周，行 = 周一..周日
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final thisMonday =
        todayMidnight.subtract(Duration(days: now.weekday - 1));
    final firstMonday =
        thisMonday.subtract(const Duration(days: 7 * (_weeks - 1)));

    return LayoutBuilder(builder: (context, cons) {
      final cell = ((cons.maxWidth - 30) / _weeks - 3).clamp(8.0, 16.0);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行标（周一/周四/周日）
          Column(
            children: [
              for (var r = 0; r < 7; r++)
                SizedBox(
                  height: cell + 3,
                  width: 26,
                  child: (r == 0 || r == 3 || r == 6)
                      ? Text(['一', '', '', '四', '', '', '日'][r],
                          style: TextStyle(
                              fontSize: 10,
                              color:
                                  Theme.of(context).colorScheme.outline))
                      : null,
                ),
            ],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var r = 0; r < 7; r++)
                  Row(
                    children: [
                      for (var w = 0; w < _weeks; w++)
                        _cellFor(
                            context,
                            firstMonday
                                .add(Duration(days: w * 7 + r)),
                            todayMidnight,
                            cell),
                    ],
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _cellFor(
      BuildContext context, DateTime day, DateTime today, double size) {
    if (day.isAfter(today)) {
      return SizedBox(width: size + 3, height: size + 3);
    }
    final key = ReadingStatsStore.dayKey(day);
    final sec = data.secondsByDay[key] ?? 0;
    final isSelected = selected == key;
    return GestureDetector(
      onTap: () => onTap(key),
      child: Tooltip(
        message: '$key · ${fmtDuration(sec)}',
        waitDuration: const Duration(milliseconds: 400),
        child: Container(
          width: size,
          height: size,
          margin: const EdgeInsets.only(right: 3, bottom: 3),
          decoration: BoxDecoration(
            color: levelColor(context, levelOf(sec)),
            borderRadius: BorderRadius.circular(3),
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary, width: 1.5)
                : null,
          ),
        ),
      ),
    );
  }
}
