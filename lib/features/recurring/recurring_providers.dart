import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity_provider.dart';
import '../../data/db/vault_database.dart';
import '../../data/providers.dart';

/// Cached recurring rules, streamed from the local table.
final recurringListProvider =
    StreamProvider.autoDispose<List<RecurringRow>>((ref) {
  final repo = ref.watch(recurringRepositoryProvider).value;
  if (repo == null) return const Stream<Never>.empty();
  return repo.watchAll();
});

/// One-line online read for gating UI and writes; the repository re-guards
/// so a stale optimistic true can only surface an API error, never queue.
final isOnlineProvider = Provider.autoDispose<bool>(
    (ref) => ref.watch(connectivityProvider).value ?? true);
