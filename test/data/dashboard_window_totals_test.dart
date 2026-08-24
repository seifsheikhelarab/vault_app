import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/repositories/expenses_repository.dart';

void main() {
  late VaultDatabase db;
  late ExpensesRepository expenses;

  setUp(() {
    db = VaultDatabase(NativeDatabase.memory());
    expenses = ExpensesRepository(db);
  });

  tearDown(() => db.close());

  // Same window math as DashboardScreen's provider (local time, month =
  // calendar month, week = Monday-anchored).
  DateTime monthStart(DateTime now) => DateTime(now.year, now.month);
  DateTime monthEnd(DateTime now) => DateTime(now.year, now.month + 1);
  DateTime prevMonthStart(DateTime now) => DateTime(now.year, now.month - 1);
  DateTime weekStart(DateTime now) =>
      DateTime(now.year, now.month, now.day - (now.weekday - DateTime.monday));
  DateTime weekEnd(DateTime now) =>
      DateTime(now.year, now.month, now.day + 7 - (now.weekday - 1));
  DateTime prevWeekStart(DateTime now) =>
      weekStart(now).subtract(const Duration(days: 7));

  /// Dart-side classification of a half-open pair of windows; independent
  /// reimplementation of the SQL so agreement proves the query.
  ({int previous, int current}) expected(
    Iterable<ExpenseRow> rows, {
    required DateTime prevStart,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    var current = 0;
    var previous = 0;
    for (final row in rows) {
      final t = row.occurredAt;
      if (!t.isBefore(windowStart) && t.isBefore(windowEnd)) {
        current += row.amountMinor;
      } else if (!t.isBefore(prevStart) && t.isBefore(windowStart)) {
        previous += row.amountMinor;
      }
    }
    return (previous: previous, current: current);
  }

  test('watchWindowTotals respects month and week boundaries', () async {
    final now = DateTime.now();

    // Boundary seeds — each lands on an edge the half-open windows must
    // classify exactly once.
    final seeds = <String, (DateTime, int)>{
      // Exactly at the lower bound: counts in CURRENT, not previous.
      'first-of-month': (monthStart(now), 20000),
      'last-day-of-prev-month': (
        DateTime(now.year, now.month, 0), // midnight of prev month last day
        10000,
      ),
      // Exactly at the upper bound: excluded from BOTH windows.
      'first-of-next-month': (monthEnd(now), 30000),
      // Exactly at prev lower bound: counts in PREVIOUS.
      'first-of-prev-month': (prevMonthStart(now), 40000),
      // Week anchor edges.
      'sunday-before-this-week': (weekStart(now).subtract(const Duration(days: 1)), 5000),
      'monday-this-week': (weekStart(now), 7000),
      'next-monday': (weekEnd(now), 11000),
      'sunday-last-week': (prevWeekStart(now).add(const Duration(hours: 12)), 13000),
      // Older than both previous windows: excluded everywhere.
      'two-months-ago': (DateTime(now.year, now.month - 2, 15), 170000),
    };
    for (final entry in seeds.entries) {
      await expenses.create(
        amountMinor: entry.value.$2,
        occurredAt: entry.value.$1,
        note: entry.key,
      );
    }
    final rows = await db.select(db.expenses).get();
    expect(rows, hasLength(seeds.length));

    final monthTotals = await expenses.watchWindowTotals(
      prevStart: prevMonthStart(now),
      windowStart: monthStart(now),
      windowEnd: monthEnd(now),
    ).first;
    expect(
      monthTotals,
      expected(rows,
          prevStart: prevMonthStart(now),
          windowStart: monthStart(now),
          windowEnd: monthEnd(now)),
      reason: 'month cur/prev must match Dart-side classification',
    );

    final weekTotals = await expenses.watchWindowTotals(
      prevStart: prevWeekStart(now),
      windowStart: weekStart(now),
      windowEnd: weekEnd(now),
    ).first;
    expect(
      weekTotals,
      expected(rows,
          prevStart: prevWeekStart(now),
          windowStart: weekStart(now),
          windowEnd: weekEnd(now)),
      reason: 'week cur/prev must match Dart-side classification',
    );

    // Hard expectations beyond the classifier: excluded rows never leak
    // into any emitted figure.
    final allEmitted = {
      monthTotals.current,
      monthTotals.previous,
      weekTotals.current,
      weekTotals.previous,
    };
    expect(allEmitted.any((sum) => sum >= 170000), isFalse,
        reason: 'two-months-ago row must be excluded from every window');
  });

  test('empty ledger emits zero totals for both windows', () async {
    final now = DateTime.now();
    final monthTotals = await expenses.watchWindowTotals(
      prevStart: prevMonthStart(now),
      windowStart: monthStart(now),
      windowEnd: monthEnd(now),
    ).first;
    expect(monthTotals.current, 0);
    expect(monthTotals.previous, 0);

    final weekTotals = await expenses.watchWindowTotals(
      prevStart: prevWeekStart(now),
      windowStart: weekStart(now),
      windowEnd: weekEnd(now),
    ).first;
    expect(weekTotals.current, 0);
    expect(weekTotals.previous, 0);
  });

  test('totals stream re-emits when an expense lands inside the window',
      () async {
    final now = DateTime.now();
    final stream = expenses.watchWindowTotals(
      prevStart: prevMonthStart(now),
      windowStart: monthStart(now),
      windowEnd: monthEnd(now),
    );

    expect(await stream.first, (previous: 0, current: 0));

    await expenses.create(
      amountMinor: 2500,
      occurredAt: now,
    );
    final after = await stream.first;
    expect(after.current, 2500);
    expect(after.previous, 0);
  });
}
