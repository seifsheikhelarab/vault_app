import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
import 'package:vault_app/data/repositories/categories_repository.dart';
import 'package:vault_app/data/repositories/expenses_repository.dart';
import 'package:vault_app/features/expenses/expenses_screen.dart';

/// Unmounts while still inside the test's fake-async zone, then pumps once
/// so drift's internal stream-cleanup timers fire before the framework's
/// no-pending-timers invariant check. Must be awaited at the END of every
/// test body — an addTearDown-based version runs outside the fake-async
/// zone and leaves the timer pending.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _pumpScreen(WidgetTester tester, VaultDatabase db) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [vaultDatabaseProvider.overrideWithValue(AsyncValue.data(db))],
      child: const MaterialApp(home: Scaffold(body: ExpensesScreen())),
    ),
  );
  await tester.pumpAndSettle();
}

final _olderHeaderFinder =
    find.textContaining(RegExp(r'^\w{3}, \d{1,2} \w{3}$'));

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

  group('expenses list', () {
    testWidgets('groups by day newest-first with correct daily totals',
        (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 12);
      final yesterday = today.subtract(const Duration(days: 1));
      final threeDaysAgo = today.subtract(const Duration(days: 3));

      await expenses.create(
          amountMinor: 2500,
          occurredAt: today.add(const Duration(hours: 2)),
          note: 'coffee');
      await expenses.create(
          amountMinor: 10000, occurredAt: today, note: 'lunch');
      await expenses.create(
          amountMinor: 5000, occurredAt: yesterday, note: 'metro card');
      await expenses.create(
          amountMinor: 12550, occurredAt: threeDaysAgo, note: 'taxi');

      await _pumpScreen(tester, db);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(_olderHeaderFinder, findsOneWidget);
      expect(find.text('EGP 125.00'), findsOneWidget); // coffee + lunch
      // Tile trailing amount and day-total header coincide when a day has
      // exactly one expense.
      expect(find.text('EGP 50.00'), findsNWidgets(2));
      expect(find.text('EGP 125.50'), findsNWidgets(2)); // taxi

      // Newest-first ordering of the day headers.
      expect(tester.getTopLeft(find.text('Today')).dy,
          lessThan(tester.getTopLeft(find.text('Yesterday')).dy));
      expect(tester.getTopLeft(find.text('Yesterday')).dy,
          lessThan(tester.getTopLeft(_olderHeaderFinder).dy));
      await _unmount(tester);
  });

    testWidgets('category chips filter the list via local query',
        (tester) async {
      final food = await categories.create('Food');
      final bills = await categories.create('Bills');
      final now = DateTime.now();
      await expenses.create(
          amountMinor: 10000,
          occurredAt: now,
          categoryId: food.id,
          note: 'groceries');
      await expenses.create(
          amountMinor: 30000,
          occurredAt: now.subtract(const Duration(hours: 1)),
          categoryId: bills.id,
          note: 'electricity');

      await _pumpScreen(tester, db);

      expect(find.text('groceries'), findsOneWidget);
      expect(find.text('electricity'), findsOneWidget);

      // Scope to the filter chip: the expense tile subtitle says 'Bills' too.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bills'));
      await tester.pumpAndSettle();

      expect(find.text('electricity'), findsOneWidget);
      expect(find.text('groceries'), findsNothing);
      // Single-expense day: tile amount equals the day total.
      expect(find.text('EGP 300.00'), findsNWidgets(2));

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('groceries'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('empty history keeps the honest empty state',
        (tester) async {
      await _pumpScreen(tester, db);
      expect(find.text('Nothing logged yet'), findsOneWidget);

      // A filtered-but-empty list says so instead.
      await categories.create('Food');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Food'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing in this category'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('infinite scroll grows the purely-local page',
        (tester) async {
      final base = DateTime.now();
      var totalMinor = 0;
      for (var i = 0; i < 45; i++) {
        totalMinor += (i + 1) * 100;
        await expenses.create(
          amountMinor: (i + 1) * 100,
          occurredAt: base.subtract(Duration(minutes: i)),
          note: 'n$i',
        );
      }

      await _pumpScreen(tester, db);

      // First page only (30).
      expect(find.text('n29'), findsOneWidget);
      expect(find.text('n44'), findsNothing);

      for (var drag = 0;
          drag < 6 && find.text('n44').evaluate().isEmpty;
          drag++) {
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
      }

      expect(find.text('n44'), findsOneWidget);
      // Daily total covers every loaded row of the day.
      expect(find.text('EGP ${(totalMinor / 100).toStringAsFixed(2)}'),
          findsOneWidget);
      await _unmount(tester);
    });
  });
}
