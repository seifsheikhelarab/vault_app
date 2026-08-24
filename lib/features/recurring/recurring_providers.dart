import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Cached recurring rules, streamed from the local table.
final recurringListProvider =
    StreamProvider.autoDispose<List<RecurringRow>>((ref) {
  final repo = ref.watch(recurringRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchAll();
});
