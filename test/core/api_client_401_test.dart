import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault_app/core/network/api_client.dart';

/// In-memory stand-in for secure storage; lets tests assert what ApiClient
/// clears when a session dies.
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
  const tokenKey = 'better-auth.session_token';
  const token = 'stale-token';

  Future<ApiClient> clientFor(
    Future<http.Response> Function(http.Request) handler, {
    bool seedToken = true,
  }) async {
    final storage = _FakeStorage();
    if (seedToken) storage.values[tokenKey] = token;
    return ApiClient(client: MockClient(handler), storage: storage);
  }

  test('401 on a protected route clears the token and fires the callback',
      () async {
    var unauthorized = 0;
    final api = await clientFor((req) async {
      return http.Response(
        '{"error":{"code":"UNAUTHORIZED","message":"nope"}}',
        401,
        headers: {'content-type': 'application/json'},
      );
    });
    api.onUnauthorized = () => unauthorized++;

    await expectLater(api.listBudgets(), throwsA(isA<ApiException>()));
    expect(unauthorized, 1);
    expect(await api.readToken(), isNull);
  });

  test('401 on an auth route keeps the token and never fires the callback',
      () async {
    var unauthorized = 0;
    final api = await clientFor((req) async {
      return http.Response('{"code":"INVALID_PASSWORD"}', 401,
          headers: {'content-type': 'application/json'});
    });
    api.onUnauthorized = () => unauthorized++;

    await expectLater(
      api.signInEmail(email: 'a@b.c', password: 'wrong'),
      throwsA(isA<ApiException>()),
    );
    expect(unauthorized, 0);
    expect(await api.readToken(), token);
  });

  test('protected-route 401 with no listener still clears the token',
      () async {
    final api = await clientFor((req) async {
      return http.Response('', 401);
    });

    await expectLater(api.listBudgets(), throwsA(isA<ApiException>()));
    expect(await api.readToken(), isNull);
  });
}
