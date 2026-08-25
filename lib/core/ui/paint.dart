import 'package:flutter/material.dart';

import '../money/money.dart';
import '../theme/vault_theme.dart';

export '../theme/vault_theme.dart'
    show VaultColors, chalkLabel, vaultDisplayFamily;

/// Registration-furniture label: small tracked caps, the quiet voice that
/// sits above painted masses without becoming a kicker headline.
class RegistrationLabel extends StatelessWidget {
  const RegistrationLabel(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: chalkLabel(color ?? Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// A flat painted panel whose top edge is cut on a slight diagonal, with a
/// lighter seam line scored along the join — sections of one wall meeting,
/// not stacked cards.
///
/// Optional [fillFraction] (0..1) washes a translucent band in from the
/// left edge, clipped to the same diagonal — the panel itself becomes the
/// bar (e.g. month spend against an overall budget cap).
class ScoredPanel extends StatelessWidget {
  const ScoredPanel({
    required this.child,
    this.color,
    this.seamColor,
    this.slope = 14,
    this.padding = const EdgeInsets.all(20),
    this.fillFraction,
    this.fillColor,
    super.key,
  });

  final Widget child;

  /// Panel ground; defaults to [ColorScheme.primary] — the committed field.
  final Color? color;

  /// The scored highlight along the diagonal join.
  final Color? seamColor;

  /// Vertical drop of the diagonal across the full width, in px.
  final double slope;

  final EdgeInsets padding;

  /// Left-to-right fill width as a fraction of the panel; null = no fill.
  final double? fillFraction;

  /// Fill wash color; defaults to a translucent white over the ground.
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? scheme.primary;
    final seam = seamColor ?? Colors.white.withValues(alpha: 0.28);
    final pad = padding + EdgeInsets.only(top: slope / 2);
    return CustomPaint(
      foregroundPainter: _SeamPainter(slope: slope, seam: seam),
      child: ClipPath(
        clipper: _DiagonalClipper(slope),
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: fill)),
            if (fillFraction != null)
              Positioned.fill(
                child: FractionallySizedBox(
                  widthFactor: fillFraction!.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: ColoredBox(
                    color:
                        fillColor ?? Colors.white.withValues(alpha: 0.13),
                  ),
                ),
              ),
            Padding(
              padding: pad,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  _DiagonalClipper(this.slope);

  final double slope;

  @override
  Path getClip(Size size) {
    return Path()
      ..moveTo(0, slope)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  bool shouldReclip(_DiagonalClipper old) => old.slope != slope;
}

class _SeamPainter extends CustomPainter {
  _SeamPainter({required this.slope, required this.seam});

  final double slope;
  final Color seam;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = seam;
    canvas.drawLine(Offset(0, slope), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(_SeamPainter old) =>
      old.slope != slope || old.seam != seam;
}

/// Hand-mixed paint-pot palette for category identity — six distinct hues.
/// Deliberately NOT scheme-derived: every role of the monochrome teal seed
/// reads as the same hue, so a role rotation cannot separate categories.
/// These are data colors, not chrome; each brightness is authored explicitly
/// (lighter, softer pots at night). Nothing leans ember-orange — that heat
/// stays owned by expense capture alone.
const List<Color> _pigmentsLight = [
  Color(0xFF0E7C7B), // teal — the field seed, first pot
  Color(0xFF34558B), // ink blue
  Color(0xFFC08A1E), // ochre
  Color(0xFF7D4A78), // plum
  Color(0xFF5F7036), // olive
  Color(0xFFAE5560), // dusty rose
];

const List<Color> _pigmentsDark = [
  Color(0xFF53B8B6), // teal
  Color(0xFF82A0DC), // ink blue
  Color(0xFFD9AF4E), // ochre
  Color(0xFFC795C1), // plum
  Color(0xFFA9BA75), // olive
  Color(0xFFDA939C), // dusty rose
];

/// Deterministic per-category tone from the paint-pot palette — the same
/// rotation the reports pie and legend use, so a category reads as one
/// color everywhere it appears. Uncategorized abstains to [outline].
Color categoryTone(String? categoryId, ColorScheme scheme) {
  if (categoryId == null) return scheme.outline;
  var hash = 0;
  for (final code in categoryId.codeUnits) {
    hash = (hash * 31 + code) & 0x7FFFFFFF;
  }
  final pots =
      scheme.brightness == Brightness.dark ? _pigmentsDark : _pigmentsLight;
  return pots[hash % pots.length];
}

/// Small square paint swatch marking an expense's category — the strip's
/// single dab of color, never a border.
class CategorySwatch extends StatelessWidget {
  const CategorySwatch({required this.categoryId, this.size = 12, super.key});

  final String? categoryId;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: categoryTone(categoryId, Theme.of(context).colorScheme),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

/// Monumental money figure — the viewport's single typographic mass.
class MoneyMass extends StatelessWidget {
  const MoneyMass(this.minor, {this.color, this.size = 64, super.key});

  final int minor;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatEgp(minor),
      style: TextStyle(
        fontFamily: vaultDisplayFamily,
        fontSize: size,
        height: 1.05,
        letterSpacing: -0.5,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
