# AGENTS.md

Flutter client for Vault (expense tracker). App code is currently a fresh Flutter template; the backend lives in a separate repo.

## Backend contract — read first

`flutter-client.md` at repo root is the verified API contract (Better Auth + Cloudflare Worker). Read it before writing any networking/API code. Highest-signal gotchas:

- **Auth is cookie-only** (`better-auth.session_token`). No bearer/JWT. Store in `flutter_secure_storage`, send verbatim as `Cookie:` on every request.
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

No codegen, no build_runner, no CI configured yet. Lints: `flutter_lints` defaults via `analysis_options.yaml`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`seifsheikhelarab/vault_app`, via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical vocabulary used verbatim (`needs-triage` … `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `CONTEXT.md` + `docs/adr/`. See `docs/agents/domain.md`.
