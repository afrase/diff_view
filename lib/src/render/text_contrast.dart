import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

/// The WCAG 2 contrast ratio of two colours, from 1 to 21. Alpha is
/// ignored: composite a translucent colour first.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return la > lb ? (la + 0.05) / (lb + 0.05) : (lb + 0.05) / (la + 0.05);
}

/// The opaque fill text sits on: [lineTint], then [wordTint], each
/// composited over the one below, over [background]. A null tint is not
/// painted. A translucent [background] is taken as opaque, its alpha
/// dropped: what shows through it is not known here.
Color compositeFill(Color background, Color? lineTint, Color? wordTint) {
  var fill = _opaque(background);
  if (lineTint != null) fill = Color.alphaBlend(lineTint, fill);
  if (wordTint != null) fill = Color.alphaBlend(wordTint, fill);
  return fill;
}

Color _opaque(Color c) => c.a == 1 ? c : c.withValues(alpha: 1);

/// [color] as text on the opaque [fill], keeping the contrast it has on
/// the pane's [background], up to [minContrast].
///
/// The target is the lesser of [minContrast] and [color]'s contrast on
/// [background]. [color] itself when it reads that on [fill] (and always
/// when [minContrast] is 0 or less). Otherwise [color] with its HSL
/// lightness changed, hue, saturation and alpha kept, by the least change
/// that reaches the target, in steps of 1/255: first away from [fill] on
/// the side [color] is on (lighter when it is lighter than [fill], darker
/// when darker), up to white or black, then from [color] toward the other
/// end. When no step reaches it, whichever of [color], white and black
/// reads best on [fill], so the result never reads worse than [color].
/// A translucent [color] is judged as it shows on [fill] and on
/// [background]; a translucent [background] is taken as opaque.
Color readableOn(
  Color color,
  Color fill, {
  required Color background,
  required double minContrast,
}) {
  if (minContrast <= 0) return color;
  final own = _shownContrast(color, _opaque(background));
  final target = own < minContrast ? own : minContrast;
  final start = _shownContrast(color, fill);
  if (start >= target) return color;
  final hsl = HSLColor.fromColor(color);
  final lum = _shown(color, fill).computeLuminance();
  final fillLum = fill.computeLuminance();
  final up = lum == fillLum
      ? contrastRatio(const Color(0xFFFFFFFF), fill) >=
            contrastRatio(const Color(0xFF000000), fill)
      : lum > fillLum;
  for (final lighter in [up, !up]) {
    for (var k = 1; ; k++) {
      final raw = hsl.lightness + (lighter ? k : -k) / 255;
      final l = raw < 0 ? 0.0 : (raw > 1 ? 1.0 : raw);
      final c = _withLightness(hsl, l, color.a);
      if (_shownContrast(c, fill) >= target) return c;
      if (l == 0 || l == 1) break;
    }
  }
  // Nothing reaches it: the best of the colour and the ends. Along each
  // side contrast is best at the end, as luminance grows with lightness.
  var best = color;
  var bestContrast = start;
  for (final c in [
    _withLightness(hsl, up ? 1 : 0, color.a),
    _withLightness(hsl, up ? 0 : 1, color.a),
  ]) {
    final r = _shownContrast(c, fill);
    if (r > bestContrast) {
      best = c;
      bestContrast = r;
    }
  }
  return best;
}

// 8-bit channels, the alpha kept as it was.
Color _withLightness(HSLColor hsl, double l, double alpha) =>
    Color(hsl.withLightness(l).toColor().toARGB32()).withValues(alpha: alpha);

Color _shown(Color c, Color fill) => c.a == 1 ? c : Color.alphaBlend(c, fill);

double _shownContrast(Color c, Color fill) =>
    contrastRatio(_shown(c, fill), fill);

/// [readableOn] with one [background] and [minContrast], worked out once
/// per colour and fill and kept.
final class TextContrast {
  /// Creates the cache.
  new({required this.background, required this.minContrast});

  /// The pane's background, where a colour's own contrast is measured.
  final Color background;

  /// The floor.
  final double minContrast;

  final Map<(int, int), Color> _cache = {};

  /// How many colour and fill pairs were worked out (diagnostics).
  int get resolved => _cache.length;

  /// [color] readable on the opaque [fill].
  Color colorOn(Color color, Color fill) =>
      _cache[(color.toARGB32(), fill.toARGB32())] ??= readableOn(
        color,
        fill,
        background: background,
        minContrast: minContrast,
      );
}
