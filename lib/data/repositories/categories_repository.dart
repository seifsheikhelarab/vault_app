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

/// Categories are fully offline-writable; deleting one nulls the
/// `categoryId` of referencing expenses so history survives taxonomy
/// changes (mirrors server hard-delete semantics).
class CategoriesRepository {
  CategoriesRepository(this._db);

  final VaultDatabase _db;

  Stream<List<CategoryRow>> watchAll() {
    return (_db.select(_db.categories)
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
          CategoriesCompanion.insert(id: id, name: name),
        );
    return CategoryRow(id: id, name: name);
  }

  Future<void> rename(String id, String rawName) async {
    final name = rawName.trim();
    _validateName(name);
    await _guardDuplicate(name, excludingId: id);
    await (_db.update(_db.categories)..where((c) => c.id.equals(id)))
        .write(CategoriesCompanion(name: Value(name)));
  }

  Future<void> delete(String id) {
    return _db.transaction(() async {
      // Keep referencing expenses intact with their category reference cleared.
      await (_db.update(_db.expenses)..where((e) => e.categoryId.equals(id)))
          .write(const ExpensesCompanion(categoryId: Value(null)));
      await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
    });
  }

  Future<void> _guardDuplicate(String name, {String? excludingId}) async {
    final query = _db.select(_db.categories)
      ..where((c) => c.name.lower().equals(name.toLowerCase()));
    final existing = await query.get();
    final clash = existing.any((row) => row.id != excludingId);
    if (clash) throw DuplicateCategoryException(name);
  }
}
