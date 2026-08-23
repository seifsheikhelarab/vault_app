import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../repositories/categories_repository.dart';
import '../repositories/expenses_repository.dart';
import 'db/vault_database.dart';

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
  (ref) async => CategoriesRepository(await ref.watch(vaultDatabaseProvider.future)),
);

final expensesRepositoryProvider = FutureProvider<ExpensesRepository>(
  (ref) async => ExpensesRepository(await ref.watch(vaultDatabaseProvider.future)),
);
