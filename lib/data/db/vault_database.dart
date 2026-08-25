import 'package:drift/drift.dart';

part 'vault_database.g.dart';

/// Local category taxonomy. Mirrors `/api/categories` rows minus server-only
/// fields; `id` is a client-minted UUID so offline creates sync cleanly.
///
/// Sync fields: `updatedAt` feeds last-write-wins pushes; `pendingSync`
/// marks rows the sync engine still owes the server; `deletedAt` stages a
/// delete until the server accepts the tombstone (categories hard-delete
/// there, so the local row is removed only after an accepted push).
@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync =>
      boolean().named('pending_sync').withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local expense ledger. `amountMinor` is integer piasters. `pendingSync`
/// marks rows the sync engine still owes the server. `recurringId` is
/// reserved for the recurring-source badge.
///
/// `updatedAt`/`deletedAt` mirror the `/api/sync/push` whole-row LWW
/// payload: edits bump `updatedAt`, deletions stage a `deletedAt` tombstone
/// that is pushed, then the row is removed once the server accepts.
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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached budget row. Budgets are ONLINE-ONLY for writes (not part of
/// /api/sync); this table is a read cache of `/api/budgets` rows. Mirrors
/// the contract shape minus server-only fields. `periodType` is
/// `'week' | 'month'`; `categoryId` null = overall budget.
@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get periodType => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached recurring-rule row (`/api/recurring`, contract §8). Online-only
/// writes like budgets; this table is a read cache of the server list minus
/// server-only fields (userId, currency is fixed EGP, lastMaterializedAt).
/// `frequency` is `'daily' | 'weekly' | 'monthly'`; `anchorDate`/`nextRunAt`
/// store ISO instants (server sends anchor as ISO midnight).
@DataClassName('RecurringRow')
class Recurrings extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get frequency => text()();
  IntColumn get interval => integer().withDefault(const Constant(1))();
  DateTimeColumn get anchorDate => dateTime()();
  DateTimeColumn get nextRunAt => dateTime()();
  BoolColumn get paused => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value store for sync engine state. One row (`key = 'pull'`) holds
/// the incremental pull cursor so it survives process restarts.
@DataClassName('SyncStateRow')
class SyncState extends Table {
  TextColumn get key => text()();
  TextColumn get cursor => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Categories, Expenses, Budgets, Recurrings, SyncState])
class VaultDatabase extends _$VaultDatabase {
  VaultDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (to < from) {
            // App rollback against a newer-schema file would misbehave at
            // runtime; drop and recreate fresh. Synced rows return on the
            // next sync cycle's full pull.
            final db = m.database;
            for (final name in [
              'categories',
              'expenses',
              'budgets',
              'recurrings',
              'sync_state',
            ]) {
              await db.customStatement('DROP TABLE IF EXISTS $name');
            }
            await m.createAll();
            return;
          }
          if (from < 2) await m.createTable(budgets);
          if (from < 3) {
            await m.createTable(syncState);
            // NOT NULL additions carry defaults so existing rows backfill.
            await m.addColumn(categories, categories.updatedAt);
            await m.addColumn(categories, categories.pendingSync);
            await m.addColumn(categories, categories.deletedAt);
            await m.addColumn(expenses, expenses.updatedAt);
          }
          if (from < 4) await m.createTable(recurrings);
        },
      );
}
