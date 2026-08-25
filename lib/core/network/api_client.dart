import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_base_url.dart';

const String _tokenKey = 'better-auth.session_token';
const Duration _timeout = Duration(seconds: 15);

/// Failure on an API route. Auth endpoints speak Better Auth's own JSON, not
/// the app error envelope, so `code`/`message` stay null there; non-auth
/// routes populate them from `{ "error": { code, message } }`.
class ApiException implements Exception {
  ApiException(this.statusCode, {this.code, this.message});

  final int statusCode;
  final String? code;

  /// `error.message` from the app error envelope on non-auth routes;
  /// `null` for auth routes (Better Auth bodies) and empty payloads.
  final String? message;

  @override
  String toString() => 'ApiException($statusCode)';
}

/// One page of the incremental `/api/sync/pull` delta. Both tables share a
/// watermark; tombstoned expenses are included, categories never are.
class SyncPullPage {
  SyncPullPage({
    required this.expenses,
    required this.categories,
    required this.nextCursor,
  });

  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> categories;

  /// `null` means the delta is fully drained.
  final String? nextCursor;
}

/// Per-item outcome of `/api/sync/push`. `conflict-lost` still means the
/// server holds the authoritative row (equal timestamps favor server), so
/// callers treat it like `accepted`.
class SyncPushResult {
  SyncPushResult(this.id, this.outcome);

  final String id;
  final String outcome;
}

/// Thin client for the Vault API. Owns the session token: persists the
/// Better Auth token in secure storage and replays it as
/// `Authorization: Bearer` on every request (server runs the Better Auth
/// bearer plugin). Rotated tokens arrive in the `set-auth-token` response
/// header and are captured automatically.
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _storage;

  /// Called after a protected route answers `401` (stored session revoked or
  /// expired): the token is already cleared by then. Attach a listener to
  /// bounce the user to sign-in. Never fires for `/api/auth/*` routes, where
  /// `401` just means rejected credentials.
  void Function()? onUnauthorized;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Uri _uri(String path) => Uri.parse('$apiBaseUrl$path');

  String _bareDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<Map<String, String>> _headers() async {
    final token = await readToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Persist a freshly minted or rotated session token from the
  /// `set-auth-token` response header (emitted by the server's Better Auth
  /// bearer plugin on sign-up/sign-in and whenever the session rotates, e.g.
  /// after change-password). Awaited by every request helper so the fresh
  /// token is durably stored before the caller can fire another request.
  Future<void> _captureToken(http.Response res) async {
    final token = res.headers['set-auth-token'];
    if (token != null && token.isNotEmpty) {
      await _storage.write(key: _tokenKey, value: token);
    }
  }

  /// A `401` from a protected route means the stored session is dead:
  /// clear it immediately and notify [onUnauthorized] so the app can
  /// redirect. Auth-route `401`s (bad password, wrong current password)
  /// leave the stored token alone — the caller surfaces the error instead.
  Future<void> _handleUnauthorized(Uri uri, http.Response res) async {
    if (res.statusCode != 401 || uri.path.startsWith('/api/auth/')) return;
    await clearToken();
    onUnauthorized?.call();
  }

  /// `null` body and JSON `null` both mean "no payload".
  Map<String, dynamic>? _decodeBody(http.Response res) {
    if (res.body.isEmpty) return null;
    return jsonDecode(res.body) as Map<String, dynamic>?;
  }

  /// Error bodies may be non-JSON (CDN/proxy HTML pages); callers only want
  /// the envelope message when one exists.
  Map<String, dynamic>? _decodeErrorBody(http.Response res) {
    try {
      return _decodeBody(res);
    } catch (_) {
      return null;
    }
  }

  String? _envelopeMessage(Map<String, dynamic>? body) =>
      body?['error'] is Map<String, dynamic>
          ? (body!['error'] as Map<String, dynamic>)['message'] as String?
          : null;

  Future<http.Response> _get(Uri uri, Map<String, String> headers) async {
    final res = await _client.get(uri, headers: headers).timeout(_timeout);
    await _captureToken(res);
    await _handleUnauthorized(uri, res);
    return res;
  }

  Future<http.Response> _post(
    Uri uri,
    Map<String, String> headers, {
    Object? body,
  }) async {
    final res =
        await _client.post(uri, headers: headers, body: body).timeout(_timeout);
    await _captureToken(res);
    await _handleUnauthorized(uri, res);
    return res;
  }

  Future<void> _send(
    Future<http.Response> Function(Map<String, String> headers) fn,
  ) async {
    final res = await fn(await _headers());
    if (res.statusCode != 200) throw ApiException(res.statusCode);
  }

  /// App-envelope routes: on failure parse `{ "error": { code, message } }`
  /// so callers can surface the server's message. Returns the decoded body
  /// (`null` for empty bodies, e.g. `204` deletes).
  Future<Object?> _sendApp(
    Future<http.Response> Function(Map<String, String> headers) fn,
  ) async {
    final res = await fn(await _headers());
    if (res.statusCode >= 400) {
      Map<String, dynamic>? body;
      try {
        body = _decodeBody(res);
      } catch (_) {}
      final err = body?['error'];
      throw ApiException(
        res.statusCode,
        code: err is Map<String, dynamic> ? err['code'] as String? : null,
        message:
            err is Map<String, dynamic> ? err['message'] as String? : null,
      );
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  Future<http.Response> _delete(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final res = await _client.delete(uri, headers: headers).timeout(_timeout);
    await _captureToken(res);
    await _handleUnauthorized(uri, res);
    return res;
  }

  Future<http.Response> _patch(
    Uri uri,
    Map<String, String> headers, {
    Object? body,
  }) async {
    final res = await _client
        .patch(uri, headers: headers, body: body)
        .timeout(_timeout);
    await _captureToken(res);
    await _handleUnauthorized(uri, res);
    return res;
  }

  // ── Budgets (/api/budgets — online-only, hard delete) ─────────────────

  Future<List<Map<String, dynamic>>> listBudgets() async {
    final body = await _sendApp(
        (h) => _get(_uri('/api/budgets'), h..remove('Content-Type')));
    return (body! as List).cast<Map<String, dynamic>>();
  }

  /// Server mints the budget id; returns the created row.
  Future<Map<String, dynamic>> createBudget({
    required String periodType,
    required int amountMinor,
    String? categoryId,
  }) async {
    final body = await _sendApp((h) => _post(
          _uri('/api/budgets'),
          h,
          body: jsonEncode({
            'periodType': periodType,
            'amountMinor': amountMinor,
            'categoryId': ?categoryId,
          }),
        ));
    return body! as Map<String, dynamic>;
  }

  /// PATCH with the full row (all fields optional per contract; `categoryId`
  /// explicitly nullable — null clears to overall).
  Future<Map<String, dynamic>> updateBudget(
    String id, {
    required String periodType,
    required int amountMinor,
    String? categoryId,
  }) async {
    final body = await _sendApp((h) => _patch(
          _uri('/api/budgets/$id'),
          h,
          body: jsonEncode({
            'periodType': periodType,
            'amountMinor': amountMinor,
            'categoryId': categoryId,
          }),
        ));
    return body! as Map<String, dynamic>;
  }

  Future<void> deleteBudget(String id) async {
    await _sendApp((h) => _delete(_uri('/api/budgets/$id'), h));
  }

  // ── Recurring (/api/recurring — online-only, like budgets) ─────────────

  Future<List<Map<String, dynamic>>> listRecurring() async {
    final body = await _sendApp(
        (h) => _get(_uri('/api/recurring'), h..remove('Content-Type')));
    return (body! as List).cast<Map<String, dynamic>>();
  }

  /// Server mints the rule id; returns the created row. [anchorDate] goes on
  /// the wire as bare `YYYY-MM-DD` (contract §4); `interval` defaults to 1.
  Future<Map<String, dynamic>> createRecurring({
    required String name,
    required int amountMinor,
    required String frequency,
    required DateTime anchorDate,
    int interval = 1,
    String? categoryId,
  }) async {
    final body = await _sendApp((h) => _post(
          _uri('/api/recurring'),
          h,
          body: jsonEncode({
            'name': name,
            'amountMinor': amountMinor,
            'frequency': frequency,
            'anchorDate': _bareDate(anchorDate),
            'interval': interval,
            'categoryId': ?categoryId,
          }),
        ));
    return body! as Map<String, dynamic>;
  }

  /// PATCH subset + `paused`. `categoryId` is only sent when non-null: the
  /// contract documents null-clearing for expenses and budgets but not for
  /// recurring, so an explicit null risks a 422.
  Future<Map<String, dynamic>> updateRecurring(
    String id, {
    String? name,
    int? amountMinor,
    String? frequency,
    DateTime? anchorDate,
    int? interval,
    String? categoryId,
    bool? paused,
  }) async {
    final body = await _sendApp((h) => _patch(
          _uri('/api/recurring/$id'),
          h,
          body: jsonEncode({
            'name': ?name,
            'amountMinor': ?amountMinor,
            'frequency': ?frequency,
            if (anchorDate != null) 'anchorDate': _bareDate(anchorDate),
            'interval': ?interval,
            'categoryId': ?categoryId,
            'paused': ?paused,
          }),
        ));
    return body! as Map<String, dynamic>;
  }

  Future<void> deleteRecurring(String id) async {
    await _sendApp((h) => _delete(_uri('/api/recurring/$id'), h));
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

  /// `POST /api/auth/change-password` — rotates the session token. The
  /// rotated token is captured from the `set-auth-token` header (awaited)
  /// before this returns, so every later request already carries the fresh
  /// session.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool revokeOtherSessions = false,
  }) {
    return _send((h) => _post(
          _uri('/api/auth/change-password'),
          h,
          body: jsonEncode({
            'currentPassword': currentPassword,
            'newPassword': newPassword,
            'revokeOtherSessions': revokeOtherSessions,
          }),
        ));
  }

  /// Parsed `{session, user}` JSON, or `null` when unauthenticated
  /// (get-session answers `200` with a literal `null` body).
  Future<Map<String, dynamic>?> getSession() async {
    final res = await _get(_uri('/api/auth/get-session'),
        await _headers()..remove('Content-Type'));
    if (res.statusCode == 401) {
      // Auth-route 401s skip _handleUnauthorized's auto-clear; an expired
      // boot session should still drop the dead token immediately.
      await clearToken();
      return null;
    }
    if (res.statusCode != 200) throw ApiException(res.statusCode);
    return _decodeBody(res);
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
      throw ApiException(
        res.statusCode,
        message: _envelopeMessage(_decodeErrorBody(res)),
      );
    }
  }

  // ── Sync (/api/sync — expenses + categories only) ──────────────────────

  /// Drains one page of the incremental delta. First-ever sync omits
  /// [cursor]; loop until `nextCursor` is null.
  Future<SyncPullPage> pullSync({required int limit, String? cursor}) async {
    final body = await _sendApp((h) => _get(
          _uri('/api/sync/pull').replace(
            queryParameters: {'limit': '$limit', 'cursor': ?cursor},
          ),
          h..remove('Content-Type'),
        ));
    final json = body! as Map<String, dynamic>;
    return SyncPullPage(
      expenses: (json['expenses'] as List).cast<Map<String, dynamic>>(),
      categories: (json['categories'] as List).cast<Map<String, dynamic>>(),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  /// Uploads whole-row LWW payloads (≤500 per array; both optional). Batch
  /// is atomic and categories apply before expenses, so same-batch
  /// references are safe.
  Future<List<SyncPushResult>> pushSync({
    List<Map<String, dynamic>> categories = const [],
    List<Map<String, dynamic>> expenses = const [],
  }) async {
    if (categories.isEmpty && expenses.isEmpty) return const [];
    final body = await _sendApp(
      (h) => _post(
        _uri('/api/sync/push'),
        h,
        body: jsonEncode({
          'categories': categories,
          'expenses': expenses,
        }),
      ),
    );
    return [
      for (final r in (body! as Map<String, dynamic>)['results'] as List)
        SyncPushResult(
          (r as Map<String, dynamic>)['id'] as String,
          r['outcome'] as String,
        ),
    ];
  }

  /// Full server category list, createdAt asc then name asc. Used by the
  /// sync engine to reconcile deletions that never tombstone.
  Future<List<Map<String, dynamic>>> listCategories() async {
    final body = await _sendApp(
        (h) => _get(_uri('/api/categories'), h..remove('Content-Type')));
    return (body! as List).cast<Map<String, dynamic>>();
  }
}

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
