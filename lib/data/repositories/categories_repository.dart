import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/vault_database.dart';

/// Thrown when a category name collides (case-insensitive) with an existing
/// one — mirrors the server's 409 on duplicate names.
class DuplicateCategoryException implements Exception {
  const DuplicateCategoryException(this.name);

  final String name;

  @override
  String toString() => 'DuplicateCategoryException: $name';
}

const _maxNameLength = 100;

void _validateName(String raw) {
  if (raw.isEmpty) {
    throw const FormatException('Enter a name');
  }
  if (raw.length > _maxNameLength) {
    throw const FormatException('Use at most 100 characters');
  }
}

/// Categories are fully offline-writable. Writes stage as dirty rows
/// (`pendingSync`) for the sync engine; deleting one nulls the `categoryId`
/// of referencing expenses immediately and stages a tombstone row — the
/// local row disappears only after the server accepts the delete push
/// (categories hard-delete server-side, so there is no pull tombstone).
class CategoriesRepository {
  CategoriesRepository(this._db);

  final VaultDatabase _db;

  /// Fired after any local write so the sync engine can schedule a debounced
  /// cycle. Wired by `syncSchedulerProvider`; nullable to keep plain-DB tests
  /// friction-free.
  void Function()? onMutated;

  Stream<List<CategoryRow>> watchAll() {
    return (_db.select(_db.categories)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([
            (c) => OrderingTerm(expression: c.name.lower()),
          ]))
        .watch();
  }

  Future<CategoryRow> create(String rawName) async {
    final name = rawName.trim();
    _validateName(name);
    await _guardDuplicate(name);
    final id = const Uuid().v4();
    await _db.into(_db.categories).insert(
          CategoriesCompanion.insert(
            id: id,
            name: name,
            updatedAt: Value(DateTime.now()),
            pendingSync: const Value(true),
          ),
        );
    onMutated?.call();
    return (_db.select(_db.categories)..where((c) => c.id.equals(id)))
        .getSingle();
  }

  Future<void> rename(String id, String rawName) async {
    final name = rawName.trim();
    _validateName(name);
    await _guardDuplicate(name, excludingId: id);
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(
      name: Value(name),
      updatedAt: Value(DateTime.now()),
      pendingSync: const Value(true),
    ));
    onMutated?.call();
  }

  /// Stages the deletion: the category vanishes from live queries and its
  /// references are nulled now; the row itself lingers as a tombstone until
  /// [purge] removes it after the server accepts the pushed delete.
  Future<void> delete(String id) async {
    await _db.transaction(() async {
      // Keep referencing rows intact with their category reference cleared.
      await (_db.update(_db.expenses)..where((e) => e.categoryId.equals(id)))
          .write(const ExpensesCompanion(categoryId: Value(null)));
      await (_db.update(_db.budgets)..where((b) => b.categoryId.equals(id)))
          .write(const BudgetsCompanion(categoryId: Value(null)));
      await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        pendingSync: const Value(true),
      ));
    });
    onMutated?.call();
  }

  /// Removes a tombstone whose push the server accepted, plus any
  /// referencing rows still pointing at it (idempotent).
  Future<void> purge(String id) {
    return _db.transaction(() async {
      await (_db.update(_db.expenses)..where((e) => e.categoryId.equals(id)))
          .write(const ExpensesCompanion(categoryId: Value(null)));
      await (_db.update(_db.budgets)..where((b) => b.categoryId.equals(id)))
          .write(const BudgetsCompanion(categoryId: Value(null)));
      await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
    });
  }

  Future<void> _guardDuplicate(String name, {String? excludingId}) async {
    final query = _db.select(_db.categories)
      ..where((c) => c.deletedAt.isNull() &
          c.name.lower().equals(name.toLowerCase()));
    final existing = await query.get();
    final clash = existing.any((row) => row.id != excludingId);
    if (clash) throw DuplicateCategoryException(name);
  }
}
