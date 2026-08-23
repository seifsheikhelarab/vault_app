import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/vault_database.dart';

/// Expenses are fully offline-writable. Every create mints a client UUID and
/// sets `pendingSync` so the sync engine can push it later; rows are
/// immediately visible to local queries.
class ExpensesRepository {
  ExpensesRepository(this._db);

  final VaultDatabase _db;

  Future<ExpenseRow> create({
    required int amountMinor,
    String? categoryId,
    required DateTime occurredAt,
    String? note,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            amountMinor: amountMinor,
            categoryId: Value(categoryId),
            occurredAt: occurredAt,
            note: Value(note),
            pendingSync: const Value(true),
            recurringId: const Value(null),
          ),
        );
    return (_db.select(_db.expenses)..where((e) => e.id.equals(id)))
        .getSingle();
  }

  /// Inserts a row the server already holds under [id] (chat confirm flow:
  /// POST succeeds, then local insert). `pendingSync` stays false so the
  /// sync engine never re-pushes it.
  Future<void> createSynced({
    required String id,
    required int amountMinor,
    String? categoryId,
    required DateTime occurredAt,
    String? note,
  }) {
    return _db.into(_db.expenses).insert(
          ExpensesCompanion.insert(
            id: id,
            amountMinor: amountMinor,
            categoryId: Value(categoryId),
            occurredAt: occurredAt,
            note: Value(note),
            recurringId: const Value(null),
          ),
        );
  }

  /// Newest-first page for purely-local infinite scroll. `limit` grows as
  /// the user scrolls; the stream re-emits on any local mutation.
  Stream<List<ExpenseRow>> watchPage({
    String? categoryId,
    required int limit,
  }) {
    final query = _db.select(_db.expenses);
    if (categoryId != null) {
      query.where((e) => e.categoryId.equals(categoryId));
    }
    return (query
              ..orderBy([
                (e) => OrderingTerm(expression: e.occurredAt, mode: OrderingMode.desc),
                (e) => OrderingTerm(expression: e.createdAt, mode: OrderingMode.desc),
                (e) => OrderingTerm(expression: e.id, mode: OrderingMode.desc),
              ])
              ..limit(limit))
        .watch();
  }

  /// Newest-first page joined with category names (`null` when uncategorized
  /// or the category was deleted). Feeds the dashboard recent list.
  Stream<List<(ExpenseRow, String?)>> watchRecentWithCategory({
    required int limit,
  }) {
    final query = _db.select(_db.expenses).join([
      leftOuterJoin(
          _db.categories, _db.categories.id.equalsExp(_db.expenses.categoryId)),
    ]);
    return (query
              ..orderBy([
                OrderingTerm(
                    expression: _db.expenses.occurredAt,
                    mode: OrderingMode.desc),
                OrderingTerm(
                    expression: _db.expenses.createdAt,
                    mode: OrderingMode.desc),
                OrderingTerm(
                    expression: _db.expenses.id, mode: OrderingMode.desc),
              ])
              ..limit(limit))
        .watch()
        .map(
          (rows) => rows
              .map((row) => (
                    row.readTable(_db.expenses),
                    row.readTableOrNull(_db.categories)?.name,
                  ))
              .toList(),
        );
  }

  /// Live expense sums (piasters) over two adjacent half-open windows:
  /// `[prevStart, windowStart)` and `[windowStart, windowEnd)`. One reactive
  /// row keeps both figures consistent with each other.
  Stream<({int previous, int current})> watchWindowTotals({
    required DateTime prevStart,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final query = _db.customSelect(
      'SELECT '
      'COALESCE(SUM(CASE WHEN occurred_at >= ? AND occurred_at < ? '
      'THEN amount_minor END), 0) AS cur, '
      'COALESCE(SUM(CASE WHEN occurred_at >= ? AND occurred_at < ? '
      'THEN amount_minor END), 0) AS prev '
      'FROM expenses',
      variables: [
        Variable.withDateTime(windowStart),
        Variable.withDateTime(windowEnd),
        Variable.withDateTime(prevStart),
        Variable.withDateTime(windowStart),
      ],
      readsFrom: {_db.expenses},
    );
    return query.watchSingle().map(
          (row) => (
            previous: row.read<int>('prev'),
            current: row.read<int>('cur'),
          ),
        );
  }

  /// Count of live rows, used to stop infinite scroll growth.
  Stream<int> watchCount({String? categoryId}) {
    final count = _db.expenses.id.count();
    final query = _db.selectOnly(_db.expenses)..addColumns([count]);
    if (categoryId != null) {
      query.where(_db.expenses.categoryId.equals(categoryId));
    }
    return query.map((row) => row.read(count) ?? 0).watchSingle();
  }

  /// Live spend totals within the half-open window `[start, end)`, grouped
  /// by categoryId (null key = uncategorized). Feeds budget progress bars;
  /// overall budgets sum every value in the map.
  Stream<Map<String?, int>> watchSpendBetween(DateTime start, DateTime end) {
    final total = _db.expenses.amountMinor.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([_db.expenses.categoryId, total])
      ..where(_db.expenses.occurredAt.isBiggerOrEqualValue(start) &
          _db.expenses.occurredAt.isSmallerThanValue(end));
    return query.watch().map((rows) => {
          for (final row in rows)
            row.read(_db.expenses.categoryId): row.read(total) ?? 0,
        });
  }
}
