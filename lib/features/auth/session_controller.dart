import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a session is active. Placeholder until the auth client lands:
/// sign-in flips it locally so the guarded shell is demoable end to end.
class SessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void signIn() => state = true;

  void signOut() => state = false;
}

final sessionProvider =
    NotifierProvider<SessionController, bool>(SessionController.new);
