import 'dart:async';

import 'package:drift/drift.dart';

import '../../core/network/api_client.dart';
import '../db/vault_database.dart';

/// Offline-first sync for expenses + categories (the only two tables the
/// `/api/sync` surface covers). Every cycle is push-then-pull:
///
/// 1. **Push** — rows flagged `pendingSync` go up as whole-row
///    last-write-wins payloads. Both arrays ride one atomic batch per chunk
///    (the server applies categories before expenses, so same-batch
///    references are safe); flags clear only on an accepted outcome, and
///    client-minted UUIDs make retries idempotent.
/// 2. **Pull** — the cursor-based delta drains page by page until
///    `nextCursor` is null, persisting the cursor after every page so a
///    killed process resumes where it stopped. Pulled tombstones delete
///    local expense rows outright; conflicts resolve silently LWW.
/// 3. **Reconcile** — categories never tombstone across devices (hard
///    deletes), so each cycle fetches the server list and removes local
///    rows absent from it, nulling `categoryId` references.
///
/// Transient failures (429/5xx/network) back off exponentially; permanent
/// failures abort the cycle silently — nothing here ever surfaces UI.
class SyncEngine {
  SyncEngine(this._db, this._api);

  final VaultDatabase _db;
  final ApiClient _api;

  static const _pullPageSize = 50;
  static const _pushChunkSize = 500;
  static const _maxAttempts = 4;
  static const _backoffBase = Duration(milliseconds: 800);
  static const _cursorKey = 'pull';

  bool _running = false;
  bool _queued = false;

  /// Runs one full cycle. Reentrant calls while a cycle is in flight are
  /// coalesced into exactly one follow-up run, so trigger storms collapse.
  Future<void> runCycle() async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      await _cycle();
    } catch (_) {
      // Silent by design — conflicts and dead networks must never surface
      // dialogs; the next trigger retries.
    } finally {
      _running = false;
    }
    if (_queued) {
      _queued = false;
      await runCycle();
    }
  }

  /// Clears the pull cursor so the next cycle re-pulls full history.
  /// With [wipeLocalData] also drops the local synced tables (expenses,
  /// categories) — budgets stay, they are an online-only cache. Exposed for
  /// a future Settings entry; no UI yet.
  Future<void> forceResync({bool wipeLocalData = false}) async {
    await (_db.delete(_db.syncState)..where((s) => s.key.equals(_cursorKey)))
        .go();
    if (wipeLocalData) {
      await _db.transaction(() async {
        await _db.expenses.delete().go();
        await _db.categories.delete().go();
      });
    }
  }

  Future<void> _cycle() async {
    await _pushDirty();
    await _drainPull();
    await _reconcileCategories();
  }

  // ── Push ──────────────────────────────────────────────────────────────

  Future<void> _pushDirty() async {
    final dirtyCategories =
        await (_db.select(_db.categories)..where((c) => c.pendingSync)).get();
    final dirtyExpenses =
        await (_db.select(_db.expenses)..where((e) => e.pendingSync)).get();

    for (var i = 0;
        i < dirtyCategories.length || i < dirtyExpenses.length;
        i += _pushChunkSize) {
      final catChunk =
          dirtyCategories.skip(i).take(_pushChunkSize).toList();
      final expChunk = dirtyExpenses.skip(i).take(_pushChunkSize).toList();
      final results = await _withBackoff(
        () => _api.pushSync(
          categories: [for (final c in catChunk) _categoryPayload(c)],
          expenses: [for (final e in expChunk) _expensePayload(e)],
        ),
      );
      // `conflict-lost` still means the server holds the authoritative row,
      // so both outcomes clear the flag.
      final settled = results.map((r) => r.id).toSet();

      await _db.transaction(() async {
        for (final c in catChunk) {
          if (!settled.contains(c.id)) continue;
          if (c.deletedAt != null) {
            await _purgeCategory(c.id);
          } else {
            await (_db.update(_db.categories)
                  ..where((row) => row.id.equals(c.id)))
                .write(const CategoriesCompanion(pendingSync: Value(false)));
          }
        }
        for (final e in expChunk) {
          if (!settled.contains(e.id)) continue;
          if (e.deletedAt != null) {
            await (_db.delete(_db.expenses)..where((row) => row.id.equals(e.id)))
                .go();
          } else {
            await (_db.update(_db.expenses)
                  ..where((row) => row.id.equals(e.id)))
                .write(const ExpensesCompanion(pendingSync: Value(false)));
          }
        }
      });
    }
  }

  Map<String, dynamic> _categoryPayload(CategoryRow c) => {
        'id': c.id,
        'updatedAt': _iso(c.updatedAt),
        'name': c.name,
        if (c.deletedAt != null) 'deletedAt': _iso(c.deletedAt!),
      };

  Map<String, dynamic> _expensePayload(ExpenseRow e) => {
        'id': e.id,
        'updatedAt': _iso(e.updatedAt),
        'amountMinor': e.amountMinor,
        'occurredAt': _iso(e.occurredAt),
        'categoryId': ?e.categoryId,
        'note': ?e.note,
        if (e.deletedAt != null) 'deletedAt': _iso(e.deletedAt!),
      };

  // ── Pull ──────────────────────────────────────────────────────────────

  Future<void> _drainPull() async {
    var cursor = await _readCursor();
    while (true) {
      final page = await _withBackoff(
        () => _api.pullSync(limit: _pullPageSize, cursor: cursor),
      );
      final nextCursor = page.nextCursor;
      await _db.transaction(() async {
        for (final json in page.categories) {
          await _applyPulledCategory(json);
        }
        for (final json in page.expenses) {
          await _applyPulledExpense(json);
        }
        await _writeCursor(nextCursor);
      });
      if (nextCursor == null) break;
      cursor = nextCursor;
    }
  }

  Future<String?> _readCursor() async {
    final query = _db.select(_db.syncState)
      ..where((s) => s.key.equals(_cursorKey));
    return (await query.getSingleOrNull())?.cursor;
  }

  Future<void> _writeCursor(String? cursor) async {
    await _db.into(_db.syncState).insertOnConflictUpdate(
          SyncStateCompanion.insert(key: _cursorKey, cursor: Value(cursor)),
        );
  }

  /// Server wins unless a locally-dirty row is strictly newer — equal
  /// timestamps favor the server on push, so they favor it here too.
  Future<void> _applyPulledExpense(Map<String, dynamic> json) async {
    final id = json['id'] as String;
    final updatedAt = DateTime.parse(json['updatedAt'] as String);
    final deletedAt = json['deletedAt'] as String?;
    final local =
        await (_db.select(_db.expenses)..where((e) => e.id.equals(id)))
            .getSingleOrNull();
    if (local != null &&
        local.pendingSync &&
        !updatedAt.isAfter(local.updatedAt)) {
      return; // Our un-pushed write is at least as new; push will decide.
    }
    if (deletedAt != null) {
      await (_db.delete(_db.expenses)..where((e) => e.id.equals(id))).go();
      return;
    }
    // ponytail: occurrenceDate has no column yet; the recurring-badge
    // ticket owns that migration — occurrence rows sync as plain expenses.
    await _db.into(_db.expenses).insertOnConflictUpdate(
          ExpensesCompanion.insert(
            id: id,
            amountMinor: (json['amountMinor'] as num).toInt(),
            categoryId: Value(json['categoryId'] as String?),
            occurredAt: DateTime.parse(json['occurredAt'] as String),
            note: Value(json['note'] as String?),
            recurringId: Value(json['recurringDefinitionId'] as String?),
            createdAt: Value(
                DateTime.parse(json['createdAt'] as String)),
            updatedAt: Value(updatedAt),
          ),
        );
  }

  Future<void> _applyPulledCategory(Map<String, dynamic> json) async {
    final id = json['id'] as String;
    final local =
        await (_db.select(_db.categories)..where((c) => c.id.equals(id)))
            .getSingleOrNull();
    // Never resurrect a row we are deleting or renaming locally.
    if (local != null && local.pendingSync) return;
    await _db.into(_db.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: id,
            name: json['name'] as String,
            updatedAt: Value(DateTime.parse(json['updatedAt'] as String)),
            pendingSync: const Value(false),
          ),
        );
  }

  // ── Reconcile (category hard deletes never propagate via pull) ────────

  Future<void> _reconcileCategories() async {
    final server = await _withBackoff(_api.listCategories);
    final serverIds = {for (final c in server) c['id'] as String};
    // Dirty rows were flushed by _pushDirty (or aborted the cycle), so any
    // clean local row absent from the server was deleted elsewhere.
    final locals =
        await (_db.select(_db.categories)..where((c) => c.deletedAt.isNull()))
            .get();
    for (final row in locals) {
      if (!serverIds.contains(row.id)) await _purgeCategory(row.id);
    }
  }

  /// Removes an accepted-deleted category locally and clears every
  /// reference to it (idempotent).
  Future<void> _purgeCategory(String id) async {
    await (_db.update(_db.expenses)..where((e) => e.categoryId.equals(id)))
        .write(const ExpensesCompanion(categoryId: Value(null)));
    await (_db.update(_db.budgets)..where((b) => b.categoryId.equals(id)))
        .write(const BudgetsCompanion(categoryId: Value(null)));
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  }

  // ── Shared helpers ────────────────────────────────────────────────────

  /// Retries transient failures (429/5xx/network/timeout) with exponential
  /// backoff; anything else rethrows immediately to abort the cycle.
  Future<T> _withBackoff<T>(Future<T> Function() op) async {
    var delay = _backoffBase;
    for (var attempt = 1;; attempt++) {
      try {
        return await op();
      } catch (error) {
        final transient =
            error is! ApiException || error.statusCode == 429 ||
                error.statusCode >= 500;
        if (!transient || attempt >= _maxAttempts) rethrow;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  String _iso(DateTime value) => value.toUtc().toIso8601String();
}
