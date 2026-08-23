# Vault Flutter Client — Backend Contract

Everything needed to build the Flutter app against this backend. Verified against the code and test suite (`bunx vitest run`: 124 tests passing).

## 1. Server basics

- Cloudflare Worker. Dev base URL: `http://localhost:8787` (`wrangler dev`). All routes under `/api`.
- **No CORS middleware** — irrelevant for native Dart HTTP, fatal if you ever fetch cross-origin from a webview.
- Rate limits per IP per minute: `/api/auth/*` and `/api/chat/*` → **10** (they share one bucket), everything else → **120**. Success responses carry `X-RateLimit-Limit` / `X-RateLimit-Remaining`. Over limit → `429`.

## 2. Authentication — cookie jar required

Better Auth v1.7, email/password only. **Cookie-only sessions; there is NO bearer/JWT support.** The server reads the session exclusively from the `Cookie` header.

Flutter requirements:

1. Maintain your own cookie jar. On sign-up/sign-in capture every `set-cookie`; persist the `better-auth.session_token` value (secure storage) and send it verbatim as `Cookie:` on **every** subsequent request.
2. Send `Content-Type: application/json` on POSTs.
3. Auth endpoint error bodies are Better Auth's own JSON, NOT the app envelope below. Rely on status codes there.
4. Sign-up seeds 8 default categories automatically (Groceries, Transport, Dining, Entertainment, Bills, Health, Shopping, Other).

| Endpoint                    | Method | Request                                                        | Success                                                                                                        |
| --------------------------- | ------ | -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `/api/auth/sign-up/email`   | POST   | `{ "name", "email", "password" }` (password ≥ 8)               | `200`, `{ "user": { id, name, email, emailVerified, createdAt, updatedAt } }` + session cookie                 |
| `/api/auth/sign-in/email`   | POST   | `{ "email", "password" }`                                      | `200` + session cookie. Bad credentials or unknown email both → `401`                                          |
| `/api/auth/get-session`     | GET    | cookie                                                         | `200`, `{ "session": {...}, "user": {...} }`; **body is literal `null` when unauthenticated** (still HTTP 200) |
| `/api/auth/sign-out`        | POST   | cookie                                                         | `200`, clears session                                                                                          |
| `/api/auth/change-password` | POST   | `{ "currentPassword", "newPassword", "revokeOtherSessions"? }` | `200`, rotates cookie                                                                                          |

Not available: email verification, forgot-password, OAuth.

## 3. Error envelope (all non-auth routes)

```json
{ "error": { "code": "...", "message": "...", "issues"?: { "formErrors": [], "fieldErrors": {} } } }
```

| Status | code             | Typical messages                                                                                     |
| ------ | ---------------- | ---------------------------------------------------------------------------------------------------- |
| 400    | BAD_REQUEST      | Bad request                                                                                          |
| 401    | UNAUTHORIZED     | Unauthorized (missing/expired cookie)                                                                |
| 404    | NOT_FOUND        | Not found                                                                                            |
| 409    | CONFLICT         | `"Category already exists"`, `"Expense id already used with a different payload"`                    |
| 422    | VALIDATION_ERROR | `"Invalid request"` + zod issues; also `"Invalid cursor"`, `"Unknown category <uuid> in sync batch"` |
| 429    | RATE_LIMITED     | Too many requests                                                                                    |
| 502    | UPSTREAM_ERROR   | Chat failures                                                                                        |

## 4. Money, time, periods

- **Money**: integer minor units of **EGP** (piasters = amount × 100). Crosses the wire as JSON **number**, never string. Currency fixed `"EGP"` everywhere; server rejects nothing else because currency isn't an accepted input at all.
- **Dates**: ISO-8601 UTC strings with ms in all responses.
- **Timezone**: user's `timeZone` column (default `Africa/Cairo`); not exposed or editable via any route. Period boundaries are local midnights converted to UTC instants (Egypt DST handled).
- **Periods**: weeks start **Monday** (ISO); months are calendar months; windows half-open `[start, end)`.
- Input exceptions: recurring `anchorDate` takes bare `YYYY-MM-DD`; reports/dashboard/budget-progress `?date=` accepts bare date or full datetime.

## 5. Categories — `/api/categories`

Row: `{ "id", "userId", "name", "createdAt", "updatedAt" }`

| Route                        | Body                        | Notes                                                                    |
| ---------------------------- | --------------------------- | ------------------------------------------------------------------------ |
| `POST /api/categories`       | `{ "name" }` trimmed 1..100 | `201`; duplicate name per user → `409`                                   |
| `GET /api/categories`        | —                           | array, createdAt asc then name asc                                       |
| `GET /api/categories/:id`    | —                           | non-UUID id → `422`; foreign/missing → `404`                             |
| `PATCH /api/categories/:id`  | `{ "name" }`                | rename only                                                              |
| `DELETE /api/categories/:id` | —                           | `204`, HARD delete; referencing expenses/budgets get `categoryId = null` |

## 6. Expenses — `/api/expenses` (soft delete)

Full row shape (every field always returned):

```json
{
    "id": "uuid",
    "userId": "uuid",
    "amountMinor": 12345,
    "currency": "EGP",
    "categoryId": "uuid|null",
    "occurredAt": "ISO",
    "note": "string|null",
    "createdAt": "ISO",
    "updatedAt": "ISO",
    "deletedAt": null,
    "recurringDefinitionId": "uuid|null",
    "occurrenceDate": "ISO|null"
}
```

| Route                                                  | Notes                                                                                 |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------- |
| `POST /api/expenses`                                   | see below; `201` new, `200` idempotent replay                                         |
| `GET /api/expenses?limit=<1..100, default 20>&cursor=` | keyset pagination, newest first, `nextCursor: string\|null`, items key is plain array |
| `GET /api/expenses/:id`                                | live rows only                                                                        |
| `PATCH /api/expenses/:id`                              | partial; `categoryId`/`note` accept `null` to clear                                   |
| `DELETE /api/expenses/:id`                             | `204`, SOFT delete (sets `deletedAt`)                                                 |

Create body:

```json
{
    "id": "<client-minted UUID, REQUIRED>",
    "amountMinor": 12345,
    "occurredAt": "ISO optional (default now)",
    "categoryId": "optional uuid (must be owned by user)",
    "note": "optional, max 1000"
}
```

Idempotency rules (offline-first cornerstone):

- Same `id` + identical payload → `200` with stored row. Safe retry.
- Same `id` + different payload → `409`.
- Client MUST mint UUID locally before upload so retries and sync pushes dedupe.

## 7. Budgets — `/api/budgets` (hard delete; NOT part of sync)

Row: `{ "id", "userId", "periodType": "week"|"month", "amountMinor", "categoryId": "uuid|null", "createdAt", "updatedAt" }`
`categoryId: null` = overall budget. Multiple concurrently active budgets allowed (no uniqueness).

| Route                                   | Notes                                                                           |
| --------------------------------------- | ------------------------------------------------------------------------------- |
| `POST /api/budgets`                     | `{ "periodType", "amountMinor", "categoryId"? }` → `201`                        |
| `GET /api/budgets`                      | array                                                                           |
| `GET /api/budgets/progress?date=`       | registered BEFORE `/:id` — don't break order when proxying                      |
| `GET`/`PATCH`/`DELETE /api/budgets/:id` | PATCH all optional, `categoryId` nullable (`null` → overall); DELETE `204` hard |

Progress item:

```json
{
    "id": "uuid",
    "periodType": "week",
    "categoryId": "uuid|null",
    "spent": 123,
    "limit": 45600,
    "pct": 27.05
}
```

Spent sums live expenses in the current week/month window containing `date` (or now); category-scoped budgets sum only that category.

## 8. Recurring — `/api/recurring`

Row: `{ "id", "userId", "name", "amountMinor", "currency", "categoryId", "frequency": "daily"|"weekly"|"monthly", "interval", "anchorDate": "ISO midnight", "nextRunAt": "ISO", "paused", "lastMaterializedAt", "createdAt", "updatedAt" }`

- Create: `{ "name" (trim 1..100), "amountMinor", "frequency", "anchorDate": "YYYY-MM-DD", "interval"? (int 1..1000, default 1), "categoryId"? }` → standard CRUD + list.
- PATCH: any subset + `"paused": true|false`. Changing `anchorDate` resets `nextRunAt`.
- Server cron (daily 03:00 UTC) materializes due occurrences into real Expense rows, with catch-up for missed days; dedupe on `(recurringDefinitionId, occurrenceDate)`; monthly clamps day-of-month (Jan 31 → Feb 28). Client does nothing but display.

## 9. Reports & Dashboard (read-only)

`GET /api/reports/weekly?date=` and `GET /api/reports/monthly?date=`:

```json
{
    "period": { "start": "ISO", "end": "ISO" },
    "total": 123456,
    "byCategory": [{ "categoryId": "uuid", "name": "Food", "total": 999 }],
    "previous": { "total": 111, "delta": 122345, "deltaPct": -12.5 }
}
```

`byCategory` sorted total desc (tie: name asc). Uncategorized expenses count in `total` but appear in no bucket. `deltaPct` is `null` when previous total was 0. Deleted expenses excluded everywhere.

`GET /api/dashboard?date=` single snapshot:

```json
{
  "month": { "total": n, "previous": { "total": n, "delta": n, "deltaPct": n|null } },
  "week":  { "total": n, "previous": { "total": n, "delta": n, "deltaPct": n|null } },
  "budgets": [ /* progress items, same shape as §7 */ ],
  "recentExpenses": [ { "id", "amountMinor", "currency", "categoryId", "occurredAt", "note" } ]
}
```

`recentExpenses`: exactly 5 newest live expenses.

## 10. Chat — `POST /api/chat/parse`

Request `{ "message": string }` (trim 1..1000). Calls Gemini (`gemini-2.5-flash`) to extract ONE expense draft from natural language ("taxi to airport 250"). Relative dates resolved in user timezone.

Response `200` — a DRAFT ONLY, server saves nothing:

```json
{
    "amountMinor": 12500,
    "currency": "EGP",
    "categoryGuess": "Groceries",
    "categoryId": "uuid-or-null",
    "occurredAtGuess": "2026-08-22",
    "note": "string-or-null"
}
```

Client flow: show parsed draft → user confirms → client calls `POST /api/expenses` itself. Errors: `502` parser unavailable/failed, `422` validation, `429` rate limit. Not streaming.

## 11. Sync — `/api/sync` (expenses + categories ONLY)

Budgets and recurring definitions are deliberately NOT synced — fetch them live via their GET endpoints when online.

### Pull: `GET /api/sync/pull?limit=<1..100, default 50>&cursor=<opaque>`

Incremental delta of BOTH tables under one watermark, merged sort `(updatedAt asc, id asc)`:

```json
{
    "expenses": [/* full rows, deletedAt may be NON-null */],
    "categories": [/* full rows */],
    "nextCursor": "string|null"
}
```

- Tombstoned expenses are INCLUDED — that's how clients learn about deletes. Categories have no tombstones (hard-deleted; see push caveat).
- Loop until `nextCursor === null`; upsert locally by id honoring `deletedAt`; persist cursor after each page. First-ever sync: omit cursor.

### Push: `POST /api/sync/push`

Upload local changes as full rows with client `updatedAt`:

```json
{
    "categories": [
        { "id": "uuid", "updatedAt": "ISO", "name": "Food", "deletedAt": "ISO|null|absent" }
    ],
    "expenses": [
        {
            "id": "uuid",
            "updatedAt": "ISO",
            "amountMinor": 123,
            "occurredAt": "ISO",
            "categoryId": "uuid|null",
            "note": "str|null",
            "deletedAt": "ISO|null|absent"
        }
    ]
}
```

Max 500 items per array; both arrays optional. Semantics:

- **Last-writer-wins**: applied only if incoming `updatedAt` strictly newer than stored; equal timestamps favor SERVER (outcome `conflict-lost`) → replays idempotent.
- Deletion = push row with `deletedAt` set. Expense tombstones propagate to other devices via pull; **category deletions do NOT** (categories hard-delete immediately).
- Batch atomic; categories applied before expenses (same-batch references OK). Unknown `categoryId` anywhere → whole batch rolled back, `422`.
- Response: `{ "results": [ { "id": "<item uuid>", "outcome": "accepted"|"conflict-lost" } ] }`.

### Recommended offline architecture

1. Local DB (Drift/Isar/sqlite). All writes go local first; queue mutations.
2. Every expense gets client-minted UUID at creation → safe retries.
3. Background sync worker: flush queue via `push`, then drain `pull` pages updating cursor.
4. On 401 during sync: drop cookie, route to login, resume after re-auth.

## 12. Gaps the frontend must design around

- No forgot-password / email verification / account deletion endpoints.
- Session is a bare cookie value — store in `flutter_secure_storage`, never plaintext prefs.
- Category deletion doesn't reach other devices through sync.
- Budgets/recurring require connectivity; only expenses+categories work offline end-to-end.
- Rate limit: auth+chat share one 10/min bucket — don't fire chat requests right after login bursts.
