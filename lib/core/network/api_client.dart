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
  ApiException(this.statusCode, [this.message]);

  final int statusCode;

  /// `error.message` from the app error envelope on non-auth routes;
  /// `null` for auth routes (Better Auth bodies) and empty payloads.
  final String? message;

  @override
  String toString() => 'ApiException($statusCode)';
}

/// Expense DRAFT returned by `/api/chat/parse`. The server saves nothing;
/// the client turns it into a real expense via its own POST.
class ParsedDraft {
  ParsedDraft({
    required this.amountMinor,
    required this.categoryGuess,
    required this.categoryId,
    required this.occurredAtGuess,
    required this.note,
  });

  final int amountMinor;
  final String? categoryGuess;
  final String? categoryId;

  /// Bare date (`YYYY-MM-DD`) resolved in the user's timezone.
  final String occurredAtGuess;
  final String? note;

  factory ParsedDraft.fromJson(Map<String, dynamic> json) => ParsedDraft(
        amountMinor: (json['amountMinor'] as num).toInt(),
        categoryGuess: json['categoryGuess'] as String?,
        categoryId: json['categoryId'] as String?,
        occurredAtGuess: json['occurredAtGuess'] as String,
        note: json['note'] as String?,
      );
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

  String? _envelopeMessage(Map<String, dynamic>? body) =>
      body?['error'] is Map<String, dynamic>
          ? (body!['error'] as Map<String, dynamic>)['message'] as String?
          : null;

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

  /// `POST /api/chat/parse` — natural-language phrase in, one expense draft
  /// out. Nothing is persisted server-side. Errors: 502 parser failed,
  /// 422 validation, 429 rate limited (shares the auth bucket).
  Future<ParsedDraft> parseExpense(String message) async {
    final res = await _post(
      _uri('/api/chat/parse'),
      await _headers(),
      body: jsonEncode({'message': message}),
    );
    final body = _decodeBody(res);
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, _envelopeMessage(body));
    }
    return ParsedDraft.fromJson(body!);
  }

  /// `POST /api/expenses` — [id] MUST be a client-minted UUID so retries
  /// dedupe (same id + same payload replays idempotently as `200`).
  Future<void> createExpense({
    required String id,
    required int amountMinor,
    DateTime? occurredAt,
    String? categoryId,
    String? note,
  }) async {
    final res = await _post(
      _uri('/api/expenses'),
      await _headers(),
      body: jsonEncode({
        'id': id,
        'amountMinor': amountMinor,
        if (occurredAt != null) 'occurredAt': occurredAt.toUtc().toIso8601String(),
        'categoryId': ?categoryId,
        'note': ?note,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw ApiException(res.statusCode, _envelopeMessage(_decodeBody(res)));
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
