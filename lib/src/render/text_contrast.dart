import 'dart:ui';

/// The WCAG 2 contrast ratio of two colours, from 1 to 21. Alpha is
/// ignored: composite a translucent colour first.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// The opaque fill text sits on: [lineTint], then [wordTint], each
/// composited over the one below, over [background]. A null tint is not
/// painted.
Color compositeFill(Color background, Color? lineTint, Color? wordTint) {
  var fill = background;
  if (lineTint != null) fill = Color.alphaBlend(lineTint, fill);
  if (wordTint != null) fill = Color.alphaBlend(wordTint, fill);
  return fill.a == 1 ? fill : fill.withValues(alpha: 1);
}

/// [color] as text on the opaque [fill] at a contrast of at least
/// [minContrast]: [color] itself when it reads (and always when
/// [minContrast] is 0 or less), else [color] mixed toward [toward] by the
/// least 8-bit step that reaches it, else [toward]. A translucent [color]
/// is judged as drawn on [fill].
Color readableOn(
  Color color,
  Color fill, {
  required Color toward,
  required double minContrast,
}) {
  if (minContrast <= 0 || _reads(color, fill, minContrast)) return color;
  // Contrast along the mix need not grow steadily (the fill can lie
  // between the two colours), so every step is tried, first to last.
  for (var k = 1; k < 255; k++) {
    final c = Color(Color.lerp(color, toward, k / 255)!.toARGB32());
    if (_reads(c, fill, minContrast)) return c;
  }
  return toward;
}

bool _reads(Color c, Color fill, double min) =>
    contrastRatio(c.a == 1 ? c : Color.alphaBlend(c, fill), fill) >= min;

/// [readableOn] with one [toward] and [minContrast], worked out once per
/// colour and fill and kept.
final class TextContrast {
  /// Creates the cache.
  new({required this.toward, required this.minContrast});

  /// The colour dim text is mixed toward.
  final Color toward;

  /// The least contrast.
  final double minContrast;

  final Map<(int, int), Color> _cache = {};

  /// How many colour and fill pairs were worked out (diagnostics).
  int get resolved => _cache.length;

  /// [color] readable on the opaque [fill].
  Color colorOn(Color color, Color fill) =>
      _cache[(color.toARGB32(), fill.toARGB32())] ??= readableOn(
        color,
        fill,
        toward: toward,
        minContrast: minContrast,
      );
}
