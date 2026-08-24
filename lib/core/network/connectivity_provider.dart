import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True whenever any radio reports connectivity. Online-only flows (chat
/// parse, budgets) gate their actions on this; `null` means still loading,
/// which callers treat as online and let real request errors speak instead.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity()
      .onConnectivityChanged
      .map((results) => results.any((r) => r != ConnectivityResult.none));
});

/// Collapse an [AsyncValue] of [connectivityProvider] to a plain bool:
/// loading counts as online (real request errors speak instead).
bool isOnline(AsyncValue<bool> state) => state.value ?? true;

/// One-line online read for gating UI and writes.
final isOnlineProvider =
    Provider.autoDispose<bool>((ref) => isOnline(ref.watch(connectivityProvider)));
