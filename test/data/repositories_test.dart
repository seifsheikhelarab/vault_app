import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/repositories/categories_repository.dart';
import 'package:vault_app/data/repositories/expenses_repository.dart';

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

  Future<CategoryRow> seedCategory(String name) => categories.create(name);

  Future<ExpenseRow> seedExpense({
    required int amountMinor,
    required DateTime occurredAt,
    CategoryRow? category,
    String? note,
  }) =>
      expenses.create(
        amountMinor: amountMinor,
        categoryId: category?.id,
        occurredAt: occurredAt,
        note: note,
      );

  group('expenses repository', () {
    test('create mints UUID, stores integer piasters, sets pendingSync',
        () async {
      final food = await seedCategory('Food');
      final row = await seedExpense(
        amountMinor: 12550,
        occurredAt: DateTime.now(),
        category: food,
        note: 'lunch',
      );

      expect(row.id, matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')));
      expect(row.amountMinor, 12550);
      expect(row.categoryId, food.id);
      expect(row.pendingSync, true);
      expect(row.recurringId, isNull);
    });

    test('watchPage orders newest first with stable tiebreak', () async {
      final base = DateTime.now();
      final older = await seedExpense(amountMinor: 100, occurredAt: base.subtract(const Duration(days: 2)));
      final newer = await seedExpense(amountMinor: 200, occurredAt: base.add(const Duration(days: 1)));
      // Same instant: insertion order must not decide.
      final tieA = await seedExpense(amountMinor: 300, occurredAt: base);
      final tieB = await seedExpense(amountMinor: 400, occurredAt: base);

      final page = await expenses.watchPage(limit: 10).first;

      // Ties break on id DESC — deterministic, but the ids are random, so
      // only assert both ties sit between `newer` and `older`.
      expect(page[0].id, newer.id);
      expect({page[1].id, page[2].id}, {tieA.id, tieB.id});
      expect(page[3].id, older.id);
    });

    test('watchPage filters by category via local SQL', () async {
      final food = await seedCategory('Food');
      final bills = await seedCategory('Bills');
      final inFood = await seedExpense(amountMinor: 100, occurredAt: DateTime.now(), category: food);
      await seedExpense(amountMinor: 200, occurredAt: DateTime.now(), category: bills);
      final uncategorized = await seedExpense(amountMinor: 300, occurredAt: DateTime.now());

      final foodRows = await expenses.watchPage(categoryId: food.id, limit: 10).first;
      expect(foodRows.map((e) => e.id), [inFood.id]);

      final allRows = await expenses.watchPage(limit: 10).first;
      expect(allRows.length, 3);
      expect(allRows.map((e) => e.id), contains(uncategorized.id));
    });

    test('watchPage limit truncates and count stream reports totals', () async {
      for (var i = 0; i < 5; i++) {
        await seedExpense(amountMinor: i * 100, occurredAt: DateTime.now().subtract(Duration(minutes: i)));
      }

      final page1 = await expenses.watchPage(limit: 2).first;
      expect(page1, hasLength(2));

      expect(await expenses.watchCount().first, 5);
    });

    test('category delete nulls referencing expenses, keeps rows intact',
        () async {
      final food = await seedCategory('Food');
      final kept = await seedExpense(amountMinor: 500, occurredAt: DateTime.now(), category: food);
      final untouched = await seedExpense(amountMinor: 700, occurredAt: DateTime.now());

      await categories.delete(food.id);

      final after = await (db.select(db.expenses)..where((e) => e.id.isIn([kept.id, untouched.id]))).get();
      final keptRow = after.singleWhere((e) => e.id == kept.id);
      final untouchedRow = after.singleWhere((e) => e.id == untouched.id);
      expect(keptRow.categoryId, isNull);
      expect(keptRow.amountMinor, 500);
      expect(keptRow.pendingSync, true, reason: 'nulled reference must resync');
      expect(untouchedRow.categoryId, isNull);
      expect(await (db.select(db.categories)).get(), isEmpty);
    });
  });

  group('categories repository', () {
    test('create trims and rejects empty/oversized names', () async {
      final row = await categories.create('  Food  ');
      expect(row.name, 'Food');

      expect(() => categories.create('   '), throwsFormatException);
      expect(() => categories.create('x' * 101), throwsFormatException);
    });

    test('duplicate names rejected case-insensitively, rename allowed to self', () async {
      await categories.create('Food');
      expect(() => categories.create('FOOD'), throwsA(isA<DuplicateCategoryException>()));
      expect(() => categories.create('food'), throwsA(isA<DuplicateCategoryException>()));

      final other = await categories.create('Bills');

      await categories.rename(other.id, 'bills'); // rename onto itself ok
      await expectLater(categories.watchAll().first, completion(hasLength(2)));
      expect(() => categories.rename(other.id, 'Food'), throwsA(isA<DuplicateCategoryException>()));
    });

    test('rename persists', () async {
      final row = await categories.create('Food');
      await categories.rename(row.id, 'Groceries');

      final stored = await (db.select(db.categories)..where((c) => c.id.equals(row.id))).getSingle();
      expect(stored.name, 'Groceries');
    });

    test('watchAll emits updates on mutation', () async {
      final first = await categories.watchAll().first;
      expect(first, isEmpty);

      await categories.create('Food');
      final next = await categories.watchAll().first;
      expect(next.map((c) => c.name), ['Food']);
    });

    test('delete removes only the target category', () async {
      final food = await categories.create('Food');
      await categories.create('Bills');

      await categories.delete(food.id);

      final left = await (db.select(db.categories)).get();
      expect(left.map((c) => c.name), ['Bills']);
    });
  });
}
