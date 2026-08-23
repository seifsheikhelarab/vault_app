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
