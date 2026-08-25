# AGENTS.md

Flutter client for Vault (expense tracker). The backend lives in a separate repo (`../Vault`).

## Backend contract — read first

`flutter-client.md` at repo root is the verified API contract (Better Auth + Cloudflare Worker). Read it before writing any networking/API code. Highest-signal gotchas:

- **Auth is bearer-token** (`Authorization: Bearer <token>`, Better Auth bearer plugin). Server also accepts cookies for web clients, but this app uses bearer exclusively. Token arrives via `set-auth-token` response header, lives in `flutter_secure_storage`, and rotates on sign-in/change-password.
- **Money**: integer minor units of EGP (piasters), JSON number, never string.
- **Expenses require client-minted UUID `id`** on create — enables idempotent retries and offline sync dedupe.
- Expenses/categories soft/hard delete semantics differ from budgets/recurring; only expenses+categories sync offline (`/api/sync`).
- Error envelope `{ "error": { code, message, issues? } }` applies to non-auth routes only; auth endpoints return Better Auth's own JSON — rely on status codes there.

## Commands

```
flutter pub get          # after pubspec changes
flutter analyze          # lint/typecheck
flutter test             # all tests
flutter test test/widget_test.dart --name "<substring>"   # single test
flutter run              # dev run (hot reload: r, hot restart: R)
```

Drift codegen via `dart run build_runner build --delete-conflicting-outputs` after editing `lib/data/db/vault_database.dart` — commit the regenerated `.g.dart`. No CI configured yet. Lints: `flutter_lints` defaults via `analysis_options.yaml`.

## Hard timeout policy

Every shell command MUST carry an explicit timeout — never run bare:

- Default tooling calls (`git`, `gh`, `ls`, file ops): **120000 ms**
- Flutter/Dart heavy commands (`pub get`, `analyze`, `test`, `build_runner`, gradle builds): **900000 ms**
- On timeout/hang: retry at most twice, then STOP and report the blocker instead of spinning.
- Applies recursively: any agent/subagent working in this repo inherits this rule and must pass explicit timeouts to its own shell calls.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`seifsheikhelarab/vault_app`, via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical vocabulary used verbatim (`needs-triage` … `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.
