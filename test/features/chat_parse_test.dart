import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault_app/core/network/api_client.dart';
import 'package:vault_app/core/network/connectivity_provider.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/providers.dart';
import 'package:vault_app/data/repositories/categories_repository.dart';
import 'package:vault_app/data/repositories/expenses_repository.dart';
import 'package:vault_app/features/chat/chat_screen.dart';

/// In-memory stand-in for secure storage (pattern from
/// api_client_change_password_test.dart).
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

void main() {
  late VaultDatabase db;
  late ExpensesRepository expenses;
  late CategoriesRepository categories;

  setUp(() {
    db = VaultDatabase(NativeDatabase.memory());
    expenses = ExpensesRepository(db);
    categories = CategoriesRepository(db);
  });

  tearDown(() => db.close());

  Future<Widget> harness({
    required http.Client httpClient,
    Stream<bool>? connectivity,
  }) async {
    final storage = _FakeStorage();
    return ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(client: httpClient, storage: storage),
        ),
        connectivityProvider.overrideWith((ref) =>
            connectivity ?? const Stream<bool>.empty()),
        vaultDatabaseProvider.overrideWith((ref) async => db),
        expensesRepositoryProvider.overrideWith((ref) async => expenses),
        categoriesRepositoryProvider.overrideWith((ref) async => categories),
      ],
      child: const MaterialApp(home: ChatScreen()),
    );
  }

  Future<void> pumpChat(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  /// Types a phrase and taps the send button.
  Future<void> submitPhrase(WidgetTester tester, String phrase) async {
    await tester.enterText(find.byType(TextField).first, phrase);
    await tester.pump();
    await tester.tap(find.byTooltip('Parse into a draft'));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Unmounts the scope while we still control pumping, so drift's
  /// stream-close timer fires instead of tripping the no-pending-timers
  /// invariant.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  }

  IconButton sendButton(WidgetTester tester) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.send_outlined),
          matching: find.byType(IconButton),
        ).first,
      );

  testWidgets('parse success shows editable draft with parsed fields',
      (tester) async {
    final food = await categories.create('Food');
    http.Request? parseReq;
    await pumpChat(
      tester,
      await harness(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/chat/parse');
          parseReq = req;
          return http.Response(
            jsonEncode({
              'amountMinor': 25050,
              'categoryGuess': 'Groceries',
              'categoryId': food.id,
              'occurredAtGuess': '2026-08-24',
              'note': 'weekly shop',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await submitPhrase(tester, 'groceries 250.50');

    expect(parseReq, isNotNull);
    expect(jsonDecode(parseReq!.body), {'message': 'groceries 250.50'});

    // Draft card replaces the empty state.
    expect(find.text('Review expense'), findsOneWidget);
    expect(find.text('Turn words into an expense'), findsNothing);

    // Parsed fields land in the editable fields.
    final amount = tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    expect(amount.controller!.text, '250.50');
    expect(amount.enabled, isTrue, reason: 'amount must stay editable');
    final note = tester.widget<TextFormField>(find.byType(TextFormField).at(1));
    expect(note.controller!.text, 'weekly shop');
    expect(note.enabled, isTrue, reason: 'note must stay editable');
    expect(find.text('Guessed category: Groceries'), findsOneWidget);

    // Parsed category preselected on the chip.
    final chip =
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Food'));
    expect(chip.selected, isTrue);

    // Date row renders the parsed guess.
    expect(find.textContaining('24 Aug 2026'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('confirm posts client-UUID expense then inserts synced locally',
      timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    await categories.create('Food');
    http.Request? expenseReq;
    await pumpChat(
      tester,
      await harness(
        httpClient: MockClient((req) async {
          switch (req.url.path) {
            case '/api/chat/parse':
              return http.Response(
                jsonEncode({
                  'amountMinor': 25050,
                  'categoryGuess': null,
                  'categoryId': null,
                  'occurredAtGuess': '2026-08-24',
                  'note': null,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            case '/api/expenses':
              expenseReq = req;
              return http.Response('', 201);
            default:
              fail('unexpected request ${req.url}');
          }
        }),
      ),
    );

    await submitPhrase(tester, 'taxi 250.50');

    // User edits the draft before confirming — proves editability flows
    // into what gets saved.
    await tester.enterText(find.byType(TextFormField).at(0), '300');
    await tester.enterText(find.byType(TextFormField).at(1), 'airport taxi');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save expense'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Wire payload: UUID id + integer piasters + ISO instant.
    expect(expenseReq, isNotNull);
    expect(expenseReq!.method, 'POST');
    final body = jsonDecode(expenseReq!.body) as Map<String, dynamic>;
    expect(body['id'],
        matches(RegExp(r'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$')));
    expect(body['amountMinor'], 30000);
    expect(body['amountMinor'], isA<int>());
    expect(body['note'], 'airport taxi');
    // Local midnight of the picked day, sent as a UTC instant.
    final occurredAt = DateTime.parse(body['occurredAt'] as String);
    expect(occurredAt.isUtc, isTrue);
    final localDay = occurredAt.toLocal();
    expect(
      DateTime(localDay.year, localDay.month, localDay.day),
      DateTime(2026, 8, 24),
      reason: 'wire instant must resolve to the drafted local day',
    );

    // Local insert exists under the SAME id, already synced.
    final rows = await db.select(db.expenses).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, body['id']);
    expect(rows.single.amountMinor, 30000);
    expect(rows.single.pendingSync, isFalse,
        reason: 'server accepted first; sync engine must not re-push');
    expect(rows.single.note, 'airport taxi');

    expect(find.text('Review expense'), findsNothing);
    expect(find.text('Expense saved.'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('parse error shows inline error and creates no draft',
      timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    var parseCalls = 0;
    await pumpChat(
      tester,
      await harness(
        httpClient: MockClient((req) async {
          expect(req.url.path, '/api/chat/parse');
          parseCalls++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'PARSE_FAILED', 'message': 'unintelligible'},
            }),
            422,
            headers: {'content-type': 'application/json'},
          );
        }),
      ),
    );

    await submitPhrase(tester, 'asdf qwerty zzz');

    expect(parseCalls, 1);
    expect(find.text("Vault couldn't read that — try rephrasing."),
        findsOneWidget);
    // No draft card — still the empty state.
    expect(find.text('Review expense'), findsNothing);
    expect(find.text('Turn words into an expense'), findsOneWidget);
    expect(await db.select(db.expenses).get(), isEmpty);

    await unmount(tester);
  });

  testWidgets('offline at mount disables send and explains why',
      (tester) async {
    await pumpChat(
      tester,
      await harness(
        connectivity: Stream.value(false),
        httpClient: MockClient((req) async => fail('no requests offline')),
      ),
    );

    expect(sendButton(tester).onPressed, isNull);
    expect(find.textContaining("You're offline"), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('offline while draft open swaps save button for offline note',
      timeout: const Timeout(Duration(minutes: 2)), (tester) async {
    final connectivity = StreamController<bool>();
    addTearDown(connectivity.close);
    await pumpChat(
      tester,
      await harness(
        connectivity: connectivity.stream,
        httpClient: MockClient((req) async {
          switch (req.url.path) {
            case '/api/chat/parse':
              return http.Response(
                jsonEncode({
                  'amountMinor': 25050,
                  'categoryGuess': null,
                  'categoryId': null,
                  'occurredAtGuess': '2026-08-24',
                  'note': null,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            default:
              fail('unexpected request ${req.url}');
          }
        }),
      ),
    );
    connectivity.add(true);
    await tester.pumpAndSettle();

    await submitPhrase(tester, 'taxi 250.50');
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsOneWidget);

    // Drop offline: confirm action disappears, inline note takes its place.
    connectivity.add(false);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Save expense'), findsNothing);
    expect(find.text("You're offline — saving needs a connection."),
        findsOneWidget);
    expect(await db.select(db.expenses).get(), isEmpty);

    await unmount(tester);
  });
}
