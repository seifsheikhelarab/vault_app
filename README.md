# Vault

Offline-first expense tracker for Android (Flutter client). Egyptian
consumer market; money is integer piasters of EGP end-to-end.

## Architecture

Feature-first: `lib/features/<name>/` for UI, `lib/core/` for shared
plumbing, `lib/data/` for Drift DB, repositories, and the sync engine.
MVVM-ish: screens consume Riverpod providers backed by repositories;
the sync engine (`lib/data/sync/sync_engine.dart`) pushes dirty rows,
pulls deltas, and reconciles categories against `/api/sync`.

The backend is a separate repo (Cloudflare Worker + Better Auth). The API
contract lives at `flutter-client.md` — read it before touching any
networking code.

## Build

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:8787   # dev
flutter test                                                   # tests
dart run build_runner build --delete-conflicting-outputs       # drift codegen
```

### Release

Release builds enforce an https `API_BASE_URL` and fail fast without one:

```sh
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-host \
  --dart-define=SENTRY_DSN=https://... \
  --obfuscate --split-debug-info=build/debug-info
```

Signing reads `key.properties` at the repo root (gitignored) pointing at
`android/app/upload-keystore.jks` (also gitignored). **Back up the
keystore, its passwords, and the debug-info symbols somewhere safe** —
losing the keystore means losing the Play Store listing's update path.

## Docs

- `DESIGN.md` — normative design system (Wallet Grammar).
- `PRODUCT.md` — audience, positioning, platform priorities.
- `docs/adr/` — architecture decisions.
