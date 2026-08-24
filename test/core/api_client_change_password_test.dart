import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vault_app/core/network/api_client.dart';

/// In-memory stand-in for secure storage; lets tests assert exactly what
/// ApiClient persists (the rotated-cookie path especially).
class _FakeStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

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
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

void main() {
  const tokenKey = 'better-auth.session_token';
  const oldToken = 'old-token';
  const newToken = 'rotated-token';

  Future<ApiClient> clientFor(http.Handler handler) async {
    final storage = _FakeStorage();
    storage.values[tokenKey] = oldToken;
    return ApiClient(
      client: MockClient(handler),
      storage: storage,
    );
  }

  Future<void> changePassword(ApiClient api) => api.changePassword(
        currentPassword: 'current-pass',
        newPassword: 'new-password-123',
        revokeOtherSessions: true,
      );

  test('success rotates the persisted session token', () async {
    http.Request? captured;
    final api = await clientFor((req) async {
      captured = req;
      return http.Response(
        jsonEncode({'status': true}),
        200,
        headers: {
          'content-type': 'application/json',
          'set-cookie':
              '$tokenKey=$newToken; Path=/; HttpOnly; SameSite=Lax',
        },
      );
    });

    await changePassword(api);

    // Request shape per contract.
    expect(captured!.url.path, '/api/auth/change-password');
    expect(captured!.headers['cookie'], '$tokenKey=$oldToken');
    expect(jsonDecode(captured!.body), {
      'currentPassword': 'current-pass',
      'newPassword': 'new-password-123',
      'revokeOtherSessions': true,
    });

    // The rotated cookie overwrote the stored one before the call returned.
    expect(await api.readToken(), newToken);
  });

  test('failure keeps the existing token and surfaces the status', () async {
    final api = await clientFor((req) async {
      return http.Response(jsonEncode({'code': 'INVALID_PASSWORD'}), 401,
          headers: {'content-type': 'application/json'});
    });

    await expectLater(changePassword(api), throwsA(isA<ApiException>()));
    expect(await api.readToken(), oldToken);
  });
}
