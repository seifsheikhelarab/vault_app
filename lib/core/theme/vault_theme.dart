import 'package:flutter/material.dart';

// DESIGN CONTRACT — Vault visual world "Sign-Painter's Cairo" (roll seed
// a5779bdb, code-led build; replaces "Wallet Grammar" bfe90971).
// THESIS: every screen is a freshly painted wall — flat committed teal
// panels, monumental block-letter money, ember the single hot spot. The
// category-default arrangement refused: neutral cards floating on cool gray.
// OWN-WORLD: committed teal field carries whole regions on a warm plaster
// ground (#F4EFE6 light / ink-teal dark); deep ink sets body type; Anton
// block lettering is the only display voice, at exactly two sizes — the
// monumental money mass and everything yielded beneath it; scored diagonal
// seams join sections; tracked caps micro-labels act as registration
// furniture; ember #E8562A decorates only expense capture, never charts,
// navigation, or auth.
// STORY: opens straight onto their month painted in full color; logging is
// the one burning action; nothing nags.
// FIRST VIEWPORT: dashboard opens edge-to-edge on the teal painted wall,
// month total monumental in Anton, delta beneath in tinted plaster text;
// below the seam, week band, budget patches, recent strips; ember FAB alone
// burns above an ink navigation beam.
// FORM: roll-assigned candidate 7 of 7 grounded directions (hand-painted
// shop signs & cinema billboards of Cairo streets). Raises named from
// Design Annual Plates (registration label furniture), Miura Fold (scored
// diagonal seams), Cracktro Queue (one display family, two sizes).
// FINISH: unreviewed and undocumented is unfinished; this build ends with
// the finish review, the verdict, DESIGN.md, and every shipping raster
// carrying its provenance.

/// Brand color roles for the Sign-Painter's Cairo world.
///
/// [fieldSeed] seeds the entire scheme and paints whole regions literally.
/// [ember] is the capture accent: it may decorate only the capture action.
/// [plaster] and [ink] are the physical ground and lettering of the wall;
/// both adapt per brightness so dark mode stays one painted scene at night.
class VaultColors {
  const VaultColors._();

  static const Color fieldSeed = Color(0xFF0E7C7B);
  static const Color ember = Color(0xFFE8562A);
  static const Color plaster = Color(0xFFF4EFE6);
  static const Color ink = Color(0xFF1F1D1A);
}

/// The bundled display voice. Hand-blocked poster lettering: used ONLY for
/// the monumental money mass and screen titles, never for body copy.
const String vaultDisplayFamily = 'Anton';

/// Shared tracked-caps style for registration-furniture labels.
TextStyle chalkLabel(Color color) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.4,
      height: 1.0,
      color: color,
    );

ThemeData buildVaultTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: VaultColors.fieldSeed,
    brightness: brightness,
  );

  // The wall's ground and lettering: warm plaster by day, ink-teal at
  // night. Everything else keeps its seed-derived role.
  final painted = switch (brightness) {
    Brightness.light => scheme.copyWith(
        surface: VaultColors.plaster,
        onSurface: VaultColors.ink,
        surfaceContainerLowest: const Color(0xFFFBF8F2),
        surfaceContainerLow: const Color(0xFFF6F1E8),
        surfaceContainer: const Color(0xFFEFEBE1),
        surfaceContainerHigh: const Color(0xFFEAE5DA),
        surfaceContainerHighest: const Color(0xFFE4DFD4),
        onSurfaceVariant: const Color(0xFF57534A),
        outlineVariant: const Color(0xFFD5CFC2),
      ),
    Brightness.dark => scheme.copyWith(
        surface: const Color(0xFF141A19),
        onSurface: const Color(0xFFE4DFD4),
        surfaceContainerLowest: const Color(0xFF0F1413),
        surfaceContainerLow: const Color(0xFF171D1C),
        surfaceContainer: const Color(0xFF1B2221),
        surfaceContainerHigh: const Color(0xFF252C2B),
        surfaceContainerHighest: const Color(0xFF303736),
        onSurfaceVariant: const Color(0xFFB3AEA3),
        outlineVariant: const Color(0xFF3A413F),
      ),
  };

  return ThemeData(
    useMaterial3: true,
    colorScheme: painted,
    scaffoldBackgroundColor: painted.surface,
    splashFactory: InkSparkle.splashFactory,
    textTheme: builtTextTheme().apply(
      bodyColor: painted.onSurface,
      displayColor: painted.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: painted.surface,
      foregroundColor: painted.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: vaultDisplayFamily,
        fontSize: 24,
        letterSpacing: 0.6,
        color: painted.onSurface,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: painted.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: painted.primary, width: 1.6),
      ),
      filled: true,
      fillColor: painted.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: painted.surfaceContainerLow,
      selectedColor: painted.primaryContainer,
      side: BorderSide(color: painted.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: painted.onSurface,
      ),
    ),
    navigationBarTheme: switch (brightness) {
      // The painted beam: by day a deep-ink lettering strip with plaster
      // destinations and a teal pill; at night it sinks to near-black.
      Brightness.light => NavigationBarThemeData(
          backgroundColor: VaultColors.ink,
          indicatorColor: const Color(0xFF2E9E9C),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? Colors.white
                    : const Color(0xFFB8B3A7),
              )),
          height: 68,
          labelTextStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: Color(0xFFE4DFD4),
            ),
          ),
        ),
      Brightness.dark => NavigationBarThemeData(
          backgroundColor: const Color(0xFF0F1413),
          indicatorColor: scheme.primaryContainer,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                color: states.contains(WidgetState.selected)
                    ? scheme.onPrimaryContainer
                    : const Color(0xFF8A857A),
              )),
          height: 68,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: scheme.onSurface.withValues(alpha: 0.9),
            ),
          ),
        ),
    },
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: painted.inverseSurface,
      contentTextStyle: TextStyle(color: painted.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: painted.primary,
      linearTrackColor: painted.surfaceContainerHighest,
    ),
    dividerTheme: DividerThemeData(
      color: painted.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}

/// Roboto body scale with Anton carrying display and headline roles — the
/// two sizes of the world: monumental masses and yielded titles.
TextTheme builtTextTheme() {
  final anton = TextStyle(fontFamily: vaultDisplayFamily);
  return TextTheme(
    displayLarge: anton.copyWith(fontSize: 57, letterSpacing: -0.5),
    displayMedium: anton.copyWith(fontSize: 45, letterSpacing: -0.5),
    displaySmall: anton.copyWith(fontSize: 36, letterSpacing: -0.25),
    headlineLarge: anton.copyWith(fontSize: 32),
    headlineMedium: anton.copyWith(fontSize: 28),
    headlineSmall: anton.copyWith(fontSize: 24),
    titleLarge: const TextStyle(
        fontFamily: 'Roboto', fontSize: 22, fontWeight: FontWeight.w600),
    titleMedium: const TextStyle(
        fontFamily: 'Roboto', fontSize: 16, fontWeight: FontWeight.w600),
    titleSmall: const TextStyle(
        fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w600),
    bodyLarge: const TextStyle(fontFamily: 'Roboto', fontSize: 16),
    bodyMedium: const TextStyle(fontFamily: 'Roboto', fontSize: 14),
    bodySmall: const TextStyle(fontFamily: 'Roboto', fontSize: 12),
    labelLarge: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1),
    labelMedium: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3),
    labelSmall: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4),
  );
}
