import 'dart:ui';

import 'package:diff_view/src/render/text_contrast.dart';
import 'package:flutter/painting.dart' show HSLColor;
import 'package:flutter_test/flutter_test.dart';

// A made-up dim theme: a dark background, plain text, a dim comment, a
// bright keyword and the line and word tints of an added line.
const background = Color(0xFF15161E);
const text = Color(0xFFC0C4D8);
const comment = Color(0xFF4E567A);
const keyword = Color(0xFF7AA2F7);
const addedLine = Color(0xFF203A44);
const addedWord = Color(0xFF2B5A66);

const white = Color(0xFFFFFFFF);
const black = Color(0xFF000000);

void main() {
  group('contrastRatio', () {
    test('is 21 for black on white and 1 for a colour on itself', () {
      expect(contrastRatio(black, white), closeTo(21, 1e-9));
      expect(contrastRatio(comment, comment), closeTo(1, 1e-9));
    });

    test('does not depend on the order', () {
      expect(
        contrastRatio(comment, addedWord),
        contrastRatio(addedWord, comment),
      );
    });
  });

  group('readableOn', () {
    Color on(Color c, Color fill, double m, {Color bg = background}) =>
        readableOn(c, fill, background: bg, minContrast: m);

    test('0 leaves every colour as it is', () {
      expect(on(comment, addedWord, 0), same(comment));
    });

    test('a colour that already reads is the same object', () {
      expect(contrastRatio(text, addedWord), greaterThan(4));
      expect(on(text, addedWord, 4), same(text));
      // The comment reads on the line's tint as well as it does on the
      // background with the floor above both: kept.
      const fill = Color(0xFF101118);
      expect(
        contrastRatio(comment, fill),
        greaterThanOrEqualTo(contrastRatio(comment, background)),
      );
      expect(on(comment, fill, 4.5), same(comment));
    });

    test('a colour under the floor on the background comes out at its own '
        'contrast there, and no more', () {
      final own = contrastRatio(comment, background);
      expect(own, lessThan(3));
      expect(contrastRatio(comment, addedWord), lessThan(own));
      final c = on(comment, addedWord, 3);
      expect(contrastRatio(c, addedWord), greaterThanOrEqualTo(own));
      expectFirstThatReads(c, comment, addedWord, own);
      // The comment is a little lighter than the word's tint, so it gets
      // lighter still.
      expect(
        comment.computeLuminance(),
        greaterThan(addedWord.computeLuminance()),
      );
      expect(c.computeLuminance(), greaterThan(comment.computeLuminance()));
    });

    test('a colour over the floor on the background reaches the floor', () {
      const fill = Color(0xFF3D59A1);
      expect(contrastRatio(keyword, background), greaterThan(4.5));
      expect(contrastRatio(keyword, fill), lessThan(3));
      final c = on(keyword, fill, 3);
      expect(contrastRatio(c, fill), greaterThanOrEqualTo(3));
      expectFirstThatReads(c, keyword, fill, 3);
    });

    test('hue and saturation are kept on a dark fill', () {
      const fill = Color(0xFF3D59A1);
      final c = on(keyword, fill, 4.5);
      expect(c, isNot(keyword));
      expectSameHueAndSaturation(c, keyword);
    });

    test('hue and saturation are kept on a light fill', () {
      // A light theme's green string on its added word's tint.
      const string = Color(0xFF2E9E3E);
      const fill = Color(0xFFB8E6B8);
      expect(contrastRatio(string, white), greaterThan(3));
      expect(contrastRatio(string, fill), lessThan(3));
      final c = on(string, fill, 3, bg: white);
      expect(contrastRatio(c, fill), greaterThanOrEqualTo(3));
      // Darker, as it was darker than the fill.
      expect(c.computeLuminance(), lessThan(string.computeLuminance()));
      expectSameHueAndSaturation(c, string);
      expectFirstThatReads(c, string, fill, 3);
    });

    test('a fill between the colour and both ends: the other side is '
        'tried when the own side cannot reach it', () {
      // The colour is darker than the fill, and black reads only 3.3 on
      // it; white reads 6.3.
      const colour = Color(0xFF505050);
      const fill = Color(0xFF606060);
      expect(contrastRatio(black, fill), lessThan(4.5));
      expect(contrastRatio(white, fill), greaterThan(4.5));
      final c = on(colour, fill, 4.5, bg: white);
      expect(contrastRatio(c, fill), greaterThanOrEqualTo(4.5));
      expect(c.computeLuminance(), greaterThan(fill.computeLuminance()));
      expectFirstThatReads(c, colour, fill, 4.5);
    });

    test('a fill between the colour and both ends: the own side first', () {
      const colour = Color(0xFF202020);
      const fill = Color(0xFF777777);
      expect(contrastRatio(black, fill), greaterThan(4.5));
      final c = on(colour, fill, 4.5, bg: white);
      expect(c.computeLuminance(), lessThan(colour.computeLuminance()));
      expectFirstThatReads(c, colour, fill, 4.5);
    });

    test('when neither end reaches it, the best of the colour and the ends, '
        'never worse than the colour', () {
      const fill = Color(0xFF777777);
      // Black is the best on this fill (4.7), white next (4.5).
      expect(on(const Color(0xFF202020), fill, 15, bg: white), black);
      // Black itself cannot do better: the same object.
      expect(on(black, fill, 15, bg: white), same(black));
      for (final colour in [
        const Color(0xFF202020),
        const Color(0xFF505050),
        const Color(0xFFA0A0A0),
        const Color(0xFFE0E0E0),
        comment,
        keyword,
      ]) {
        final c = on(colour, fill, 15, bg: white);
        expect(
          contrastRatio(c, fill),
          greaterThanOrEqualTo(contrastRatio(colour, fill)),
          reason: '$colour',
        );
      }
    });

    test('a colour as light as its fill goes toward the end that reads '
        'better there', () {
      // Its luminance equals the fill's, so neither side is its own. Both
      // ends reach the target; the better one is taken.
      const dark = Color(0xFF404040);
      expect(
        contrastRatio(white, dark),
        greaterThan(contrastRatio(black, dark)),
      );
      expect(contrastRatio(black, dark), greaterThan(1.5));
      final up = on(dark, dark, 1.5, bg: white);
      expect(contrastRatio(up, dark), greaterThanOrEqualTo(1.5));
      expect(up.computeLuminance(), greaterThan(dark.computeLuminance()));
      expectFirstThatReads(up, dark, dark, 1.5);

      const light = Color(0xFFC0C0C0);
      expect(
        contrastRatio(black, light),
        greaterThan(contrastRatio(white, light)),
      );
      expect(contrastRatio(white, light), greaterThan(1.5));
      final down = on(light, light, 1.5, bg: black);
      expect(contrastRatio(down, light), greaterThanOrEqualTo(1.5));
      expect(down.computeLuminance(), lessThan(light.computeLuminance()));
      expectFirstThatReads(down, light, light, 1.5);
    });

    test('a translucent colour is judged as it shows and keeps its alpha', () {
      final faint = comment.withValues(alpha: 0.5);
      final own = contrastRatio(
        Color.alphaBlend(faint, background),
        background,
      );
      final c = on(faint, addedWord, 3);
      expect(c, isNot(faint));
      expect(c.a, faint.a);
      expect(
        contrastRatio(Color.alphaBlend(c, addedWord), addedWord),
        greaterThanOrEqualTo(own),
      );
      expectFirstThatReads(c, faint, addedWord, own);
    });

    test('a translucent colour that shows readably is kept', () {
      final faint = text.withValues(alpha: 0.9);
      expect(on(faint, addedWord, 3), same(faint));
    });
  });

  group('compositeFill', () {
    test('an opaque tint is the fill', () {
      expect(compositeFill(background, addedLine, null), addedLine);
      expect(compositeFill(background, addedLine, addedWord), addedWord);
    });

    test('translucent tints are composited over the background', () {
      const line = Color(0x40409060);
      const word = Color(0x6060C080);
      final lineFill = compositeFill(background, line, null);
      expect(lineFill, Color.alphaBlend(line, background));
      expect(lineFill.a, 1);
      expect(
        compositeFill(background, line, word),
        Color.alphaBlend(word, Color.alphaBlend(line, background)),
      );
      // A word on a line without a tint sits on the background.
      expect(
        compositeFill(background, null, word),
        Color.alphaBlend(word, background),
      );
    });

    test('the contrast is measured on the composited fill', () {
      const line = Color(0x80305A66);
      final fill = compositeFill(background, line, null);
      final c = readableOn(
        comment,
        fill,
        background: background,
        minContrast: 3,
      );
      expect(
        contrastRatio(c, fill),
        greaterThanOrEqualTo(contrastRatio(comment, background)),
      );
      // On the raw, translucent tint the ratio would be judged wrongly.
      expect(contrastRatio(comment, fill), isNot(contrastRatio(comment, line)));
    });
  });

  group('a translucent background', () {
    // What shows under a see-through pane is unknown, so its background
    // is taken as opaque, its alpha dropped.
    final seeThrough = background.withValues(alpha: 0.6);
    const line = Color(0x80305A66);

    test('is taken as opaque under the tints', () {
      expect(
        compositeFill(seeThrough, line, addedWord.withValues(alpha: 0.5)),
        compositeFill(background, line, addedWord.withValues(alpha: 0.5)),
      );
      expect(compositeFill(seeThrough, null, null), background);
    });

    test("is taken as opaque for a colour's own contrast", () {
      final faint = comment.withValues(alpha: 0.7);
      final fill = compositeFill(background, line, null);
      expect(
        readableOn(faint, fill, background: seeThrough, minContrast: 3),
        readableOn(faint, fill, background: background, minContrast: 3),
      );
    });
  });

  group('TextContrast', () {
    test('works out each colour and fill once', () {
      final tc = TextContrast(background: background, minContrast: 3);
      final a = tc.colorOn(comment, addedWord);
      expect(tc.resolved, 1);
      expect(tc.colorOn(comment, addedWord), same(a));
      expect(tc.resolved, 1);
      tc.colorOn(comment, addedLine);
      expect(tc.resolved, 2);
    });
  });
}

// What [c] shows as on [fill].
Color shown(Color c, Color fill) => c.a == 1 ? c : Color.alphaBlend(c, fill);

double shownContrast(Color c, Color fill) =>
    contrastRatio(shown(c, fill), fill);

// The rule's tries for [from] on [fill], in order: its HSL lightness in
// steps of 1/255 toward the end on its own side of the fill (white if it
// shows lighter than the fill, black if darker, and whichever reads
// better on the fill if it shows as light as the fill), to that end, then
// from [from] toward the other end. Each try is 8-bit, with [from]'s
// alpha.
List<Color> tries(Color from, Color fill) {
  final hsl = HSLColor.fromColor(from);
  final lum = shown(from, fill).computeLuminance();
  final fillLum = fill.computeLuminance();
  final up = lum == fillLum
      ? contrastRatio(white, fill) >= contrastRatio(black, fill)
      : lum > fillLum;
  final out = <Color>[];
  for (final dir in [up, !up]) {
    for (var k = 1; ; k++) {
      final raw = hsl.lightness + (dir ? k : -k) / 255;
      final l = raw.clamp(0.0, 1.0);
      out.add(
        Color(hsl.withLightness(l).toColor().toARGB32())
            .withValues(alpha: from.a),
      );
      if (l != raw || l == 0 || l == 1) break;
    }
  }
  return out;
}

// [got] is the first of [from]'s tries on [fill] that reads [target]:
// every try before it does not, so skipping steps fails.
void expectFirstThatReads(Color got, Color from, Color fill, double target) {
  final all = tries(from, fill);
  final i = all.indexOf(got);
  expect(i, greaterThanOrEqualTo(0), reason: '$got is not a try');
  expect(shownContrast(got, fill), greaterThanOrEqualTo(target));
  for (var j = 0; j < i; j++) {
    expect(
      shownContrast(all[j], fill),
      lessThan(target),
      reason: 'try $j (${all[j]}) already reads; $got is try $i',
    );
  }
}

void expectSameHueAndSaturation(Color got, Color want) {
  final g = HSLColor.fromColor(got);
  final w = HSLColor.fromColor(want);
  expect(g.hue, closeTo(w.hue, 2));
  expect(g.saturation, closeTo(w.saturation, 0.03));
}
