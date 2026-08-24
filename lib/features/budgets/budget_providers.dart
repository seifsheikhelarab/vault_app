import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity_provider.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Cached budget rows, streamed from the local table.
final budgetsListProvider = StreamProvider.autoDispose<List<BudgetRow>>((ref) {
  final repo = ref.watch(budgetsRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchAll();
});

/// Spend per category for the calendar month containing "now" (local device
/// time — the contract's Africa/Cairo default; device tz is the honest
/// approximation available offline).
final monthSpendProvider = StreamProvider.autoDispose<Map<String?, int>>((ref) {
  final repo = ref.watch(expensesRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchSpendBetween(monthWindow().$1, monthWindow().$2);
});

/// Spend per category for the Monday-anchored week containing "now",
/// matching how the dashboard and reports define a week.
final weekSpendProvider = StreamProvider.autoDispose<Map<String?, int>>((ref) {
  final repo = ref.watch(expensesRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchSpendBetween(weekWindow().$1, weekWindow().$2);
});

/// Half-open (start, end) calendar-month window containing now.
(DateTime, DateTime) monthWindow() {
  final now = DateTime.now();
  return (
    DateTime(now.year, now.month),
    DateTime(now.year, now.month + 1),
  );
}

/// Half-open Monday-anchored week window containing now.
(DateTime, DateTime) weekWindow() {
  final today = DateTime.now();
  final date = DateTime(today.year, today.month, today.day);
  final daysFromMonday = date.weekday - DateTime.monday;
  final start = date.subtract(Duration(days: daysFromMonday));
  return (start, start.add(const Duration(days: 7)));
}

class BudgetProgress {
  const BudgetProgress({required this.budget, required this.spent});

  final BudgetRow budget;

  /// Overall budgets (`categoryId == null`) sum every expense in the window,
  /// matching the server's progress semantics; category budgets sum only
  /// that category's live expenses this month.
  final int spent;

  int get limitMinor => budget.amountMinor;

  double get ratio =>
      limitMinor <= 0 ? 0 : (spent / limitMinor).clamp(0.0, 1.0);

  bool get over => spent > limitMinor;
}

final budgetProgressProvider =
    Provider.autoDispose<List<BudgetProgress>>((ref) {
  final budgets = ref.watch(budgetsListProvider).value ?? const [];
  final monthSpend = ref.watch(monthSpendProvider).value ?? const {};
  final weekSpend = ref.watch(weekSpendProvider).value ?? const {};
  Map<String?, int> spendFor(BudgetRow b) =>
      b.periodType == 'week' ? weekSpend : monthSpend;
  return [
    for (final b in budgets)
      BudgetProgress(
        budget: b,
        spent: b.categoryId == null
            ? spendFor(b).values.fold(0, (a, v) => a + v)
            : spendFor(b)[b.categoryId] ?? 0,
      ),
  ];
});

/// One-line online read for gating UI and writes.
final isOnlineProvider =
    Provider.autoDispose<bool>((ref) => isOnline(ref.watch(connectivityProvider)));
