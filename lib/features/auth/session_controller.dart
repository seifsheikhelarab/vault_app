import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// Auth gate for the router. `AsyncLoading` = boot still deciding (router
/// holds course); `AsyncData(true/false)` = decided.
class SessionController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final api = ref.watch(apiClientProvider);
    final token = await api.readToken();
    if (token == null) return false;
    try {
      final session = await api.getSession();
      return session != null;
    } catch (_) {
      // Dead or unreachable cookie at boot ⇒ treat as signed out.
      // ponytail: collapses offline-with-valid-cookie into sign-in; revisit
      // when offline mode lands and a cached identity matters.
      return false;
    }
  }

  Future<void> signIn(String email, String password) async {
    final api = ref.watch(apiClientProvider);
    await api.signInEmail(email: email.trim(), password: password);
    state = const AsyncData(true);
  }

  Future<void> signUp(String name, String email, String password) async {
    final api = ref.watch(apiClientProvider);
    await api.signUpEmail(
        name: name.trim(), email: email.trim(), password: password);
    state = const AsyncData(true);
  }

  /// Endpoint call is best-effort — the local session dies either way,
  /// so the user is never trapped by a flaky sign-out.
  Future<void> signOut() async {
    final api = ref.watch(apiClientProvider);
    try {
      await api.signOut();
    } catch (_) {}
    await api.clearToken();
    state = const AsyncData(false);
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, bool>(SessionController.new);
