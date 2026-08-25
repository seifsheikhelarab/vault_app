import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/date_labels.dart';
import '../../core/money/money.dart';
import '../../core/stream/latest_all.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/paint.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Chart windows mirror the dashboard's half-open semantics exactly:
/// calendar month `[firstOfMonth, firstOfNextMonth)` and Monday-anchored
/// local week `[monday, nextMonday)`.
enum ReportsWindow { week, month }

class _WindowBounds {
  const _WindowBounds(this.start, this.end, this.days);

  final DateTime start;
  final DateTime end;

  /// Whole days in the window; the trend line plots exactly this many
  /// points (daily for both windows — one consistent grain).
  final int days;
}

_WindowBounds _boundsFor(ReportsWindow window) {
  final now = DateTime.now();
  switch (window) {
    case ReportsWindow.week:
      final monday = DateTime(
          now.year, now.month, now.day - (now.weekday - DateTime.monday));
      return _WindowBounds(monday, monday.add(const Duration(days: 7)), 7);
    case ReportsWindow.month:
      final start = DateTime(now.year, now.month);
      final end = DateTime(now.year, now.month + 1);
      return _WindowBounds(start, end, end.difference(start).inDays);
  }
}

class _ReportsData {
  const _ReportsData({required this.byCategory, required this.perDay});

  final Map<String?, int> byCategory;
  final Map<int, int> perDay;

  int get total => byCategory.values.fold(0, (sum, minor) => sum + minor);
}

final _reportsProvider =
    StreamProvider.autoDispose.family<_ReportsData, ReportsWindow>(
        (ref, window) {
  final repo = ref.watch(expensesRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  final bounds = _boundsFor(window);
  return latestAll(
    [
      repo.watchSpendBetween(bounds.start, bounds.end),
      repo.watchSpendPerDay(start: bounds.start, end: bounds.end),
    ],
    (values) => _ReportsData(
      byCategory: values[0]! as Map<String?, int>,
      perDay: values[1]! as Map<int, int>,
    ),
  );
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: SafeArea(
        child: ReportsPanel(),
      ),
    );
  }
}

/// The full reports body — window toggle, category breakdown, daily trend.
/// Embeddable: the dashboard hosts it directly (scrollable: false), the
/// /reports route wraps it in a Scaffold.
class ReportsPanel extends ConsumerStatefulWidget {
  const ReportsPanel({this.scrollable = true, super.key});

  /// True inside the /reports route (fills remaining height); false when
  /// embedded in a scrolling parent like the dashboard.
  final bool scrollable;

  @override
  ConsumerState<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends ConsumerState<ReportsPanel> {
  ReportsWindow _window = ReportsWindow.week;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_reportsProvider(_window));
    final embedded = !widget.scrollable;
    final content = async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const EmptyState(
        icon: Icons.error_outline,
        title: 'Reports unavailable',
        message:
            'Charts could not be read from the local ledger. Try again after restarting the app.',
      ),
      data: (data) => data.total == 0
          ? EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: 'No spending '
                  '${_window == ReportsWindow.week ? 'this week' : 'this month'}',
              message:
                  'Breakdowns and trends appear here once expenses land in this window. Capture starts with the ember button.',
            )
          : _ReportsContent(
              data: data,
              window: _window,
              shrinkWrap: embedded,
            ),
    );
    if (embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            child: SegmentedButton<ReportsWindow>(
              segments: const [
                ButtonSegment(
                    value: ReportsWindow.week, label: Text('Week')),
                ButtonSegment(
                    value: ReportsWindow.month, label: Text('Month')),
              ],
              selected: {_window},
              onSelectionChanged: (selection) =>
                  setState(() => _window = selection.first),
            ),
          ),
          content,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SegmentedButton<ReportsWindow>(
            segments: const [
              ButtonSegment(value: ReportsWindow.week, label: Text('Week')),
              ButtonSegment(
                  value: ReportsWindow.month, label: Text('Month')),
            ],
            selected: {_window},
            onSelectionChanged: (selection) =>
                setState(() => _window = selection.first),
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

/// One resolved pie slice: label, amount, and its assigned scheme-role
/// color. Colors are decided once here so chart and legend always agree.
class _Slice {
  const _Slice(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

/// Slice tones come from the shared [categoryTone] rotation so a category
/// reads as one paint dab everywhere — list swatches, pie, and legend.
/// Uncategorized abstains to neutral (`outline`) by construction.
List<_Slice> _buildSlices(
    List<MapEntry<String?, int>> entries,
    Map<String, String> categoryNames,
    ColorScheme scheme) {
  return [
    for (final entry in entries)
      _Slice(
        entry.key == null
            ? 'Uncategorized'
            : categoryNames[entry.key] ?? 'Uncategorized',
        entry.value,
        categoryTone(entry.key, scheme),
      ),
  ];
}

class _ReportsContent extends ConsumerWidget {
  const _ReportsContent({
    required this.data,
    required this.window,
    this.shrinkWrap = false,
  });

  final _ReportsData data;
  final ReportsWindow window;

  /// Embedded mode: shrink-wrap into a scrolling parent, no own padding.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bounds = _boundsFor(window);
    final sorted = data.byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final categoryNames = {
      for (final row in ref.watch(categoriesListProvider).value ?? const <CategoryRow>[])
        row.id: row.name,
    };
    final slices =
        _buildSlices(sorted, categoryNames, theme.colorScheme);
    return ListView(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: shrinkWrap
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(24, 0, 24, 96),
      children: [
        _ChartCard(
          title: 'Spend by category',
          footer: _CategoryLegend(slices: slices),
          child: _CategoryPie(slices: slices),
        ),
        const SizedBox(height: 16),
        _ChartCard(
          title: 'Daily trend',
          child: _TrendLine(perDay: data.perDay, bounds: bounds),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.child,
    this.footer,
  });

  final String title;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RegistrationLabel(title),
          const SizedBox(height: 16),
          child,
          if (footer != null) ...[
            const SizedBox(height: 16),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _CategoryPie extends StatelessWidget {
  const _CategoryPie({required this.slices});

  final List<_Slice> slices;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        height: 200,
        width: 200,
        child: PieChart(
          PieChartData(
            sections: [
              for (final slice in slices)
                PieChartSectionData(
                  value: slice.value.toDouble(),
                  color: slice.color,
                  radius: 44,
                  showTitle: false,
                ),
            ],
            centerSpaceRadius: 52,
            sectionsSpace: 2,
          ),
        ),
      ),
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({required this.slices});

  final List<_Slice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: slice.color,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text(slice.label, style: theme.textTheme.bodyMedium),
                ),
                Text(formatEgp(slice.value),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }
}

/// One point per day of the window (gaps zero-filled). Daily grain for both
/// week and month keeps the reading identical across the toggle.
class _TrendLine extends StatelessWidget {
  const _TrendLine({required this.perDay, required this.bounds});

  final Map<int, int> perDay;
  final _WindowBounds bounds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var maxMinor = 0;
    for (final v in perDay.values) {
      maxMinor = math.max(maxMinor, v);
    }
    final spots = [
      for (var day = 0; day < bounds.days; day++)
        FlSpot(day.toDouble(), (perDay[day] ?? 0).toDouble()),
    ];
    final yStep = _yStep(maxMinor).toDouble();
    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: math.max(maxMinor * 1.15, yStep),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: yStep,
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: false,
              barWidth: 2,
              color: scheme.primary,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, _, _, _) =>
                    FlDotCirclePainter(radius: 2, color: scheme.primary),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: yStep,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    formatPiasters(value.round()),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: bounds.days <= 7 ? 1 : 7,
                getTitlesWidget: (value, _) =>
                    _dayLabel(value, bounds, theme),
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }

  static Widget _dayLabel(double value, _WindowBounds bounds, ThemeData theme) {
    final day = value.round();
    if (day < 0 || day >= bounds.days) return const SizedBox.shrink();
    final date = bounds.start.add(Duration(days: day));
    final label = bounds.days <= 7
        ? weekdaysShort[date.weekday - DateTime.monday]
        : '${date.day}';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  /// Roundest multiple of 100 piasters giving ~3 y ticks; axis labels stay
  /// whole-pound figures instead of fractional noise.
  static int _yStep(int maxMinor) {
    final rough = (maxMinor / 3).ceil();
    if (rough <= 0) return 100;
    return ((rough + 99) ~/ 100) * 100;
  }
}
