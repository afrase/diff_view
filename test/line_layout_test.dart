import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:diff_view/diff_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('expandTabs', () {
    test('no tab: same text, no column map', () {
      expect(expandTabs('abc', 4), ('abc', null));
    });

    test('tabs go to the next stop and the map follows', () {
      final (text, cols) = expandTabs('\ta\tbc', 4);
      expect(text, '    a   bc');
      expect(cols, [0, 4, 5, 8, 9, 10]);
    });
  });

  group('LineLayoutBuilder', () {
    final theme = DiffThemeData.light();
    final builder = LineLayoutBuilder(theme, const ['', 'keyword']);

    test('advance is one column; monospace x is column × advance', () {
      // The test font draws every glyph one em wide.
      expect(builder.advance, closeTo(theme.fontSize, 0.01));
      final layout = builder.build(
        DiffLine(
          line: 0,
          text: '\tfunc x',
          syntax: Uint32List.fromList([1, 4, 1]),
        ),
      );
      expect(layout.isMonospaceSafe, isTrue);
      expect(layout.columnOf(1), 4);
      expect(layout.xRange(1, 5, builder.advance), (4 * 13.0, 8 * 13.0));
      expect(layout.width, closeTo(10 * 13.0, 0.01));
      layout.dispose();
    });

    test('non-Latin-1 text measures through the paragraph', () {
      final layout = builder.build(DiffLine(line: 0, text: 'a日本b'));
      expect(layout.isMonospaceSafe, isFalse);
      final (x0, x1) = layout.xRange(1, 3, builder.advance);
      expect(x0, closeTo(13, 0.01));
      expect(x1, greaterThan(x0));
      layout.dispose();
    });

    test('a soft hyphen or a control character is measured, not assumed', () {
      // U+00AD draws zero-width mid-line: 'a­bcd' is four advances wide, so
      // 'd' starts at 3 advances, not 4.
      final shy = builder.build(DiffLine(line: 0, text: 'a\u00ADbcd'));
      expect(shy.isMonospaceSafe, isFalse);
      final (x0, _) = shy.xRange(4, 5, builder.advance);
      expect(x0, closeTo(shy.width - builder.advance, 0.01));
      shy.dispose();
      for (final text in ['a\u0001b', 'a\u007Fb', 'a\u0085b']) {
        final l = builder.build(DiffLine(line: 0, text: text));
        expect(l.isMonospaceSafe, isFalse, reason: text.codeUnits.toString());
        l.dispose();
      }
      final latin = builder.build(DiffLine(line: 0, text: 'café ÿ ×'));
      expect(latin.isMonospaceSafe, isTrue);
      latin.dispose();
    });

    test('measured x spans are cached per range', () {
      final layout = builder.build(DiffLine(line: 0, text: 'a日本b'));
      final first = layout.xSpans(1, 3, builder.advance);
      expect(identical(layout.xSpans(1, 3, builder.advance), first), isTrue);
      expect(layout.xSpans(0, 1, builder.advance), isNot(first));
      layout.dispose();
    });

    test('a range split by an RTL run is one span per visual run', () {
      // `"של` (offsets 4..7): the quote sits left of the Hebrew run, the
      // two letters at its right end; `ום עולם` lies between them.
      const text = 'x = "שלום עולם" + y';
      final layout = builder.build(DiffLine(line: 0, text: text));
      final a = builder.advance;
      final spans = layout.xSpans(4, 7, a);
      expect(spans, hasLength(2));
      final covered = spans.fold<double>(0, (w, s) => w + s.$2 - s.$1);
      expect(covered, closeTo(3 * a, 0.5));
      for (var i = 1; i < spans.length; i++) {
        expect(spans[i].$1, greaterThan(spans[i - 1].$2));
      }
      // xRange is still the whole extent.
      final (x0, x1) = layout.xRange(4, 7, a);
      expect(x0, spans.first.$1);
      expect(x1, spans.last.$2);
      // A range in one direction stays one span.
      expect(layout.xSpans(0, 3, a), [(0.0, 3 * a)]);
      layout.dispose();
    });

    test('emoji ZWJ sequences and RTL runs give ordered, finite ranges', () {
      for (final text in ['👩‍💻 x = 1', 'say("שלום") // done']) {
        final layout = builder.build(DiffLine(line: 0, text: text));
        expect(layout.isMonospaceSafe, isFalse);
        final end = text.length;
        final (x0, x1) = layout.xRange(end - 1, end, builder.advance);
        expect(x0.isFinite && x1.isFinite, isTrue);
        expect(x1, greaterThan(x0));
        expect(x1, lessThanOrEqualTo(layout.width + 0.01));
        layout.dispose();
      }
    });

    test('a long line lays out on one line at full width', () {
      final text = 'x' * 5000;
      final layout = builder.build(DiffLine(line: 0, text: text));
      expect(layout.width, closeTo(5000 * builder.advance, 0.5));
      expect(layout.paragraph.computeLineMetrics(), hasLength(1));
      expect(layout.xRange(4999, 5000, builder.advance), (
        4999 * builder.advance,
        5000 * builder.advance,
      ));
      layout.dispose();
    });

    test('syntax spans after a tab keep their styles (review round 3)', () {
      // Overlap is judged on original offsets; expanded columns run ahead
      // of them after a tab, which used to drop `err` and `!=` here.
      const text = '\t\tif err != nil {';
      final syntax = [2, 2, 1, 5, 3, 1, 9, 2, 1, 12, 3, 1];
      final (_, cols) = expandTabs(text, 4);
      final runs = <(int, int, int)>[];
      syntaxRuns(text.length, syntax, cols, (s, e, c) => runs.add((s, e, c)));
      expect(runs, [(8, 10, 1), (11, 14, 1), (15, 17, 1), (18, 21, 1)]);
      // A real overlap is still skipped; an empty span too.
      runs.clear();
      syntaxRuns(6, [0, 3, 1, 2, 2, 1, 4, 0, 1, 4, 2, 1], null, (s, e, c) {
        runs.add((s, e, c));
      });
      expect(runs, [(0, 3, 1), (4, 6, 1)]);
    });

    test('a styled span after a tab paints in its style', () async {
      // Pixel probe: the test font draws every glyph as a full box in the
      // text colour, so the centre of a column is that glyph's colour.
      Future<List<int>> colours(String text, List<int> syntax) async {
        final layout = builder.build(
          DiffLine(line: 0, text: text, syntax: Uint32List.fromList(syntax)),
        );
        final a = builder.advance;
        final w = (layout.width + a).ceil();
        final h = layout.paragraph.height.ceil();
        final rec = ui.PictureRecorder();
        ui.Canvas(rec).drawParagraph(layout.paragraph, ui.Offset.zero);
        final image = await rec.endRecording().toImage(w, h);
        final bytes = (await image.toByteData())!;
        image.dispose();
        final (expanded, _) = expandTabs(text, theme.tabSize);
        final out = [
          for (var col = 0; col < expanded.length; col++)
            bytes.getUint32(((h ~/ 2) * w + (col * a + a / 2).floor()) * 4),
        ];
        layout.dispose();
        return out;
      }

      // Columns: 4 = `i`, 7 = `e` (of `err`), 11 = `x`.
      final tabbed = await colours('\tif err x', [1, 2, 1, 4, 3, 1]);
      final spaced = await colours('    if err x', [4, 2, 1, 7, 3, 1]);
      expect(tabbed, spaced);
      expect(tabbed[7], tabbed[4], reason: '`err` in the keyword style');
      expect(tabbed[11], isNot(tabbed[4]), reason: '`x` in the base style');
    });

    test('out-of-range syntax spans are clamped, not thrown', () {
      final layout = builder.build(
        DiffLine(line: 0, text: 'ab', syntax: Uint32List.fromList([1, 99, 1])),
      );
      expect(layout.width, closeTo(26, 0.01));
      layout.dispose();
    });
  });

  group('ParagraphCache', () {
    test('evicts the least recently used entry', () {
      final builder = LineLayoutBuilder(DiffThemeData.light(), const ['']);
      final cache = ParagraphCache(maxEntries: 2);
      var built = 0;
      final lines = {
        for (final k in [1, 2, 3]) k: DiffLine(line: k, text: 'x$k'),
      };
      LineLayout make(int k) => cache.getOrBuild(k, lines[k]!, () {
        built++;
        return builder.build(lines[k]!);
      });
      make(1);
      make(2);
      make(1); // hit; 2 is now the oldest
      make(3); // evicts 2
      expect(built, 3);
      expect(cache.contains(1), isTrue);
      expect(cache.contains(2), isFalse);
      expect(cache.contains(3), isTrue);
      make(2);
      expect(built, 4);
      expect(cache.length, 2);
      cache.clear();
      expect(cache.length, 0);
    });

    test('an entry hit between inserts is never evicted', () {
      final builder = LineLayoutBuilder(DiffThemeData.light(), const ['']);
      final cache = ParagraphCache(maxEntries: 3);
      LineLayout make(int k) {
        final line = DiffLine(line: k, text: 'x$k');
        return cache.getOrBuild(k, line, () => builder.build(line));
      }

      final hot = make(0);
      for (var k = 1; k < 50; k++) {
        expect(make(0), same(hot), reason: 'insert $k');
        make(k);
        expect(cache.length, lessThanOrEqualTo(3));
      }
      expect(cache.contains(0), isTrue);
      expect(cache.contains(49), isTrue);
      cache.clear();
    });

    test('a capacity of one keeps the newest entry', () {
      final builder = LineLayoutBuilder(DiffThemeData.light(), const ['']);
      final cache = ParagraphCache(maxEntries: 1);
      for (var k = 0; k < 3; k++) {
        final line = DiffLine(line: k, text: 'x$k');
        cache
          ..getOrBuild(k, line, () => builder.build(line))
          ..getOrBuild(k, line, () => builder.build(line));
        expect(cache.contains(k), isTrue);
        expect(cache.length, 1);
      }
      cache.clear();
    });

    test('a line that lays out differently rebuilds its entry', () {
      final builder = LineLayoutBuilder(DiffThemeData.light(), const [
        '',
        'keyword',
      ]);
      final cache = ParagraphCache(maxEntries: 4);
      var built = 0;
      LineLayout get(DiffLine line) => cache.getOrBuild(7, line, () {
        built++;
        return builder.build(line);
      });
      final plain = DiffLine(line: 7, text: 'func x');
      final first = get(plain);
      // The same content in a new object (a page decoded again): kept.
      expect(get(DiffLine(line: 7, text: 'func x')), same(first));
      expect(built, 1);
      // Syntax tokens arrived after the row: rebuilt.
      final tokens = DiffLine(
        line: 7,
        text: 'func x',
        syntax: Uint32List.fromList([0, 4, 1]),
      );
      final second = get(tokens);
      expect(second, isNot(same(first)));
      expect(built, 2);
      // A re-fetched row with other text (file_key changed): rebuilt.
      final third = get(DiffLine(line: 7, text: 'func y'));
      expect(third, isNot(same(second)));
      expect(built, 3);
      expect(cache.invalidated, 2);
      expect(cache.length, 1);
      cache.clear();
    });
  });

  group('DiffThemeData', () {
    test('line height snaps to physical pixels', () {
      final t = DiffThemeData.light();
      expect(t.lineHeightFor(2), 19); // 13 × 1.45 = 18.85 → 37.7 → 38 / 2
      expect(t.lineHeightFor(1), 19);
      expect(t.placeholderHeightFor(2), 28.5);
    });

    test('dotted capture names fall back to their parents', () {
      final styles = DiffThemeData.light().resolveCaptures(const [
        '',
        'keyword.control.return',
        'unknown',
      ]);
      expect(styles, hasLength(3));
    });
  });
}
