import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/vault_database.dart';
import '../../data/providers.dart';
import 'connectivity_provider.dart';

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
  final now = DateTime.now();
  final start = DateTime(now.year, now.month);
  final end = DateTime(now.year, now.month + 1);
  return repo.watchSpendBetween(start, end);
});

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
  final spend = ref.watch(monthSpendProvider).value ?? const {};
  return [
    for (final b in budgets)
      BudgetProgress(
        budget: b,
        spent: b.categoryId == null
            ? spend.values.fold(0, (a, v) => a + v)
            : spend[b.categoryId] ?? 0,
      ),
  ];
});

/// One-line online read for gating UI and writes.
final isOnlineProvider = Provider.autoDispose<bool>(
    (ref) => isOnline(ref.watch(connectivityProvider)));
