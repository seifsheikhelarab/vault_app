---
name: Vault
description: Offline-first expense tracker for Egyptian consumers — log fast, works offline.
colors:
  field-teal: "#0E7C7B"
  ember: "#E8562A"
typography:
  display:
    fontFamily: "Roboto"
    fontSize: "57px (Material displayLarge)"
    fontWeight: 700
    letterSpacing: "-1px"
    lineHeight: 1.12
  label:
    fontFamily: "Roboto"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.33
rounded:
  sm: "12px"
  md: "14px"
  xl: "28px"
spacing:
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
components:
  button-primary:
    backgroundColor: "{colors.field-teal}"
    textColor: "on-primary (derived)"
    rounded: "{rounded.md}"
    size: "full-width x 52px"
  input-field:
    backgroundColor: "surface-container-lowest (derived)"
    textColor: "on-surface (derived)"
    rounded: "{rounded.md}"
---

# Design System: Vault

## Overview

**Creative North Star: "Wallet Grammar"**

Vault borrows the visual grammar of the mobile-wallet homes Egyptians already navigate daily — InstaPay, Vodafone Cash: a committed colored field owns whole regions of the screen, content arrives on floating off-white slabs, and exactly one hot accent exists, reserved by law for the capture action. Money is the protagonist; chrome stays quiet. Nothing nags, nothing glows.

The system is Material 3 throughout — structure, navigation, and interaction come from M3 components and role-derived color, never raw hex outside the two brand seeds. Dark theme is a first-class citizen produced by the same seeds through `ColorScheme.fromSeed`; its paler tonal ground is accepted as correct adaptation, not drift. Placeholders are honest: they name what will arrive and when, never fake skeletons or shimmering lies.

**Key Characteristics:**
- Two brand constants only: committed teal field, capture-only ember
- All other color flows from Material role derivation (`ColorScheme.fromSeed`)
- One typographic mass per viewport; type hierarchy does the rest quietly
- Rounded-slab geometry (28px rising sheets, 14px controls, 12px toasts)

## Colors

A deep teal field anchors identity; every other surface is a Material-derived neutral that shifts tone correctly between light and dark.

### Primary
- **Field Teal** (#0E7C7B): the seed of the entire `ColorScheme`. Appears literally as the committed field region on auth screens (top 40% of the viewport); everywhere else it works indirectly through derived roles (`primary`, `primaryContainer`).

### Secondary
- **Ember** (#E8562A): the capture accent. Owned exclusively by the log-an-expense action. It must never appear on auth surfaces, navigation, or decoration.

### Neutral
- Derived roles only (`surface`, `surfaceContainer`, `surfaceContainerLowest`, `outlineVariant`, `onSurfaceVariant`, `scrim`): all flow from the seed at runtime. No neutral hex is hardcoded; light and dark both inherit correctly.

### Named Rules
**The Ember Law.** Ember decorates only the capture action — currently the FAB, forever anything expense-capture becomes. If ember appears somewhere that cannot log an expense, the design is broken.
**The Committed Field Rule.** Whole regions carry the teal field; teal never shrinks to trim, borders, or small highlights. It commits area or abstains.

## Typography

**Display Font:** Roboto (platform face; display-face upgrade deliberately unresolved)
**Body Font:** Roboto

**Character:** One voice, weight-led. Personality comes from scale jumps (monumental wordmark vs quiet labels) rather than font mixing.

### Hierarchy
- **Display** (700, displayLarge 57px, -1px tracking): the monumental "Vault" wordmark and future money figures — one per viewport.
- **Title** (600–500, titleMedium): section titles, empty-state headlines, the auth tagline.
- **Body** (400, bodyMedium): helper copy, empty-state explanations.
- **Label** (600, 12px): navigation destination labels.

### Named Rules
**The One Mass Rule.** Each viewport holds exactly one dominant typographic mass — the money figure or the wordmark — and every other string yields to it.

## Layout

Single-column phone-first layout. Auth splits the viewport 2:3 — committed field above, rising form slab below. Content slabs use 24px horizontal padding; forms separate fields by 16px and fields-from-action by 24px. Empty states center horizontally with 32px side insets and 16/8px internal rhythm. Bottom navigation carries the four destinations (Home, Expenses, Chat, Settings).

## Elevation & Depth

Hybrid: one structural shadow plus Material tonal layering. The signature depth move is the **rising slab** — content sheets lift from below with an upward-cast shadow (offset 0,-6, blur 18, scrim 35%), reading as paper laid over the field. Everything else uses M3 tonal elevation (`surfaceContainer` nav bar over `surface` body); no drop shadows on cards or buttons.

### Shadow Vocabulary
- **Slab rise** (`BoxShadow(0, -6, 18, scrim @35%)`): upward-cast shadow under rising content sheets. Structural, used where slab meets field.

## Shapes

Rounded but disciplined. Controls (buttons, inputs) share a 14px radius; toasts use 12px; content sheets crown with a 28px top radius — the larger the surface, the larger the radius. Outlines exist only on inputs (`outlineVariant` stroke on filled `surfaceContainerLowest`). No pill shapes, no hard corners.

## Components

### Buttons
- **Shape:** 14px radius, full-width, 52px minimum height, 16px w600 label
- **Primary:** FilledButton in derived primary/on-primary (teal field on auth)
- **Busy:** inline 22px spinner replaces label; button disables during work
- **Text:** TextButton for footers ("Create one", "Sign in") — no outlined secondary tier yet

### Inputs / Fields
- **Style:** filled `surfaceContainerLowest`, 1px `outlineVariant` stroke, 14px radius, 16/14px internal padding
- **Focus/Error:** Material defaults; validation fires on user interaction with plain-language messages ("Enter your email", "Use at least 8 characters")

### Navigation
- **Style:** M3 NavigationBar on `surfaceContainer`, `primaryContainer` indicator pills, outlined→filled icon pairs, 12px w600 labels
- **Active behavior:** re-tapping the current tab returns to its root location

### Capture FAB
- **Signature component.** Ember (#E8562A) ground, white add glyph, tooltip "Log an expense". The only hot element in the world; sits above the NavigationBar on every main tab. Exception to the no-hardcoded-neutrals rule: the glyph is literal `Colors.white` by design — Ember has no scheme role to derive an `on` color from, so white is the law here, not an oversight.

### Empty State
- Centered column: 48px outline-colored icon, w600 titleMedium headline, bodyMedium explanation in `onSurfaceVariant`. Copy names what arrives and when ("Parsing ships soon"), never fakes loading.

### Snackbar
- Floating behavior, 12px radius; used for gentle status ("Expense capture arrives with the expenses release."), never errors-as-toasts.

## Do's and Don'ts

### Do:
- **Do** derive every color except Field Teal and Ember from `ColorScheme.fromSeed(fieldTeal)` so dark theme adapts for free.
- **Do** give each viewport exactly one monumental typographic mass.
- **Do** write placeholders that name what arrives and when.
- **Do** reserve 52px full-width filled buttons for a screen's single primary action.

### Don't:
- **Don't** use Ember anywhere that can't capture an expense — especially auth.
- **Don't** hardcode neutrals; use scheme roles so dark mode stays coherent.
- **Don't** shrink the teal into borders, badges, or trims — it commits regions or abstains.
- **Don't** fake data states with skeletons or shimmers; say what's coming instead.
