import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:diff_view/diff_view.dart';
import 'package:diff_view/src/render/text_contrast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// A made-up dark theme whose comments are dim: they read on the background
// (about 2.6:1) and all but vanish on the tints.
const _background = Color(0xFF15161E);
const _text = Color(0xFFC0C4D8);
const _comment = Color(0xFF4E567A);

DiffThemeData dimCommentTheme({double minTextContrast = 0}) => DiffThemeData(
  brightness: ui.Brightness.dark,
  background: _background,
  text: _text,
  gutterBackground: _background,
  gutterText: const Color(0xFF3B3F52),
  gutterTextChanged: const Color(0xFF737AA0),
  insertedLine: const Color(0xFF203A44),
  insertedWord: const Color(0xFF2B5A66),
  deletedLine: const Color(0xFF3A2228),
  deletedWord: const Color(0xFF5E2E38),
  modifiedLine: const Color(0xFF22304C),
  modifiedWord: const Color(0xFF34497A),
  // Translucent, so the fills are composited.
  unifiedDeletedLine: const Color(0x66702A36),
  unifiedDeletedWord: const Color(0x99843444),
  ribbonInserted: const Color(0xFF203A44),
  ribbonDeleted: const Color(0xFF3A2228),
  ribbonModified: const Color(0xFF22304C),
  dividerBackground: _background,
  selection: const Color(0x663D59A1),
  selectionOverCap: const Color(0x66E0AF68),
  textSelection: const Color(0xFF2E3C64),
  foldPlaceholderBackground: const Color(0xFF1E2030),
  foldPlaceholderText: const Color(0xFF737AA0),
  loadingBar: const Color(0xFF1E2030),
  hoverAffordance: const Color(0xFF7AA2F7),
  syntax: const {
    'comment': SyntaxStyle(_comment),
    'keyword': SyntaxStyle(Color(0xFFBB9AF7)),
  },
  minTextContrast: minTextContrast,
);

const _captures = ['', 'comment', 'keyword'];

/// The rows of [_DimDiff], side by side:
///
///   old 0 / new 0  `// keep it`           unchanged (plain background)
///   old 1 / new 1  `// old note` / `// new note`  modified, the word changed
///   new 2          `let x // added`       inserted, no changed word
///   old 2 / new 3  `// end`               unchanged
///
/// Unified: keep, old note (deleted), new note, `let x // added`
/// (inserted), end.
final class _DimDiff {
  factory() {
    DiffLine line(
      int n,
      String text,
      LineKind kind,
      int block, {
      List<int> syntax = const [],
      List<int>? inner,
    }) => DiffLine(
      line: n,
      text: text,
      kind: kind,
      block: block,
      syntax: Uint32List.fromList(
        syntax.isEmpty ? [0, text.length, 1] : syntax,
      ),
      inner: inner == null ? null : Uint32List.fromList(inner),
    );
    final old = [
      line(0, '// keep it', LineKind.unchanged, -1),
      line(1, '// old note', LineKind.modified, 0, inner: [3, 3, innerChanged]),
      line(2, '// end', LineKind.unchanged, -1),
    ];
    final neu = [
      line(0, '// keep it', LineKind.unchanged, -1),
      line(1, '// new note', LineKind.modified, 0, inner: [3, 3, innerChanged]),
      line(2, 'let x // added', LineKind.added, 1, syntax: [0, 3, 2, 6, 8, 1]),
      line(3, '// end', LineKind.unchanged, -1),
    ];
    return _DimDiff._(
      DiffDocument(
        oldLineCount: 3,
        newLineCount: 4,
        blocks: const [
          DiffBlock(
            index: 0,
            kind: BlockKind.modified,
            old: ModelSpan(1, 2),
            neu: ModelSpan(1, 2),
          ),
          DiffBlock(
            index: 1,
            kind: BlockKind.inserted,
            old: ModelSpan(2, 2),
            neu: ModelSpan(2, 3),
          ),
        ],
        gaps: const [
          DiffGap(index: 0, old: ModelSpan(0, 1), neu: ModelSpan(0, 1)),
          DiffGap(index: 1, old: ModelSpan(2, 3), neu: ModelSpan(3, 4)),
        ],
        path: 'notes.txt',
      ),
      MemoryLineSource(old: old, neu: neu),
    );
  }
  new _(this.document, this.source);

  final DiffDocument document;
  final MemoryLineSource source;
}

/// One line a side, [oldText] / [newText], each a comment, with the
/// changed words [oldInner] / [newInner] (`start, length` pairs): a
/// modified line, or with [unchanged] an unchanged one.
(DiffDocument, MemoryLineSource) oneLine(
  String oldText,
  String newText, {
  required List<int> oldInner,
  required List<int> newInner,
  bool unchanged = false,
}) {
  DiffLine line(String text, List<int> inner) => DiffLine(
    line: 0,
    text: text,
    kind: unchanged ? LineKind.unchanged : LineKind.modified,
    block: unchanged ? -1 : 0,
    syntax: Uint32List.fromList([0, text.length, 1]),
    inner: Uint32List.fromList([
      for (var i = 0; i + 1 < inner.length; i += 2) ...[
        inner[i],
        inner[i + 1],
        innerChanged,
      ],
    ]),
  );
  return (
    DiffDocument(
      oldLineCount: 1,
      newLineCount: 1,
      blocks: [
        if (!unchanged)
          const DiffBlock(
            index: 0,
            kind: BlockKind.modified,
            old: ModelSpan(0, 1),
            neu: ModelSpan(0, 1),
          ),
      ],
      gaps: [
        if (unchanged)
          const DiffGap(index: 0, old: ModelSpan(0, 1), neu: ModelSpan(0, 1)),
      ],
      path: 'notes.txt',
    ),
    MemoryLineSource(
      old: [line(oldText, oldInner)],
      neu: [line(newText, newInner)],
    ),
  );
}

Future<DiffViewController> pumpDim(
  WidgetTester tester,
  DiffThemeData theme, {
  required bool unified,
  (DiffDocument, MemoryLineSource)? diff,
}) async {
  tester.view
    ..physicalSize = const Size(640, 160)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final d = _DimDiff();
  final c = DiffViewController(
    document: diff?.$1 ?? d.document,
    lines: diff?.$2 ?? d.source,
    theme: theme,
    captureNames: _captures,
    devicePixelRatio: 1,
    foldContext: -1,
  );
  addTearDown(c.dispose);
  Widget inlay(BuildContext context, InlaySpec spec) => const SizedBox();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: unified
          ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
          : SideBySideDiff(controller: c, theme: theme, inlayBuilder: inlay),
    ),
  );
  await tester.pump();
  return c;
}

/// The colour drawn at the centre of column [col] of row [row] in pane
/// [pane] (0 old, 1 new; the unified view has one). The test font draws
/// every glyph as a full box in the text colour.
Future<Color> glyphAt(
  WidgetTester tester,
  DiffViewController c, {
  required int row,
  required int col,
  int pane = 0,
}) async {
  final ro = tester
      .renderObjectList<RenderDiffPane>(find.byType(DiffPaneViewport))
      .elementAt(pane);
  final res = c.resources;
  final gutter = ro.unified == null ? res.gutter : res.unifiedGutter;
  final x = gutter.codeX + col * res.advance + res.advance / 2;
  final y = row * res.lineHeight + res.textTop + res.layouts.textHeight / 2;
  final layer = ro.debugLayer! as OffsetLayer;
  final pixel = await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & ro.size);
    final bytes = (await image.toByteData())!;
    image.dispose();
    return bytes.getUint32((y.floor() * image.width + x.floor()) * 4);
  });
  // RGBA → ARGB.
  final p = pixel!;
  return Color((p & 0xFF) << 24 | p >> 8);
}

Color expected(DiffThemeData t, Color? line, Color? word) => readableOn(
  _comment,
  compositeFill(t.background, line, word),
  background: t.background,
  minContrast: t.minTextContrast,
);

void main() {
  final on = dimCommentTheme(minTextContrast: 3);
  final off = dimCommentTheme();

  test('the made-up comments are dim on the tints', () {
    expect(contrastRatio(_comment, _background), inInclusiveRange(2.4, 2.8));
    for (final fill in [on.insertedLine, on.insertedWord, on.modifiedWord]) {
      expect(contrastRatio(_comment, fill), lessThan(2));
    }
  });

  group('side by side', () {
    // New pane: row 1 `// new note` with `new` (cols 3..5) changed, row 2
    // `let x // added` with the comment from col 6.
    testWidgets('off: every comment is drawn in its own colour', (
      tester,
    ) async {
      final c = await pumpDim(tester, off, unified: false);
      for (final pane in [0, 1]) {
        expect(await glyphAt(tester, c, pane: pane, row: 0, col: 3), _comment);
        expect(await glyphAt(tester, c, pane: pane, row: 1, col: 3), _comment);
        expect(await glyphAt(tester, c, pane: pane, row: 1, col: 7), _comment);
      }
      expect(await glyphAt(tester, c, pane: 1, row: 2, col: 9), _comment);
    });

    testWidgets('on: a dim comment on a changed word and line reads', (
      tester,
    ) async {
      final c = await pumpDim(tester, on, unified: false);
      // On the plain background: untouched, though it reads under 3.
      expect(await glyphAt(tester, c, pane: 1, row: 0, col: 3), _comment);
      // The changed word, then the rest of the same comment run on the
      // line's tint: the run is split at the word's edge.
      final onWord = await glyphAt(tester, c, pane: 1, row: 1, col: 3);
      final onLine = await glyphAt(tester, c, pane: 1, row: 1, col: 7);
      expect(onWord, expected(on, on.modifiedLine, on.modifiedWord));
      expect(onLine, expected(on, on.modifiedLine, null));
      expect(onWord, isNot(onLine));
      for (final got in [onWord, onLine]) {
        expect(
          got.computeLuminance(),
          greaterThan(_comment.computeLuminance()),
        );
      }
      // The old pane's changed word.
      expect(
        await glyphAt(tester, c, row: 1, col: 4),
        expected(on, on.modifiedLine, on.modifiedWord),
      );
      // An added line with no changed word.
      expect(
        await glyphAt(tester, c, pane: 1, row: 2, col: 9),
        expected(on, on.insertedLine, null),
      );
      // The keyword reads already and is not touched.
      expect(
        await glyphAt(tester, c, pane: 1, row: 2, col: 1),
        const Color(0xFFBB9AF7),
      );
    });

    testWidgets('on: repainting builds nothing again', (tester) async {
      final c = await pumpDim(tester, on, unified: false);
      final builds = c.resources.layouts.contrastBuilds;
      final resolved = c.resources.layouts.contrastResolved;
      expect(builds, greaterThan(0));
      for (var i = 0; i < 5; i++) {
        for (final ro in tester.renderObjectList<RenderDiffPane>(
          find.byType(DiffPaneViewport),
        )) {
          ro.markNeedsPaint();
        }
        await tester.pump();
      }
      expect(c.resources.layouts.contrastBuilds, builds);
      expect(c.resources.layouts.contrastResolved, resolved);
    });

    testWidgets('off: nothing is worked out', (tester) async {
      final c = await pumpDim(tester, off, unified: false);
      expect(c.resources.layouts.contrastBuilds, 0);
      expect(c.resources.layouts.contrastResolved, 0);
    });
  });

  group('unified', () {
    // Rows: 0 keep, 1 `// old note` (deleted), 2 `// new note`,
    // 3 `let x // added`, 4 end.
    testWidgets('off: every comment is drawn in its own colour', (
      tester,
    ) async {
      final c = await pumpDim(tester, off, unified: true);
      for (final (row, col) in [(0, 3), (1, 3), (1, 7), (2, 3), (3, 9)]) {
        expect(
          await glyphAt(tester, c, row: row, col: col),
          _comment,
          reason: 'row $row col $col',
        );
      }
    });

    testWidgets('on: deleted and inserted rows read on their fills', (
      tester,
    ) async {
      final c = await pumpDim(tester, on, unified: true);
      expect(await glyphAt(tester, c, row: 0, col: 3), _comment);
      // The deleted row uses the unified deleted fills, translucent and
      // composited over the background.
      final deletedWord = await glyphAt(tester, c, row: 1, col: 3);
      expect(
        deletedWord,
        expected(on, on.unifiedDeletedLine, on.unifiedDeletedWord),
      );
      expect(deletedWord, isNot(_comment));
      expect(
        await glyphAt(tester, c, row: 1, col: 7),
        expected(on, on.unifiedDeletedLine, null),
      );
      // The modified new line is an insertion here.
      expect(
        await glyphAt(tester, c, row: 2, col: 3),
        expected(on, on.insertedLine, on.insertedWord),
      );
      expect(
        await glyphAt(tester, c, row: 3, col: 9),
        expected(on, on.insertedLine, null),
      );
    });
  });

  group('a word edge inside a surrogate pair', () {
    // An emoji whose two code units a character diff split: the old
    // side's word is its low half, the new side's its high half.
    final diff = oneLine(
      '// \u{1F600} done',
      '// \u{1F601} done',
      oldInner: [4, 1],
      newInner: [3, 1],
    );
    for (final unified in [false, true]) {
      testWidgets(unified ? 'unified' : 'side by side', (tester) async {
        final c = await pumpDim(tester, on, unified: unified, diff: diff);
        expect(tester.takeException(), isNull);
        // The comment was recoloured, the emoji kept whole.
        expect(c.resources.layouts.contrastBuilds, greaterThan(0));
        for (final ro in tester.renderObjectList<RenderDiffPane>(
          find.byType(DiffPaneViewport),
        )) {
          ro.markNeedsPaint();
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    test('a paragraph is built with the pair whole', () {
      final b = LineLayoutBuilder(on, _captures);
      for (final inner in [
        [1, 1],
        [2, 1],
        [0, 2],
        [2, 2],
      ]) {
        final line = DiffLine(
          line: 0,
          text: 'a\u{1F600}b',
          kind: LineKind.modified,
          block: 0,
          syntax: Uint32List.fromList([0, 4, 1]),
          inner: Uint32List.fromList([inner[0], inner[1], innerChanged]),
        );
        final layout = b.build(line);
        final p = layout.paragraphOn(b, line, on.modifiedLine, on.modifiedWord);
        expect(p.width, greaterThan(0), reason: '$inner');
        layout.dispose();
      }
    });
  });

  group('changed words', () {
    testWidgets('on an unchanged row only the words are recoloured', (
      tester,
    ) async {
      // A row with no line tint whose inner spans still paint, in the
      // modified word tint: the text outside them is on the background.
      final diff = oneLine(
        '// keep note',
        '// keep note',
        oldInner: [3, 4],
        newInner: [3, 4],
        unchanged: true,
      );
      for (final unified in [false, true]) {
        final c = await pumpDim(tester, on, unified: unified, diff: diff);
        final inWord = expected(on, null, on.modifiedWord);
        expect(inWord, isNot(_comment));
        expect(await glyphAt(tester, c, row: 0, col: 4), inWord);
        expect(await glyphAt(tester, c, row: 0, col: 0), _comment);
        expect(await glyphAt(tester, c, row: 0, col: 9), _comment);
      }
    });

    test('new words on the same text get a new paragraph', () {
      final b = LineLayoutBuilder(on, _captures);
      DiffLine line(List<int> inner) => DiffLine(
        line: 0,
        text: '// one two',
        kind: LineKind.modified,
        block: 0,
        syntax: Uint32List.fromList([0, 10, 1]),
        inner: Uint32List.fromList(inner),
      );
      final first = line([3, 3, innerChanged]);
      final second = line([7, 3, innerChanged]);
      expect(first.sameLayoutAs(second), isTrue);
      final layout = b.build(first);
      final a = layout.paragraphOn(b, first, on.modifiedLine, on.modifiedWord);
      expect(b.contrastBuilds, 1);
      // The same words in a new list: kept.
      final again = line([3, 3, innerChanged]);
      expect(
        layout.paragraphOn(b, again, on.modifiedLine, on.modifiedWord),
        same(a),
      );
      expect(b.contrastBuilds, 1);
      final c = layout.paragraphOn(b, second, on.modifiedLine, on.modifiedWord);
      expect(c, isNot(same(a)));
      expect(b.contrastBuilds, 2);
      layout.dispose();
    });
  });

  group('goldens', () {
    testWidgets('side by side, dim comments at a least contrast', (
      tester,
    ) async {
      await pumpDim(tester, on, unified: false);
      await expectLater(
        find.byType(SideBySideDiff),
        matchesGoldenFile('goldens/side_by_side_min_contrast.png'),
      );
    });

    testWidgets('unified, dim comments at a least contrast', (tester) async {
      await pumpDim(tester, on, unified: true);
      await expectLater(
        find.byType(UnifiedDiff),
        matchesGoldenFile('goldens/unified_min_contrast.png'),
      );
    });
  });
}
