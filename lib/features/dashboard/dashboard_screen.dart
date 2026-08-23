import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:go_router/go_router.dart';

import '../../core/money/money.dart';
import '../../core/ui/empty_state.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Everything the dashboard renders, computed purely from the local DB.
class DashboardData {
  const DashboardData({
    required this.monthTotals,
    required this.weekTotals,
    required this.recent,
  });

  /// (previous, current) sums in piasters for month and week windows.
  final ({int previous, int current}) monthTotals;
  final ({int previous, int current}) weekTotals;
  final List<(ExpenseRow, String?)> recent;

  bool get isEmpty =>
      recent.isEmpty && monthTotals.current == 0 && weekTotals.current == 0;
}

final _dashboardProvider = StreamProvider.autoDispose<DashboardData>((ref) {
  final repo = ref.watch(expensesRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  final now = DateTime.now();

  final monthStart = DateTime(now.year, now.month);
  final monthEnd = DateTime(now.year, now.month + 1);
  final prevMonthStart = DateTime(now.year, now.month - 1);

  // Monday-anchored local-time week.
  final weekStart =
      DateTime(now.year, now.month, now.day - (now.weekday - DateTime.monday));
  final weekEnd = DateTime(now.year, now.month, now.day + 7 - (now.weekday - 1));
  final prevWeekStart = weekStart.subtract(const Duration(days: 7));

  return latestAll(
    [
      repo.watchWindowTotals(
        prevStart: prevMonthStart,
        windowStart: monthStart,
        windowEnd: monthEnd,
      ),
      repo.watchWindowTotals(
        prevStart: prevWeekStart,
        windowStart: weekStart,
        windowEnd: weekEnd,
      ),
      repo.watchRecentWithCategory(limit: 5),
    ],
    (values) => DashboardData(
      monthTotals: values[0] as ({int previous, int current}),
      weekTotals: values[1] as ({int previous, int current}),
      recent: values[2] as List<(ExpenseRow, String?)>,
    ),
  );
});

const _monthAbbrevs = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Combines the latest value of each source; emits once every source has
/// emitted, then again on any change. Each source emits on listen.
Stream<T> latestAll<T>(
  List<Stream<Object?>> sources,
  T Function(List<Object?>) project,
) {
  late final StreamController<T> controller;
  final subs = <StreamSubscription<Object?>>[];
  controller = StreamController<T>(
    onListen: () {
      final latest = List<Object?>.filled(sources.length, null);
      final ready = List<bool>.filled(sources.length, false);
      for (var i = 0; i < sources.length; i++) {
        final idx = i;
        subs.add(
          sources[idx].listen(
            (value) {
              latest[idx] = value;
              ready[idx] = true;
              if (ready.every((r) => r)) controller.add(project(latest));
            },
            onError: controller.addError,
          ),
        );
      }
    },
    onCancel: () => Future.wait(subs.map((s) => s.cancel())),
  );
  return controller.stream;
}

String _formatDay(DateTime d) => '${d.day} ${_monthAbbrevs[d.month - 1]}';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_dashboardProvider);
    return Scaffold(
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const EmptyState(
            icon: Icons.error_outline,
            title: 'Dashboard unavailable',
            message:
                'Your totals could not be read from the local ledger. Try again after restarting the app.',
          ),
          data: (data) => data.isEmpty
              ? const EmptyState(
                  icon: Icons.calendar_view_month_outlined,
                  title: 'Your month at a glance',
                  message:
                      'Totals and budgets land here once expenses exist. Capture starts with the ember button.',
                )
              : _DashboardContent(data: data),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      children: [
        Text(
          'This month',
          style: theme.textTheme.labelLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          formatEgp(data.monthTotals.current),
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        _DeltaLabel(current: data.monthTotals.current, previous: data.monthTotals.previous),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This week',
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  formatEgp(data.weekTotals.current),
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                _DeltaLabel(
                    current: data.weekTotals.current,
                    previous: data.weekTotals.previous),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: EdgeInsets.zero,
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Icon(Icons.bar_chart_outlined,
                color: theme.colorScheme.onSurfaceVariant),
            title: const Text('Reports'),
            subtitle: Text('Charts over your spending',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            trailing: Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant),
            onTap: () => context.push('/reports'),
          ),
        ),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => context.push('/budgets'),
          icon: const Icon(Icons.savings_outlined),
          label: const Text('Manage budgets'),
        ),
        if (data.recent.isNotEmpty) ...[
          Text(
            'Recent expenses',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          for (final (expense, category) in data.recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(category ?? 'Uncategorized'),
              subtitle: Text(_formatDay(expense.occurredAt),
                  style:
                      TextStyle(color: theme.colorScheme.onSurfaceVariant)),
              trailing: Text(
                formatEgp(expense.amountMinor),
                style: theme.textTheme.titleMedium,
              ),
            ),
        ],
      ],
    );
  }
}

class _DeltaLabel extends StatelessWidget {
  const _DeltaLabel({required this.current, required this.previous});

  final int current;
  final int previous;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final delta = current - previous;
    IconData icon;
    String label;
    if (previous == 0 && current == 0) {
      icon = Icons.trending_flat;
      label = 'No spending yet';
    } else if (previous == 0) {
      icon = Icons.trending_up;
      label = 'First spending in this window';
    } else if (delta > 0) {
      icon = Icons.trending_up;
      label = '+${(delta / previous * 100).round()}% vs last period';
    } else if (delta < 0) {
      icon = Icons.trending_down;
      label = '-${(-delta / previous * 100).round()}% vs last period';
    } else {
      icon = Icons.trending_flat;
      label = 'Flat vs last period';
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
