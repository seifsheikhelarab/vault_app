import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True when the OS reports any usable transport (wifi/mobile/ethernet/vpn).
/// `null` while the first check is in flight — UI treats null as online and
/// lets the repository-level guard have the final word.
///
/// Note: session boot already collapses "offline at boot" into sign-out
/// (ticket #3), so this only gates in-session budget writes.
final connectivityProvider = StreamProvider<bool>((ref) {
  final plugin = Connectivity();
  Future<bool> toOnline(List<ConnectivityResult> results) async =>
      results.hasConnectivity;
  return plugin.onConnectivityChanged.asyncMap(toOnline);
});

/// Optimistic read for gating UI. Writes are additionally guarded by the
/// same signal inside [BudgetsRepository], so a stale optimistic true can
/// never silently queue anything — it just surfaces an API error.
bool isOnline(AsyncValue<bool> state) => state.value ?? true;
