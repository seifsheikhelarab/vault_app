import 'package:drift/drift.dart';

import '../../core/network/api_client.dart';
import '../db/vault_database.dart';

/// Thrown when a recurring-rule write is attempted while offline. Rules are
/// deliberately NOT part of /api/sync (contract §8), so there is no queue to
/// join — the write is refused and the user is told why.
class RecurringOfflineException implements Exception {
  const RecurringOfflineException();

  @override
  String toString() => 'RecurringOfflineException';
}

/// Read-cache + online-only CRUD proxy over `/api/recurring`. Reads always
/// hit the local table (stale-safe); writes require connectivity, mutate the
/// server first, then mirror into local rows. The server's cron materializes
/// occurrences — the client only displays rules and badges sourced expenses.
class RecurringRepository {
  RecurringRepository(this._db, this._api);

  final VaultDatabase _db;
  final ApiClient _api;

  Stream<List<RecurringRow>> watchAll() {
    return (_db.select(_db.recurrings)
          ..orderBy([
            (r) => OrderingTerm(expression: r.createdAt),
          ]))
        .watch();
  }

  /// Replaces the cache wholesale from the server list. Caller must check
  /// connectivity first; a failed call leaves the stale cache untouched.
  Future<void> refresh() async {
    final rows = await _api.listRecurring();
    await _db.transaction(() async {
      await _db.delete(_db.recurrings).go();
      for (final row in rows) {
        await _upsert(row);
      }
    });
  }

  Future<RecurringRow> create({
    required String name,
    required int amountMinor,
    required String frequency,
    required DateTime anchorDate,
    required bool online,
    int interval = 1,
    String? categoryId,
  }) async {
    if (!online) throw const RecurringOfflineException();
    final row = await _api.createRecurring(
      name: name,
      amountMinor: amountMinor,
      frequency: frequency,
      anchorDate: anchorDate,
      interval: interval,
      categoryId: categoryId,
    );
    await _upsert(row);
    return _fromApi(row);
  }

  Future<void> update(
    String id, {
    String? name,
    int? amountMinor,
    String? frequency,
    DateTime? anchorDate,
    int? interval,
    String? categoryId,
    bool? paused,
    required bool online,
  }) async {
    if (!online) throw const RecurringOfflineException();
    final row = await _api.updateRecurring(
      id,
      name: name,
      amountMinor: amountMinor,
      frequency: frequency,
      anchorDate: anchorDate,
      interval: interval,
      categoryId: categoryId,
      paused: paused,
    );
    await _upsert(row);
  }

  Future<void> delete(String id, {required bool online}) async {
    if (!online) throw const RecurringOfflineException();
    await _api.deleteRecurring(id);
    await (_db.delete(_db.recurrings)..where((r) => r.id.equals(id))).go();
  }

  Future<void> _upsert(Map<String, dynamic> json) {
    return _db.into(_db.recurrings).insertOnConflictUpdate(
          RecurringsCompanion.insert(
            id: json['id'] as String,
            name: json['name'] as String,
            amountMinor: (json['amountMinor'] as num).toInt(),
            categoryId: Value(json['categoryId'] as String?),
            frequency: json['frequency'] as String,
            interval: Value((json['interval'] as num?)?.toInt() ?? 1),
            anchorDate: DateTime.parse(json['anchorDate'] as String),
            nextRunAt: DateTime.parse(json['nextRunAt'] as String),
            paused: Value(json['paused'] as bool? ?? false),
            createdAt: DateTime.parse(json['createdAt'] as String),
          ),
        );
  }

  RecurringRow _fromApi(Map<String, dynamic> json) => RecurringRow(
        id: json['id'] as String,
        name: json['name'] as String,
        amountMinor: (json['amountMinor'] as num).toInt(),
        categoryId: json['categoryId'] as String?,
        frequency: json['frequency'] as String,
        interval: (json['interval'] as num?)?.toInt() ?? 1,
        anchorDate: DateTime.parse(json['anchorDate'] as String),
        nextRunAt: DateTime.parse(json['nextRunAt'] as String),
        paused: json['paused'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}
