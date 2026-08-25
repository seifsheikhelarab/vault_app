import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/connectivity_provider.dart';
import '../../features/auth/session_controller.dart';
import '../providers.dart';
import 'sync_engine.dart';

final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  return SyncEngine(
    await ref.watch(vaultDatabaseProvider.future),
    ref.watch(apiClientProvider),
  );
});

/// Latest sync-cycle outcome, for the quiet "not synced" indicator.
class SyncStatusNotifier extends Notifier<SyncStatus?> {
  @override
  SyncStatus? build() => null;

  void set(SyncStatus status) => state = status;
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus?>(SyncStatusNotifier.new);

/// Fan-in point for every sync trigger. Mutations land here debounced;
/// manual pull-to-refresh awaits [refresh] directly.
class SyncScheduler {
  SyncScheduler(this._engine);

  static const _debounceDelay = Duration(milliseconds: 800);

  final SyncEngine _engine;
  Timer? _debounce;

  /// A local write happened — schedule one cycle shortly, collapsing bursts.
  void nudge() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _engine.runCycle);
  }

  /// Awaitable cycle for explicit user actions (pull-to-refresh).
  /// Completes normally even when offline; failures are silent.
  Future<void> refresh() => _engine.runCycle();

  void dispose() {
    _debounce?.cancel();
  }
}

final syncSchedulerProvider = FutureProvider<SyncScheduler>((ref) async {
  final engine = await ref.watch(syncEngineProvider.future);
  final scheduler = SyncScheduler(engine);
  ref.onDispose(scheduler.dispose);
  engine.onStatus = ref.read(syncStatusProvider.notifier).set;

  // App-launch trigger: first resolution as signed-in kicks off a cycle.
  // Connectivity regain: false -> true edge while the stream runs.
  var wasOnline = false;
  ref.listen(sessionProvider, (_, next) {
    if (next.asData?.value ?? false) scheduler.nudge();
  });
  ref.listen(connectivityProvider, (_, next) {
    final online = next.asData?.value;
    if (online != null && online && !wasOnline) scheduler.nudge();
    if (online != null) wasOnline = online;
  });

  return scheduler;
});
