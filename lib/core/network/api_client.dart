import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_base_url.dart';

const String _tokenKey = 'better-auth.session_token';
const Duration _timeout = Duration(seconds: 15);

/// Failure on an auth route, driven purely by HTTP status code.
/// Auth endpoints speak Better Auth's own JSON, not the app error envelope,
/// so the response body carries nothing we can rely on here.
class ApiException implements Exception {
  ApiException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'ApiException($statusCode)';
}

/// Thin client for the Vault API. Owns the cookie jar: persists
/// `better-auth.session_token` in secure storage and replays it verbatim as
/// the `Cookie:` header on every request (the server has no bearer support).
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  Future<Map<String, String>> _headers() async {
    final token = await readToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Cookie': '$_tokenKey=$token',
    };
  }

  /// Capture the session cookie from an auth response into secure storage.
  void _captureCookie(http.Response res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
    final match =
        RegExp('${RegExp.escape(_tokenKey)}=([^;]+)').firstMatch(raw);
    final value = match?.group(1);
    if (value != null && value.isNotEmpty) {
      _storage.write(key: _tokenKey, value: value);
    }
  }

  /// `null` body and JSON `null` both mean "no payload".
  Map<String, dynamic>? _decodeBody(http.Response res) {
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }

  Future<http.Response> _get(Uri uri, Map<String, String> headers) =>
      _client.get(uri, headers: headers).timeout(_timeout);

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> headers, {
    Object? body,
  }) =>
      _client.post(uri, headers: headers, body: body).timeout(_timeout);

  Future<void> _send(
    Future<http.Response> Function(Map<String, String> headers) fn,
  ) async {
    final res = await fn(await _headers());
    if (res.statusCode != 200) throw ApiException(res.statusCode);
    _captureCookie(res);
  }

  Future<void> signUpEmail({
    required String name,
    required String email,
    required String password,
  }) {
    return _send((h) => _post(
          _uri('/api/auth/sign-up/email'),
          h,
          body: jsonEncode({
            'name': name,
            'email': email,
            'password': password,
          }),
        ));
  }

  Future<void> signInEmail({
    required String email,
    required String password,
  }) {
    return _send((h) => _post(
          _uri('/api/auth/sign-in/email'),
          h,
          body: jsonEncode({
            'email': email,
            'password': password,
          }),
        ));
  }

  Future<void> signOut() {
    return _send((h) => _post(_uri('/api/auth/sign-out'), h));
  }

  /// Parsed `{session, user}` JSON, or `null` when unauthenticated
  /// (get-session answers `200` with a literal `null` body).
  Future<Map<String, dynamic>?> getSession() async {
    final res = await _get(_uri('/api/auth/get-session'),
        await _headers()..remove('Content-Type'));
    if (res.statusCode == 401) return null;
    if (res.statusCode != 200) throw ApiException(res.statusCode);
    return _decodeBody(res);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
