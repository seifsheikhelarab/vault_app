import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vault_app/core/router/app_router.dart';
import 'package:vault_app/features/auth/session_controller.dart';
import 'package:vault_app/features/auth/sign_in_screen.dart';

/// Session gate stub: null result = still deciding (boot splash holds);
/// true/false = decided.
class _FixedSession extends SessionController {
  _FixedSession(this.result);

  final bool? result;

  @override
  Future<bool> build() =>
      result == null ? Completer<bool>().future : Future.value(result);
}

Future<void> _pumpApp(WidgetTester tester, {required bool? session}) async {
  final container = ProviderContainer(overrides: [
    sessionProvider.overrideWith(() => _FixedSession(session)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: container.read(appRouterProvider)),
  );
  // Two frames: one to build the initial route, one for the redirect pass.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('cold start parks on splash while the gate is undecided',
      (tester) async {
    await _pumpApp(tester, session: null);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
  });

  testWidgets('splash hands off to sign-in when signed out', (tester) async {
    await _pumpApp(tester, session: false);

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
