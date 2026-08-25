import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';

/// Auth gate for the router. `AsyncLoading` = boot still deciding (router
/// holds course); `AsyncData(true/false)` = decided.
class SessionController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final api = ref.watch(apiClientProvider);
    // Any protected route answering 401 later (revoked/expired session)
    // drops the user back to sign-in through the router's redirect.
    api.onUnauthorized = () => state = const AsyncData(false);
    final token = await api.readToken();
    if (token == null) return false;
    try {
      final session = await api.getSession();
      return session != null;
    } catch (_) {
      // Boot-time network failure ≠ dead session: trust the stored token so
      // an offline cold start stays in the app. If the token really is dead,
      // the next request answers 401, clears it, and the router redirects.
      return true;
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
