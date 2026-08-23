import 'package:flutter/material.dart';

// DESIGN CONTRACT — Vault visual world "Wallet Grammar" (roll seed bfe90971,
// code-led build).
// THESIS: the wallet home Egyptians already navigate daily — one monumental
// money figure rules each viewport, tiles answer fast, and a single ember
// accent is reserved by law for capture alone.
// OWN-WORLD: committed teal field carries whole regions; off-white slabs float
// as content surfaces; deep ink sets type; ember never appears outside
// capture.
// STORY: opens straight to their money state; logging takes seconds; nothing
// nags, nothing glows.
// FIRST VIEWPORT: teal field with the VAULT logotype monumental at its head,
// a white slab sheet rising below holding fields and one filled primary
// action; no ember anywhere on auth.
// FORM: roll-assigned candidate 4 of 7 grounded directions. Raises named from
// Arcade Cabinet (one accent, owned by law), Alphabet Storm (one typographic
// mass per viewport), Folded Crane (numbered capture steps, later tickets).
// FINISH: unreviewed and undocumented is unfinished; this build ends with the
// finish review, the verdict, DESIGN.md, and every shipping raster carrying
// its provenance.

/// Brand color roles for the Wallet Grammar world.
///
/// [ember] is the capture accent: it may decorate only the capture action.
class VaultColors {
  const VaultColors._();

  static const Color fieldSeed = Color(0xFF0E7C7B);
  static const Color ember = Color(0xFFE8562A);
}

ThemeData buildVaultTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: VaultColors.fieldSeed,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
