import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/date_labels.dart';
import '../../core/money/money.dart';
import '../../core/stream/latest_all.dart';
import '../../core/ui/empty_state.dart';
import '../../core/ui/paint.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import '../budgets/budget_providers.dart';
import '../recurring/recurring_providers.dart';
import '../reports/reports_screen.dart';

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

String _formatDay(DateTime d) => '${d.day} ${monthsShort[d.month - 1]}';

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

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(budgetProgressProvider);
    final categories = ref.watch(categoriesListProvider).value ?? const [];
    final names = {for (final c in categories) c.id: c.name};
    final recurrings = ref.watch(recurringListProvider).value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 160),
      children: [
        // The painted wall: month state committed to one full-bleed field.
        // Literal field teal in both brightnesses — the committed field
        // never pales to a derived dark-mode tint.
        ScoredPanel(
          color: VaultColors.fieldSeed,
          slope: 16,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RegistrationLabel('This month',
                  color: Colors.white.withValues(alpha: 0.85)),
              const SizedBox(height: 8),
              MoneyMass(
                data.monthTotals.current,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 6),
              _DeltaLabel(
                current: data.monthTotals.current,
                previous: data.monthTotals.previous,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RegistrationLabel('This week'),
                    const SizedBox(height: 6),
                    Text(
                      formatEgp(data.weekTotals.current),
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 2),
                    _DeltaLabel(
                      current: data.weekTotals.current,
                      previous: data.weekTotals.previous,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Reports live on the dashboard: breakdown and trend inline.
              ReportsPanel(scrollable: false),
              const SizedBox(height: 20),
              if (progress.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(child: RegistrationLabel('Budgets')),
                    TextButton(
                      onPressed: () => context.push('/budgets'),
                      child: const Text('Manage'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final p in progress)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => context.push('/budgets/${p.budget.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CategorySwatch(categoryId: p.budget.categoryId, size: 12),
                              Expanded(
                                child: Text(
                                  p.budget.categoryId == null
                                      ? 'Overall'
                                      : names[p.budget.categoryId] ?? 'Category',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${formatEgp(p.spent)} / ${formatEgp(p.limitMinor)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            // The bar wears the category tone — color as
                            // data, same rotation the pie and swatches use.
                            child: LinearProgressIndicator(
                              value: p.ratio,
                              minHeight: 8,
                              color: categoryTone(
                                  p.budget.categoryId, theme.colorScheme),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              // Committed future spend: recurring rules glanceable beside the
              // budgets they feed. Section stays visible when empty so the
              // entry point never disappears.
              Row(
                children: [
                  const Expanded(child: RegistrationLabel('Recurring payments')),
                  TextButton(
                    onPressed: () => context.push('/recurring'),
                    child: const Text('Manage'),
                  ),
                ],
              ),
              if (recurrings == null || recurrings.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'No recurring payments yet.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...[
                const SizedBox(height: 4),
                for (final r in recurrings)
                  _RecurringStrip(rule: r, categoryName: names[r.categoryId]),
              ],
              if (data.recent.isNotEmpty) ...[
                RegistrationLabel('Recent expenses'),
                const SizedBox(height: 4),
                for (final (expense, category) in data.recent)
                  _RecentStrip(expense: expense, category: category),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.expense, required this.category});

  final ExpenseRow expense;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CategorySwatch(categoryId: expense.categoryId, size: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category ?? 'Uncategorized',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall),
                Text(_formatDay(expense.occurredAt),
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatEgp(expense.amountMinor), style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _RecurringStrip extends StatelessWidget {
  const _RecurringStrip({required this.rule, this.categoryName});

  final RecurringRow rule;
  final String? categoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cadence = switch (rule.frequency) {
      'daily' => rule.interval == 1 ? 'Daily' : 'Every ${rule.interval} days',
      'weekly' =>
        rule.interval == 1 ? 'Weekly' : 'Every ${rule.interval} weeks',
      _ => rule.interval == 1 ? 'Monthly' : 'Every ${rule.interval} months',
    };
    // Paused rules are not coming; the whole strip recedes.
    final tone = rule.paused
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;
    final subtitle = rule.paused
        ? 'Paused · $cadence'
        : '$cadence · next ${_formatDay(rule.nextRunAt)}';
    return Opacity(
      opacity: rule.paused ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CategorySwatch(categoryId: rule.categoryId, size: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: tone)),
                  Text(subtitle,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(formatEgp(rule.amountMinor),
                style: theme.textTheme.titleMedium?.copyWith(color: tone)),
          ],
        ),
      ),
    );
  }
}

class _DeltaLabel extends StatelessWidget {
  const _DeltaLabel({
    required this.current,
    required this.previous,
    this.color,
  });

  final int current;
  final int previous;

  /// Overrides the muted default when the label sits on the teal wall.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = color ?? scheme.onSurfaceVariant;
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
        Icon(icon, size: 16, color: tone),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: tone),
        ),
      ],
    );
  }
}
