import 'package:drift/drift.dart';

import '../../core/network/api_client.dart';
import '../db/vault_database.dart';

/// Thrown when a budget write is attempted while offline. Budgets are
/// deliberately NOT part of /api/sync (contract §7), so there is no queue to
/// join — the write is refused and the user is told why.
class BudgetOfflineException implements Exception {
  const BudgetOfflineException();

  @override
  String toString() => 'BudgetOfflineException';
}

/// Read-cache + online-only CRUD proxy over `/api/budgets`. Reads always hit
/// the local table (stale-safe); writes require connectivity, mutate the
/// server first, then mirror into local rows.
class BudgetsRepository {
  BudgetsRepository(this._db, this._api);

  final VaultDatabase _db;
  final ApiClient _api;

  Stream<List<BudgetRow>> watchAll() {
    return (_db.select(_db.budgets)
          ..orderBy([
            (b) => OrderingTerm(expression: b.createdAt),
          ]))
        .watch();
  }

  /// Replaces the cache wholesale from the server list. Caller must check
  /// connectivity first; a failed call leaves the stale cache untouched.
  Future<void> refresh() async {
    final rows = await _api.listBudgets();
    await _db.transaction(() async {
      await _db.delete(_db.budgets).go();
      for (final row in rows) {
        await _upsert(row);
      }
    });
  }

  Future<BudgetRow> create({
    required String periodType,
    required int amountMinor,
    required bool online,
    String? categoryId,
  }) async {
    if (!online) throw const BudgetOfflineException();
    final row = await _api.createBudget(
      periodType: periodType,
      amountMinor: amountMinor,
      categoryId: categoryId,
    );
    await _upsert(row);
    return _fromApi(row);
  }

  Future<void> update(
    String id, {
    required String periodType,
    required int amountMinor,
    required bool online,
    String? categoryId,
  }) async {
    if (!online) throw const BudgetOfflineException();
    final row = await _api.updateBudget(
      id,
      periodType: periodType,
      amountMinor: amountMinor,
      categoryId: categoryId,
    );
    await _upsert(row);
  }

  Future<void> delete(String id, {required bool online}) async {
    if (!online) throw const BudgetOfflineException();
    await _api.deleteBudget(id);
    await (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
  }

  Future<void> _upsert(Map<String, dynamic> json) {
    return _db.into(_db.budgets).insertOnConflictUpdate(
          BudgetsCompanion.insert(
            id: json['id'] as String,
            periodType: json['periodType'] as String,
            amountMinor: (json['amountMinor'] as num).toInt(),
            categoryId: Value(json['categoryId'] as String?),
            createdAt: DateTime.parse(json['createdAt'] as String),
          ),
        );
  }

  BudgetRow _fromApi(Map<String, dynamic> json) => BudgetRow(
        id: json['id'] as String,
        periodType: json['periodType'] as String,
        amountMinor: (json['amountMinor'] as num).toInt(),
        categoryId: json['categoryId'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
