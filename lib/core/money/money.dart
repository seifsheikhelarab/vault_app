/// The single place where user-facing decimal money strings convert to/from
/// integer minor units (piasters). Amounts are integer piasters everywhere
/// else — never strings, never floats.
library;

final _decimalPattern = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$');

/// Parses a strict ≤2-decimal decimal string into integer piasters.
///
/// Accepts leading zeros (`"007.5"` → `700`). Rejects empty, garbage,
/// negatives, thousands separators, and more than two decimal places.
///
/// Throws [FormatException] with a plain-language message suitable for
/// showing under an amount field.
int parsePiasters(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Enter an amount');
  }
  final match = _decimalPattern.firstMatch(trimmed);
  if (match == null) {
    throw const FormatException('Use at most two decimals, digits only');
  }
  final pounds = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return pounds * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
}

/// Formats integer piasters as a canonical decimal string, always two
/// decimals (`12345` → `"123.45"`, `0` → `"0.00"`).
///
/// Round-trip guarantee: `parsePiasters(formatPiasters(p)) == p` for every
/// non-negative p.
String formatPiasters(int piasters) {
  if (piasters < 0) {
    throw ArgumentError.value(piasters, 'piasters', 'must be non-negative');
  }
  return '${piasters ~/ 100}.${(piasters % 100).toString().padLeft(2, '0')}';
}

/// Display form: `"EGP 1250.00"`.
String formatEgp(int piasters) => 'EGP ${formatPiasters(piasters)}';
