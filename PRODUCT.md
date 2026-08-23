# Product

<!-- impeccable:product-schema 1 -->

## Platform

android

## Users

Egyptian consumers tracking their personal day-to-day spending in Egyptian Pounds (EGP) on Android phones. Primary situations: capturing an expense in seconds wherever they are (including with no connectivity), and reviewing spending — totals, budgets, trends — at a glance. iOS ships later as an untested secondary target sharing the same Material-based design language.

## Product Purpose

Vault is an offline-first personal expense tracker backed by a hosted service. Every read comes from local storage, so the app is fully usable without connectivity; a background sync engine keeps device and server consistent. Success means: logging an expense takes seconds and never fails due to network, numbers are always trustworthy, and spending state (month/week totals, budgets, trends) is understandable without effort.

## Positioning

Fully offline-capable expense tracking with natural-language capture ("lunch 120 with Ali" becomes a reviewable expense draft) in EGP, where competing trackers go inert or lossy without a connection.

## Operating Context

- Currency is exclusively EGP, displayed in pounds, stored/transported as integer piasters.
- Connectivity is intermittent; airplane mode and dead zones are normal usage, not edge cases.
- Single-user accounts (email + password sessions); no shared household ledgers in v1.
- English-only interface in v1.

## Capabilities and Constraints

- Four tabs: Dashboard, Expenses, Chat, Settings.
- Expenses and categories work completely offline (create/edit/delete queued locally, synced later).
- Budgets, recurring rules, and Chat parsing are online-only writes; cached data stays visible offline with inline reasons blocking writes.
- Sync: push-then-pull cycles triggered by launch, connectivity regain, debounced mutations, and manual refresh; last-write-wins conflict resolution handled silently; category deletions reconcile locally by nulling references.
- Money entry accepts strict two-decimal input; conversion to/from integer piasters lives in one shared helper.
- New expenses carry client-minted UUID ids enabling idempotent retries.
- Backend contract is verified and documented at repo root (`flutter-client.md`); auth is cookie-session based.
- Undecided product fact: monetization/pricing has not been discussed or decided.

## Brand Commitments

- The product name is **Vault**. No logo, wordmark, palette, typography, voice guidelines, or other identity assets exist yet; nothing visual is binding.

## Evidence on Hand

- Verified backend API contract document at repo root — the authoritative source for all networking behavior.
- No real user data, testimonials, case studies, screenshots of incumbent versions, or market research exist; future work must not fabricate any of these.

## Product Principles

1. Offline is the default path, not a degraded fallback.
2. Capture speed outranks everything else in the core loop.
3. Money math is never approximate: one module, integer piasters, exact round-trips.
4. Reliability is silent: sync and conflicts resolve without demanding attention.
5. Glanceable before deep: today's state readable in one look, depth one tap away.
