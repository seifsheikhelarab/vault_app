import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
import 'package:vault_app/main.dart';

Widget appUnderTest() => ProviderScope(
      overrides: [
        vaultDatabaseProvider
            .overrideWithValue(AsyncValue.data(VaultDatabase(NativeDatabase.memory()))),
      ],
      child: const VaultApp(),
    );

/// Unmounts while still inside the test's fake-async zone, then pumps so
/// drift's internal stream-cleanup timers fire before the framework's
/// no-pending-timers invariant check.
void flushTreeOnTearDown(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  });
}

Future<void> pumpApp(WidgetTester tester) async {
  flushTreeOnTearDown(tester);
  await tester.pumpWidget(appUnderTest());
  await tester.pumpAndSettle();
}

Future<void> signIn(WidgetTester tester) async {
  await pumpApp(tester);
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'seif@example.com');
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'longenough1');
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
  });

  testWidgets('sign-in validates empty and malformed input', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'nope');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });

  testWidgets('valid sign-in reaches the four-tab shell with capture FAB', (tester) async {
    await signIn(tester);

    expect(find.text('Your month at a glance'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    for (final label in ['Dashboard', 'Expenses', 'Chat', 'Settings']) {
      expect(navLabel(label), findsOneWidget);
    }
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
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('sign out returns to sign-in', (tester) async {
    await signIn(tester);

    await tester.tap(navLabel('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('capture FAB opens the log-an-expense sheet', (tester) async {
    await signIn(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text('Log an expense'), findsOneWidget);
    expect(find.text('Save expense'), findsOneWidget);
  });

  testWidgets('sign-up screen toggles from sign-in and validates', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Create one'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Create account'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });
}
