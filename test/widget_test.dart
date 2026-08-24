import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault_app/core/network/api_client.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
import 'package:vault_app/main.dart';

/// In-memory stand-in for secure storage, same shape as the ApiClient
/// change-password test's fake.
class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
    WebOptions? webOptions,
  }) async {
    values.remove(key);
  }
}

/// Routes the auth endpoints the shell flow touches; anything else 404s.
Future<http.Response> _route(http.Request request) async {
  final path = request.url.path;
  if (path == '/api/auth/get-session') {
    return http.Response('null', 200);
  }
  if (path == '/api/auth/sign-in/email') {
    return http.Response('{}', 200, headers: {
      'set-cookie': 'better-auth.session_token=fake-token; Path=/',
    });
  }
  if (path == '/api/auth/sign-up/email') {
    return http.Response('{}', 200, headers: {
      'set-cookie': 'better-auth.session_token=fake-token; Path=/',
    });
  }
  if (path == '/api/auth/sign-out') {
    return http.Response('{}', 200);
  }
  return http.Response('{"error":{"code":"not_found"}}', 404);
}

Widget appUnderTest() => ProviderScope(
      overrides: [
        vaultDatabaseProvider.overrideWithValue(
            AsyncValue.data(VaultDatabase(NativeDatabase.memory()))),
        apiClientProvider.overrideWithValue(
          ApiClient(client: MockClient(_route), storage: _FakeStorage()),
        ),
      ],
      child: const VaultApp(),
    );

/// Unmounts while still inside the test's fake-async zone, then pumps once
/// so drift's internal stream-cleanup timers fire before the framework's
/// no-pending-timers invariant check. Must be awaited at the END of every
/// test body — an addTearDown-based version runs outside the fake-async
/// zone and leaves the timer pending.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(appUnderTest());
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'), 'seif@example.com');
  await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'), 'longenough1');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

Finder navLabel(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

void main() {
  testWidgets('opens on sign-in when signed out', (tester) async {
    await pumpApp(tester);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('sign-in validates empty and malformed input', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'nope');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('valid sign-in reaches the four-tab shell with capture FAB',
      (tester) async {
    await signIn(tester);

    expect(find.text('Your month at a glance'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    for (final label in ['Dashboard', 'Expenses', 'Chat', 'Settings']) {
      expect(navLabel(label), findsOneWidget);
    }
    await unmount(tester);
  });

  testWidgets('tabs switch branches', (tester) async {
    await signIn(tester);

    await tester.tap(navLabel('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing logged yet'), findsOneWidget);

    await tester.tap(navLabel('Chat'));
    await tester.pumpAndSettle();
    expect(find.text('Turn words into an expense'), findsOneWidget);

    await tester.tap(navLabel('Settings'));
    await tester.pumpAndSettle();
    // Sign out sits at the bottom of a lazy ListView — bring it into the
    // viewport before asserting.
    await tester.dragUntilVisible(
        find.text('Sign out'), find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('sign out returns to sign-in', (tester) async {
    await signIn(tester);

    await tester.tap(navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
        find.text('Sign out'), find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('capture FAB opens the log-an-expense sheet', (tester) async {
    await signIn(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Log an expense'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('sign-up screen toggles from sign-in and validates',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Create one'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);

    await tester
        .tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    await unmount(tester);
  });
}
