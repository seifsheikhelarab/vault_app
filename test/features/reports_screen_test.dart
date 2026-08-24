import 'package:drift/native.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
import 'package:vault_app/data/repositories/categories_repository.dart';
import 'package:vault_app/data/repositories/expenses_repository.dart';
import 'package:vault_app/features/reports/reports_screen.dart';

/// Unmounts while still inside the test's fake-async zone, then pumps once
/// so drift's internal stream-cleanup timers fire before the framework's
/// no-pending-timers invariant check. Must be awaited at the END of every
/// test body — an addTearDown-based version runs outside the fake-async
/// zone and leaves the timer pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpReports(WidgetTester tester, VaultDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [vaultDatabaseProvider.overrideWithValue(AsyncValue.data(db))],
      child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late VaultDatabase db;
  late CategoriesRepository categories;
  late ExpensesRepository expenses;

  setUp(() {
    db = VaultDatabase(NativeDatabase.memory());
    categories = CategoriesRepository(db);
    expenses = ExpensesRepository(db);
  });
  tearDown(() => db.close());

  group('reports screen', () {
    testWidgets('empty window shows empty state for both toggles',
        (tester) async {
      await _pumpReports(tester, db);

      expect(find.text('No spending this week'), findsOneWidget);

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.text('No spending this month'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('pie legend breaks spend down by category and uncategorized',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final food = await categories.create('Food');
      await expenses.create(
          amountMinor: 2500,
          occurredAt: today.add(const Duration(hours: 2)),
          categoryId: food.id);
      await expenses.create(amountMinor: 1000, occurredAt: today);
      // Outside both windows: must not appear anywhere.
      await expenses.create(
        amountMinor: 9900,
        occurredAt: DateTime(now.year, now.month - 1, 15),
        categoryId: food.id,
      );

      await _pumpReports(tester, db);

      expect(find.text('Food'), findsOneWidget);
      // Second legend row sits below the fold of the lazy ListView.
      for (var i = 0;
          i < 5 && find.text('Uncategorized').evaluate().isEmpty;
          i++) {
        await tester.drag(find.byType(ListView).first, const Offset(0, -200));
        await tester.pumpAndSettle();
      }
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(find.text('EGP 25.00'), findsOneWidget);
      expect(find.text('EGP 10.00'), findsOneWidget);
      expect(find.text('EGP 99.00'), findsNothing);

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('EGP 25.00'), findsOneWidget);
      expect(find.text('EGP 99.00'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('trend line renders daily points without crashing',
        (tester) async {
      final now = DateTime.now();
      final monday = DateTime(
          now.year, now.month, now.day - (now.weekday - DateTime.monday));
      await expenses.create(
        amountMinor: 5000,
        occurredAt: monday.add(const Duration(hours: 10)),
      );
      await expenses.create(
        amountMinor: 2000,
        occurredAt: monday.add(const Duration(days: 2, hours: 10)),
      );
      await expenses.create(
        amountMinor: 1000,
        occurredAt: monday.add(const Duration(days: 2, hours: 12)),
      );

      await _pumpReports(tester, db);

      expect(find.text('Daily trend'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);

      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();

      expect(find.byType(LineChart), findsOneWidget);
      await _unmount(tester);
    });
  });
}
