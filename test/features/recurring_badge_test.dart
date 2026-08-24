import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
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

void main() {
  late VaultDatabase db;

  setUp(() {
    db = VaultDatabase(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> seedExpense({
    required String id,
    required int amountMinor,
    required DateTime occurredAt,
    String? recurringId,
  }) =>
      db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: id,
              amountMinor: amountMinor,
              occurredAt: occurredAt,
              recurringId: Value(recurringId),
            ),
          );

  testWidgets('recurring-sourced expenses show the badge, manual ones do not',
      (tester) async {
    final now = DateTime.now();
    await seedExpense(
      id: 'synced-rule',
      amountMinor: 75000,
      occurredAt: now,
      recurringId: 'rule-1',
    );
    await seedExpense(
      id: 'manual',
      amountMinor: 2500,
      occurredAt: now.subtract(const Duration(minutes: 5)),
    );

    await _pumpScreen(tester, db);

    expect(find.text('EGP 750.00'), findsOneWidget);
    expect(find.byIcon(Icons.autorenew), findsOneWidget);

    // Badge belongs to the rule-sourced row, not its day section neighbor.
    final badgedTile =
        tester.widget<ListTile>(find.ancestor(
      of: find.byIcon(Icons.autorenew),
      matching: find.byType(ListTile),
    ));
    expect((badgedTile.title! as Row).children.first.runtimeType, Flexible);

    // Tooltip carries the plain-language explanation.
    expect(find.byTooltip('Logged by a recurring rule'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('badge count follows the number of rule-sourced rows',
      (tester) async {
    final now = DateTime.now();
    await seedExpense(
      id: 'a',
      amountMinor: 100,
      occurredAt: now,
      recurringId: 'rule-1',
    );
    await seedExpense(
      id: 'b',
      amountMinor: 200,
      occurredAt: now.subtract(const Duration(minutes: 1)),
      recurringId: 'rule-2',
    );
    await seedExpense(
      id: 'c',
      amountMinor: 300,
      occurredAt: now.subtract(const Duration(minutes: 2)),
    );

    await _pumpScreen(tester, db);

    expect(find.byIcon(Icons.autorenew), findsNWidgets(2));
    await _unmount(tester);
  });
}
