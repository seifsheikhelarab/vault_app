import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault_app/core/network/api_client.dart';
import 'package:vault_app/data/db/vault_database.dart';
import 'package:vault_app/data/repositories/recurring_repository.dart';

/// In-memory stand-in for secure storage so no platform channel is touched.
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

/// Server-shaped `/api/recurring` row (contract §8): every field always
/// returned, anchorDate an ISO midnight instant.
Map<String, dynamic> _serverRow({
  String id = 'rule-1',
  String name = 'Rent',
  int amountMinor = 750000,
  String frequency = 'monthly',
  int interval = 1,
  String? categoryId,
  bool paused = false,
}) =>
    {
      'id': id,
      'userId': 'user-1',
      'name': name,
      'amountMinor': amountMinor,
      'currency': 'EGP',
      'categoryId': categoryId,
      'frequency': frequency,
      'interval': interval,
      'anchorDate': '2026-01-01T00:00:00.000Z',
      'nextRunAt': '2026-09-01T00:00:00.000Z',
      'paused': paused,
      'lastMaterializedAt': null,
      'createdAt': '2025-12-31T10:00:00.000Z',
      'updatedAt': '2025-12-31T10:00:00.000Z',
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  late VaultDatabase db;
  late List<http.Request> requests;
  late ApiClient api;
  late RecurringRepository repo;

  setUp(() {
    db = VaultDatabase(NativeDatabase.memory());
    requests = [];
    api = ApiClient(
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (request.method == 'GET' && path == '/api/recurring') {
          return _json([_serverRow()]);
        }
        if (request.method == 'POST' && path == '/api/recurring') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return _json(_serverRow(
            id: 'rule-new',
            name: body['name'] as String,
            amountMinor: body['amountMinor'] as int,
            frequency: body['frequency'] as String,
            interval: body['interval'] as int? ?? 1,
            categoryId: body['categoryId'] as String?,
          ), 201);
        }
        if (request.method == 'PATCH' &&
            path.startsWith('/api/recurring/')) {
          return _json(_serverRow(paused: true));
        }
        if (request.method == 'DELETE' &&
            path.startsWith('/api/recurring/')) {
          return http.Response('', 204);
        }
        return _json({
          'error': {'code': 'NOT_FOUND', 'message': 'Not found'}
        }, 404);
      }),
      storage: _FakeStorage(),
    );
    repo = RecurringRepository(db, api);
  });

  tearDown(() => db.close());

  group('recurring repository', () {
    test('create posts bare-date payload then caches the server row',
        () async {
      final row = await repo.create(
        name: 'Gym',
        amountMinor: 30000,
        frequency: 'monthly',
        anchorDate: DateTime(2026, 8, 24),
        online: true,
      );

      expect(row.id, 'rule-new');
      expect(requests.single.method, 'POST');
      final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(sent['name'], 'Gym');
      expect(sent['amountMinor'], 30000);
      expect(sent['frequency'], 'monthly');
      expect(sent['anchorDate'], '2026-08-24');
      expect(sent['interval'], 1);

      final cached = await repo.watchAll().first;
      expect(cached, hasLength(1));
      expect(cached.single.name, 'Gym');
    });

    test('offline write refuses before any HTTP call', () async {
      await expectLater(
        () => repo.create(
          name: 'Gym',
          amountMinor: 1,
          frequency: 'daily',
          anchorDate: DateTime(2026, 8, 24),
          online: false,
        ),
        throwsA(isA<RecurringOfflineException>()),
      );
      await expectLater(
        () => repo.update('rule-1', paused: true, online: false),
        throwsA(isA<RecurringOfflineException>()),
      );
      await expectLater(
        () => repo.delete('rule-1', online: false),
        throwsA(isA<RecurringOfflineException>()),
      );
      expect(requests, isEmpty);
    });

    test('refresh replaces the cache wholesale from the server list',
        () async {
      await db.into(db.recurrings).insert(RecurringsCompanion.insert(
            id: 'stale',
            name: 'Stale',
            amountMinor: 1,
            frequency: 'daily',
            anchorDate: DateTime(2026, 1, 1),
            nextRunAt: DateTime(2026, 1, 2),
            createdAt: DateTime(2026, 1, 1),
          ));

      await repo.refresh();

      final cached = await repo.watchAll().first;
      expect(cached.map((r) => r.id), ['rule-1']);
    });

    test('update patches subset, honors paused flag, refreshes cache',
        () async {
      await repo.refresh();
      requests.clear();

      await repo.update('rule-1', paused: true, online: true);

      final patch = requests.single;
      expect(patch.method, 'PATCH');
      expect(jsonDecode(patch.body), {'paused': true});
      expect((await repo.watchAll().first).single.paused, isTrue);
    });

    test('delete removes server row and local cache entry', () async {
      await repo.refresh();
      requests.clear();

      await repo.delete('rule-1', online: true);

      expect(requests.single.method, 'DELETE');
      expect(await repo.watchAll().first, isEmpty);
    });

    test('seeded expense rows stay badge-less until sync fills recurringId',
        () async {
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            id: 'e1',
            amountMinor: 750000,
            occurredAt: DateTime(2026, 9, 1),
          ));

      final row = await (db.select(db.expenses)
            ..where((e) => e.id.equals('e1')))
          .getSingle();
      expect(row.recurringId, isNull);

      await (db.update(db.expenses)..where((e) => e.id.equals('e1')))
          .write(const ExpensesCompanion(recurringId: Value('rule-1')));
      expect(
        (await (db.select(db.expenses)).getSingle()).recurringId,
        'rule-1',
      );
    });
  });
}
