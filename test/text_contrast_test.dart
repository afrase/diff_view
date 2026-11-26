import 'dart:ui';

import 'package:diff_view/src/render/text_contrast.dart';
import 'package:flutter_test/flutter_test.dart';

// A made-up dim theme: a dark background, plain text, a dim comment and the
// line and word tints of an added line.
const background = Color(0xFF15161E);
const text = Color(0xFFC0C4D8);
const comment = Color(0xFF4E567A);
const addedLine = Color(0xFF203A44);
const addedWord = Color(0xFF2B5A66);

void main() {
  group('contrastRatio', () {
    test('is 21 for black on white and 1 for a colour on itself', () {
      expect(
        contrastRatio(const Color(0xFF000000), const Color(0xFFFFFFFF)),
        closeTo(21, 1e-9),
      );
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
    test('0 leaves every colour as it is', () {
      expect(
        readableOn(comment, addedWord, toward: text, minContrast: 0),
        same(comment),
      );
    });

    test('a colour that already reads is kept', () {
      expect(contrastRatio(text, addedWord), greaterThan(4));
      expect(
        readableOn(text, addedWord, toward: text, minContrast: 4),
        same(text),
      );
      expect(contrastRatio(comment, background), greaterThan(2));
      expect(
        readableOn(comment, background, toward: text, minContrast: 2),
        same(comment),
      );
    });

    test('a dim colour is mixed toward the text until it reads', () {
      expect(contrastRatio(comment, addedWord), lessThan(1.5));
      final c = readableOn(comment, addedWord, toward: text, minContrast: 3);
      expect(c, isNot(comment));
      expect(contrastRatio(c, addedWord), greaterThanOrEqualTo(3));
      // It is on the way from the comment to the text, opaque.
      expect(c.a, 1);
      final t = (c.r - comment.r) / (text.r - comment.r);
      expect(t, inExclusiveRange(0, 1));
      for (final (from, to, got) in [
        (comment.g, text.g, c.g),
        (comment.b, text.b, c.b),
      ]) {
        expect(got, closeTo(from + (to - from) * t, 1.5 / 255));
      }
    });

    test('the mix is the least that reaches the contrast', () {
      final c = readableOn(comment, addedWord, toward: text, minContrast: 3);
      // c is the first 8-bit step of the mix that reads; the step before
      // it does not.
      final k = [for (var k = 0; k < 256; k++) k]
          .firstWhere((k) => mix(comment, text, k / 255) == c);
      expect(k, greaterThan(0));
      expect(
        contrastRatio(mix(comment, text, (k - 1) / 255), addedWord),
        lessThan(3),
      );
    });

    test('falls back to the text when even the text does not reach it', () {
      expect(contrastRatio(text, addedWord), lessThan(15));
      expect(
        readableOn(comment, addedWord, toward: text, minContrast: 15),
        text,
      );
    });

    test('a colour equal to the text stays the text', () {
      expect(readableOn(text, addedWord, toward: text, minContrast: 15), text);
    });

    test('a translucent text colour is judged as drawn on the fill', () {
      // Half the comment's alpha reads even less than the comment.
      final faint = comment.withValues(alpha: 0.5);
      final c = readableOn(faint, addedWord, toward: text, minContrast: 3);
      expect(
        contrastRatio(Color.alphaBlend(c, addedWord), addedWord),
        greaterThanOrEqualTo(3),
      );
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
      final c = readableOn(comment, fill, toward: text, minContrast: 3);
      expect(contrastRatio(c, fill), greaterThanOrEqualTo(3));
      // On the raw, translucent tint the ratio would be judged wrongly.
      expect(contrastRatio(comment, fill), isNot(contrastRatio(comment, line)));
    });
  });

  group('TextContrast', () {
    test('works out each colour and fill once', () {
      final tc = TextContrast(toward: text, minContrast: 3);
      final a = tc.colorOn(comment, addedWord);
      expect(tc.resolved, 1);
      expect(tc.colorOn(comment, addedWord), same(a));
      expect(tc.resolved, 1);
      tc.colorOn(comment, addedLine);
      expect(tc.resolved, 2);
    });
  });
}

// [from] mixed toward [to] by [t], in 8-bit channels.
Color mix(Color from, Color to, double t) =>
    Color(Color.lerp(from, to, t)!.toARGB32());
