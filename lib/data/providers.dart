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
final vaultDatabaseProvider = FutureProvider<VaultDatabase>((ref) async {
  final dir = await getApplicationSupportDirectory();
  final db = VaultDatabase(
    NativeDatabase.createInBackground(
      File('${dir.path}${Platform.pathSeparator}vault.sqlite'),
      setup: (raw) => raw.execute('PRAGMA foreign_keys = ON'),
    ),
  );
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
