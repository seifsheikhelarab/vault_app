import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault_app/core/network/api_client.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/sync/sync_engine.dart';

/// In-memory stand-in for secure storage (same shape as the one in
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
    AndroidOptions? aOptions,
    AppleOptions? iOptions,
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
  // Whole-second UTC instants everywhere: drift stores DateTimes with second
  // precision, so sub-second timestamps would not round-trip exactly.
  final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
  final t2 = DateTime.utc(2026, 1, 1, 12, 0, 2);

  late VaultDatabase db;

  setUp(() {
    db = VaultDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  // ── helpers ───────────────────────────────────────────────────────────

  String iso(DateTime d) => d.toUtc().toIso8601String();

  http.Response jsonRes(Object body, {int status = 200}) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> pullPage({
    List<Map<String, dynamic>> expenses = const [],
    List<Map<String, dynamic>> categories = const [],
    String? nextCursor,
  }) =>
      {
        'expenses': expenses,
        'categories': categories,
        'nextCursor': nextCursor,
      };

  Map<String, dynamic> serverExpense({
    required String id,
    required DateTime updatedAt,
    int amountMinor = 100,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
    String? deletedAt,
  }) =>
      {
        'id': id,
        'updatedAt': iso(updatedAt),
        'amountMinor': amountMinor,
        'occurredAt': iso(occurredAt ?? updatedAt),
        'categoryId': ?categoryId,
        'note': ?note,
        'createdAt': iso(updatedAt),
        'recurringDefinitionId': null,
        'deletedAt': ?deletedAt,
      };

  Map<String, dynamic> serverCategory({
    required String id,
    required DateTime updatedAt,
    String name = 'Cat',
  }) =>
      {'id': id, 'name': name, 'updatedAt': iso(updatedAt)};

  List<Map<String, dynamic>> pushResults(
    Iterable<String> ids, {
    String outcome = 'accepted',
  }) =>
      [for (final id in ids) {'id': id, 'outcome': outcome}];

  ApiClient apiWith(
    Future<http.Response> Function(http.Request req) handler,
  ) =>
      ApiClient(
        client: MockClient(handler),
        storage: (_FakeStorage()..values['better-auth.session_token'] = 't'),
      );

  Future<void> seedCategory({
    required String id,
    String name = 'Cat',
    bool pendingSync = false,
    DateTime? updatedAt,
  }) =>
      db.into(db.categories).insert(
            CategoriesCompanion.insert(
              id: id,
              name: name,
              updatedAt: Value(updatedAt ?? t0),
              pendingSync: Value(pendingSync),
            ),
          );

  Future<void> seedExpense({
    required String id,
    int amountMinor = 100,
    String? categoryId,
    String? note,
    required DateTime occurredAt,
    bool pendingSync = false,
    DateTime? updatedAt,
  }) =>
      db.into(db.expenses).insert(
            ExpensesCompanion.insert(
              id: id,
              amountMinor: amountMinor,
              categoryId: Value(categoryId),
              occurredAt: occurredAt,
              note: Value(note),
              recurringId: const Value(null),
              updatedAt: Value(updatedAt ?? t0),
              pendingSync: Value(pendingSync),
            ),
          );

  Future<CategoryRow?> categoryById(String id) =>
      (db.select(db.categories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<ExpenseRow?> expenseById(String id) =>
      (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<List<SyncStateRow>> cursorRows() => db.select(db.syncState).get();

  /// Routes a canned sync backend. [pushBodies]/[pullRequests] record every
  /// hit; responses come from the queues/lists the test fills.
  ({
    ApiClient api,
    List<Map<String, dynamic>> pushBodies,
    List<http.Request> pullRequests,
  }) mockSync({
    List<Map<String, dynamic>> Function(Map<String, dynamic> pushBody)?
        onPush,
    Map<String, dynamic>? Function(int pageIndex)? onPull,
    List<Map<String, dynamic>>? serverCategories,
  }) {
    final pushBodies = <Map<String, dynamic>>[];
    final pullRequests = <http.Request>[];
    var pullIndex = 0;
    final api = apiWith((req) async {
      switch (req.url.path) {
        case '/api/sync/push':
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          pushBodies.add(body);
          return jsonRes({
            'results': onPush?.call(body) ??
                pushResults([
                  ...(body['categories'] as List).cast<Map<String, dynamic>>(),
                  ...(body['expenses'] as List).cast<Map<String, dynamic>>(),
                ].map((r) => r['id'] as String)),
          });
        case '/api/sync/pull':
          pullRequests.add(req);
          final page = onPull?.call(pullIndex++) ?? pullPage();
          return jsonRes(page);
        case '/api/categories':
          return jsonRes(serverCategories ?? const []);
      }
      return http.Response('not found', 404);
    });
    return (api: api, pushBodies: pushBodies, pullRequests: pullRequests);
  }

  // ── tests ─────────────────────────────────────────────────────────────

  group('sync engine', () {
    test('push sends dirty categories and expenses together in one batch, '
        'categories before expenses', () async {
      await seedCategory(id: 'cat-1', pendingSync: true);
      await seedExpense(id: 'exp-1', pendingSync: true, occurredAt: t0);
      final m = mockSync(
        serverCategories: [serverCategory(id: 'cat-1', updatedAt: t0)],
      );
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      expect(m.pushBodies, hasLength(1));
      final body = m.pushBodies.single;
      expect(
        (body['categories'] as List).map((c) => c['id']),
        ['cat-1'],
      );
      expect(
        (body['expenses'] as List).map((e) => e['id']),
        ['exp-1'],
      );
      // Same request carries both arrays; encoded key order puts categories
      // first (the order the server applies them in).
      final raw = jsonEncode(body);
      expect(raw.indexOf('"categories"'), lessThan(raw.indexOf('"expenses"')));
    });

    test('accepted push clears pendingSync on categories and expenses',
        () async {
      await seedCategory(id: 'cat-1', pendingSync: true);
      await seedExpense(id: 'exp-1', pendingSync: true, occurredAt: t0);
      final m = mockSync(
        serverCategories: [serverCategory(id: 'cat-1', updatedAt: t0)],
      );
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      expect((await categoryById('cat-1'))!.pendingSync, isFalse);
      expect((await expenseById('exp-1'))!.pendingSync, isFalse);
    });

    test('conflict-lost outcome also clears pendingSync', () async {
      await seedCategory(id: 'cat-1', pendingSync: true);
      await seedExpense(id: 'exp-1', pendingSync: true, occurredAt: t0);
      final m = mockSync(
        onPush: (_) => pushResults(['cat-1', 'exp-1'],
            outcome: 'conflict-lost'),
        serverCategories: [serverCategory(id: 'cat-1', updatedAt: t0)],
      );
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      expect((await categoryById('cat-1'))!.pendingSync, isFalse);
      expect((await expenseById('exp-1'))!.pendingSync, isFalse);
    });

    test('conflict-lost push resets the pull cursor so the next drain '
        'starts from scratch', () async {
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(key: 'pull', cursor: Value('old-c')),
          );
      await seedExpense(id: 'exp-1', pendingSync: true, occurredAt: t0);
      final m = mockSync(
        onPush: (_) => pushResults(['exp-1'], outcome: 'conflict-lost'),
        onPull: (i) => i == 0
            ? pullPage(nextCursor: 'c1')
            : pullPage(nextCursor: null),
      );
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      // The pre-existing 'old-c' cursor was discarded: the first page of the
      // post-push drain went out without a cursor param.
      expect(m.pullRequests, hasLength(2));
      expect(m.pullRequests[0].url.queryParameters.containsKey('cursor'),
          isFalse);
      expect(m.pullRequests[1].url.queryParameters['cursor'], 'c1');
      // Drain finished, so the stored cursor is the terminal null again.
      final rows = await cursorRows();
      expect(rows.single.key, 'pull');
      expect(rows.single.cursor, isNull);
    });

    test('pull drains pages until nextCursor is null, persists the cursor '
        'per page, inserts pulled rows and applies tombstones', () async {
      // A local clean row that the server has tombstoned.
      await seedExpense(id: 'exp-old', occurredAt: t0);
      final m = mockSync(onPull: (i) => i == 0
          ? pullPage(
              categories: [serverCategory(id: 'cat-1', updatedAt: t0)],
              expenses: [
                serverExpense(
                  id: 'exp-1',
                  updatedAt: t2,
                  amountMinor: 2500,
                  note: 'pulled',
                ),
              ],
              nextCursor: 'c1',
            )
          : pullPage(
              expenses: [
                serverExpense(
                  id: 'exp-old',
                  updatedAt: t2,
                  deletedAt: iso(t2),
                ),
              ],
              nextCursor: null,
            ));
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      // Two page requests: first without a cursor, second resuming from c1 —
      // which proves the cursor was persisted after page one.
      expect(m.pullRequests, hasLength(2));
      expect(m.pullRequests[0].url.queryParameters.containsKey('cursor'),
          isFalse);
      expect(m.pullRequests[1].url.queryParameters['cursor'], 'c1');

      final pulled = (await expenseById('exp-1'))!;
      expect(pulled.amountMinor, 2500);
      expect(pulled.note, 'pulled');
      expect(pulled.pendingSync, isFalse);

      // Pulled tombstone removed the local row outright.
      expect(await expenseById('exp-old'), isNull);

      final rows = await cursorRows();
      expect(rows.single.key, 'pull');
      expect(rows.single.cursor, isNull);
    });

    test('pulled row does not overwrite a locally-dirty row with equal '
        'updatedAt', () async {
      await seedExpense(
        id: 'exp-loc',
        amountMinor: 999,
        note: 'mine',
        occurredAt: t0,
        pendingSync: true,
        updatedAt: t2,
      );
      // results=[] leaves the row dirty through the push phase (the real
      // trigger for this guard is a mutation landing mid-cycle); the pull
      // then arrives carrying the server's same-instant version.
      final m = mockSync(
        onPush: (_) => [],
        onPull: (_) => pullPage(expenses: [
          serverExpense(id: 'exp-loc', updatedAt: t2, amountMinor: 100),
        ]),
      );
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      final local = (await expenseById('exp-loc'))!;
      expect(local.amountMinor, 999);
      expect(local.note, 'mine');
      expect(local.pendingSync, isTrue);
    });

    test('reconcile purges clean categories missing server-side and nulls '
        'their references; dirty ones survive', () async {
      await seedCategory(id: 'cat-clean');
      await seedCategory(id: 'cat-dirty', pendingSync: true);
      await seedExpense(id: 'exp-1', categoryId: 'cat-clean', occurredAt: t0);
      await db.into(db.budgets).insert(
            BudgetsCompanion.insert(
              id: 'bgt-1',
              periodType: 'month',
              amountMinor: 50000,
              categoryId: Value('cat-clean'),
              createdAt: t0,
            ),
          );
      final m = mockSync(
        serverCategories: [serverCategory(id: 'cat-dirty', updatedAt: t0)],
      );
      final engine = SyncEngine(db, m.api);

      await engine.runCycle();

      // cat-dirty survived (it flushed via push and the server still lists
      // it); cat-clean was hard-deleted elsewhere → purged locally.
      final cats = await db.select(db.categories).get();
      expect(cats.map((c) => c.id), ['cat-dirty']);

      expect((await expenseById('exp-1'))!.categoryId, isNull);
      final budget = await (db.select(db.budgets)
            ..where((b) => b.id.equals('bgt-1')))
          .getSingle();
      expect(budget.categoryId, isNull);
    });

    test('forceResync(wipeLocalData) pushes dirty rows best-effort first, '
        'then wipes tables and clears the cursor', () async {
      await seedCategory(id: 'cat-1');
      await seedExpense(id: 'exp-clean', occurredAt: t0);
      await seedExpense(
        id: 'exp-dirty',
        pendingSync: true,
        occurredAt: t0,
        updatedAt: t2,
      );
      await db.into(db.syncState).insertOnConflictUpdate(
            SyncStateCompanion.insert(key: 'pull', cursor: Value('old-c')),
          );
      final m = mockSync(
        serverCategories: [serverCategory(id: 'cat-1', updatedAt: t0)],
      );
      final engine = SyncEngine(db, m.api);

      await engine.forceResync(wipeLocalData: true);

      // Dirty row salvaged best-effort before the wipe.
      expect(m.pushBodies, hasLength(1));
      expect(
        (m.pushBodies.single['expenses'] as List).map((e) => e['id']),
        ['exp-dirty'],
      );

      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await db.select(db.categories).get(), isEmpty);
      expect(await cursorRows(), isEmpty);
    });

    test('429 on push retries with backoff and succeeds', () async {
      await seedExpense(id: 'exp-1', pendingSync: true, occurredAt: t0);
      var pushCalls = 0;
      final pushBodies = <Map<String, dynamic>>[];
      final api = apiWith((req) async {
        switch (req.url.path) {
          case '/api/sync/push':
            pushCalls++;
            if (pushCalls == 1) {
              return jsonRes(
                {
                  'error': {'code': 'RATE_LIMITED', 'message': 'slow down'},
                },
                status: 429,
              );
            }
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            pushBodies.add(body);
            return jsonRes({'results': pushResults(['exp-1'])});
          case '/api/categories':
            return jsonRes(const []);
        }
        return http.Response('not found', 404);
      });
      final engine = SyncEngine(db, api);

      await engine.runCycle();

      // One retry after the rate limit; flags clear only on success.
      expect(pushCalls, 2);
      expect((await expenseById('exp-1'))!.pendingSync, isFalse);
      expect(pushBodies.single['expenses'], isNotEmpty);
    });
  });
}
