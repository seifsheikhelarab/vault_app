import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
import 'package:vault_app/data/repositories/categories_repository.dart';
import 'package:vault_app/features/expenses/capture_fab.dart';

/// Unmounts while still inside the test's fake-async zone, then pumps once
/// so drift's internal stream-cleanup timers fire before the framework's
/// no-pending-timers invariant check. Registered by every harness below.
void _flushTreeOnTearDown(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });
}

Future<void> _pumpHarness(WidgetTester tester, VaultDatabase db) async {
  _flushTreeOnTearDown(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [vaultDatabaseProvider.overrideWithValue(AsyncValue.data(db))],
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox.shrink(),
          floatingActionButton: CaptureFab(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _amountField => find.widgetWithText(TextFormField, 'Amount').first;

void main() {
  late VaultDatabase db;

  setUp(() => db = VaultDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('capture flow', () {
    testWidgets('ember FAB opens the log-an-expense sheet', (tester) async {
      await _pumpHarness(tester, db);

      expect(find.text('Log an expense'), findsNothing);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Log an expense'), findsOneWidget);
      expect(_amountField, findsOneWidget);
      expect(find.text('Uncategorized'), findsOneWidget);
      expect(
          find.widgetWithText(FilledButton, 'Save expense'), findsOneWidget);
    });

    testWidgets('decimal keypad rejects a third decimal place',
        (tester) async {
      await _pumpHarness(tester, db);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(_amountField, '12.345');
      expect(tester.widget<TextFormField>(_amountField).controller!.text, '');

      await tester.enterText(_amountField, '12.34');
      expect(tester.widget<TextFormField>(_amountField).controller!.text,
          '12.34');

      await tester.enterText(_amountField, '1.2.3');
      expect(tester.widget<TextFormField>(_amountField).controller!.text,
          '12.34');
    });

    testWidgets('empty amount shows inline error and writes nothing',
        (tester) async {
      await _pumpHarness(tester, db);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save expense'));
      await tester.pump();

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(await db.select(db.expenses).get(), isEmpty);
    });

    testWidgets('saving offline writes UUID row with pendingSync flag',
        (tester) async {
      final food = await CategoriesRepository(db).create('Food');
      await _pumpHarness(tester, db);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(_amountField, '49.99');
      await tester.tap(find.text('Food'));
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Note (optional)'), 'lunch out');
      await tester.tap(find.widgetWithText(FilledButton, 'Save expense'));
      // Fixed pumps: the status snackbar owns a real dismiss timer that
      // pumpAndSettle would wait on forever.
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.amountMinor, 4999);
      expect(row.categoryId, food.id);
      expect(row.note, 'lunch out');
      expect(row.pendingSync, true);
      expect(
        row.id,
        matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')),
      );

      // Sheet closed, gentle status shown.
      expect(find.text('Log an expense'), findsNothing);
      expect(find.textContaining('sync when online'), findsOneWidget);
    });

    testWidgets('capture works without any categories yet', (tester) async {
      await _pumpHarness(tester, db);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.enterText(_amountField, '20');
      await tester
          .tap(find.widgetWithText(FilledButton, 'Save expense'));
      await tester.pumpAndSettle();

      final rows = await db.select(db.expenses).get();
      expect(rows, hasLength(1));
      expect(rows.single.categoryId, isNull);
      expect(rows.single.amountMinor, 2000);
    });
  });
}
