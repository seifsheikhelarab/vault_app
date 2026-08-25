import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/network/api_client.dart';
import 'db/vault_database.dart';
import 'repositories/budgets_repository.dart';
import 'repositories/categories_repository.dart';
import 'repositories/expenses_repository.dart';
import 'repositories/recurring_repository.dart';
import 'sync/sync_providers.dart';

/// Opens the on-disk database. Overridden with `NativeDatabase.memory()` in
/// tests.
///
/// A corrupt file would otherwise fail this provider and brick every data
/// screen, so open failures move the file aside and start fresh — synced
/// rows return on the next full pull.
final vaultDatabaseProvider = FutureProvider<VaultDatabase>((ref) async {
  final dir = await getApplicationSupportDirectory();
  final dbFile = File('${dir.path}${Platform.pathSeparator}vault.sqlite');

  Future<VaultDatabase> open() async {
    final db = VaultDatabase(
      NativeDatabase.createInBackground(
        dbFile,
        setup: (raw) {
          raw.execute('PRAGMA foreign_keys = ON');
          raw.execute('PRAGMA journal_mode = WAL');
        },
      ),
    );
    // Force a real table read now so corruption surfaces here, not mid-UI.
    await db.select(db.categories).get();
    return db;
  }

  VaultDatabase db;
  try {
    db = await open();
  } catch (_) {
    // ponytail: whole-file quarantine; per-page salvage if corruption ever
    // recurs in the field.
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File('${dbFile.path}$suffix');
      final dead = File('${dbFile.path}$suffix.corrupt');
      if (await dead.exists()) await dead.delete();
      if (await source.exists()) await source.rename(dead.path);
    }
    db = await open();
  }
  ref.onDispose(db.close);
  return db;
});

final categoriesRepositoryProvider = FutureProvider<CategoriesRepository>(
  (ref) async => CategoriesRepository(await ref.watch(vaultDatabaseProvider.future))
    ..onMutated = (await ref.watch(syncSchedulerProvider.future)).nudge,
);

/// Live category list for chips and management UI. The stream instance is
/// owned here so widgets never resubscribe per rebuild.
final categoriesListProvider =
    StreamProvider.autoDispose<List<CategoryRow>>((ref) {
  final repo = ref.watch(categoriesRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchAll();
});

final expensesRepositoryProvider = FutureProvider<ExpensesRepository>(
  (ref) async => ExpensesRepository(await ref.watch(vaultDatabaseProvider.future))
    ..onMutated = (await ref.watch(syncSchedulerProvider.future)).nudge,
);

final budgetsRepositoryProvider = FutureProvider<BudgetsRepository>(
  (ref) async => BudgetsRepository(
    await ref.watch(vaultDatabaseProvider.future),
    ref.watch(apiClientProvider),
  ),
);

final recurringRepositoryProvider = FutureProvider<RecurringRepository>(
  (ref) async => RecurringRepository(
    await ref.watch(vaultDatabaseProvider.future),
    ref.watch(apiClientProvider),
  ),
);
