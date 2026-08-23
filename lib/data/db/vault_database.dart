import 'package:drift/drift.dart';

part 'vault_database.g.dart';

/// Local category taxonomy. Mirrors `/api/categories` rows minus server-only
/// fields; `id` is a client-minted UUID so offline creates sync cleanly.
@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local expense ledger. `amountMinor` is integer piasters. `pendingSync`
/// marks rows the sync engine still owes the server. `recurringId` is
/// reserved for the recurring-source badge.
@DataClassName('ExpenseRow')
class Expenses extends Table {
  TextColumn get id => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  BoolColumn get pendingSync =>
      boolean().named('pending_sync').withDefault(const Constant(false))();
  TextColumn get recurringId => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Categories, Expenses])
class VaultDatabase extends _$VaultDatabase {
  VaultDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
