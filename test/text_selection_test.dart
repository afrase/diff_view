import 'dart:ui' show PointerDeviceKind;

import 'package:diff_view/diff_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A paging source: only the lines [load] has returned are in memory.
final class PagedSource implements DiffLineSource {
  new(this.old, this.neu);

  final List<DiffLine> old;
  final List<DiffLine> neu;
  final List<(PaneSide, ModelSpan)> loads = [];
  final Set<(PaneSide, int)> _loaded = {};

  List<DiffLine> _side(PaneSide side) => side == PaneSide.old ? old : neu;

  @override
  DiffLine? lineAt(PaneSide side, int line) =>
      _loaded.contains((side, line)) ? _side(side)[line] : null;

  @override
  void prefetch(PaneSide side, ModelSpan span) {}

  @override
  Future<List<DiffLine>> load(PaneSide side, ModelSpan span) async {
    loads.add((side, span));
    for (var l = span.start; l < span.end; l++) {
      _loaded.add((side, l));
    }
    return _side(side).sublist(span.start, span.end);
  }

  @override
  void addListener(void Function() listener) {}

  @override
  void removeListener(void Function() listener) {}
}

DiffLine line(int n, String text, {LineEnding ending = LineEnding.lf}) =>
    DiffLine(line: n, text: text, ending: ending);

/// Records what is written to the clipboard.
String? Function() mockClipboard(WidgetTester tester) {
  String? clipboard;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return () => clipboard;
}

DiffViewController controllerOf(
  SyntheticDiff d, {
  int foldContext = -1,
  DiffLineSource? lines,
}) => DiffViewController(
  document: d.document,
  lines: lines ?? d.source,
  theme: DiffThemeData.light(),
  captureNames: testCaptures,
  foldContext: foldContext,
);

void main() {
  group('the controller', () {
    test('one selection at a time, and selectionChanges fires', () {
      final c = controllerOf(SyntheticDiff(const [Eq(5), Mod(2, 2), Eq(5)]));
      addTearDown(c.dispose);
      var changes = 0;
      c.selectionChanges.addListener(() => changes++);
      final ValueListenable<CodeSelection?> text = c.textSelection;
      c.selection.start(PaneSide.neu, 2);
      c.unifiedSelection.start(4);
      changes = 0;
      const s = CodeSelection(
        side: PaneSide.old,
        anchor: CodePosition(1, 0),
        focus: CodePosition(2, 3),
      );
      c.textSelection.select(s);
      expect(text.value, s);
      expect(c.selection.value, isNull);
      expect(c.unifiedSelection.value, isNull);
      expect(changes, greaterThanOrEqualTo(1));

      changes = 0;
      c.selection.start(PaneSide.old, 4);
      expect(text.value, isNull);
      expect(changes, greaterThanOrEqualTo(1));

      c.textSelection.select(s);
      c.unifiedSelection.start(1);
      expect(text.value, isNull);

      c.textSelection.select(s);
      changes = 0;
      c.clearTextSelection();
      expect(text.value, isNull);
      expect(changes, 1);
    });

    test('turning text selection off clears it', () {
      final c = controllerOf(SyntheticDiff(const [Eq(5)]));
      addTearDown(c.dispose);
      expect(c.textSelectionEnabled, isTrue);
      c.textSelection.select(
        const CodeSelection(
          side: PaneSide.neu,
          anchor: CodePosition(0, 0),
          focus: CodePosition(1, 0),
        ),
      );
      c.textSelectionEnabled = false;
      expect(c.textSelection.value, isNull);
      final off = DiffViewController(
        document: c.document,
        lines: c.lines,
        theme: DiffThemeData.light(),
        textSelectionEnabled: false,
      );
      addTearDown(off.dispose);
      expect(off.textSelectionEnabled, isFalse);
    });
  });

  group('textOf', () {
    final old = [
      line(0, 'alpha'),
      line(1, 'beta', ending: LineEnding.crlf),
      line(2, 'gamma'),
      line(3, 'last', ending: LineEnding.none),
    ];
    final neu = [
      line(0, 'alpha'),
      line(1, 'BETA'),
      line(2, 'gamma'),
      line(3, 'last'),
      line(4, 'more'),
    ];
    final doc = DiffDocument(
      oldLineCount: 4,
      newLineCount: 5,
      blocks: const [
        DiffBlock(
          index: 0,
          kind: BlockKind.modified,
          old: ModelSpan(1, 2),
          neu: ModelSpan(1, 2),
        ),
        DiffBlock(
          index: 1,
          kind: BlockKind.modified,
          old: ModelSpan(3, 4),
          neu: ModelSpan(3, 5),
        ),
      ],
      gaps: const [
        DiffGap(index: 0, old: ModelSpan(0, 1), neu: ModelSpan(0, 1)),
        DiffGap(index: 1, old: ModelSpan(2, 3), neu: ModelSpan(2, 3)),
      ],
    );

    DiffViewController make(DiffLineSource source) {
      final c = DiffViewController(
        document: doc,
        lines: source,
        theme: DiffThemeData.light(),
        foldContext: -1,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('the text as shown, joined by each line end, loading lines', () async {
      final source = PagedSource(old, neu);
      final c = make(source);
      final text = await c.textOf(
        const CodeSelection(
          side: PaneSide.old,
          anchor: CodePosition(3, 2),
          focus: CodePosition(0, 3),
        ),
      );
      expect(text, 'ha\nbeta\r\ngamma\nla');
      expect(source.loads, [(PaneSide.old, const ModelSpan(0, 4))]);
      // Within one line, and a column past the end is clamped.
      expect(
        await c.textOf(
          const CodeSelection(
            side: PaneSide.neu,
            anchor: CodePosition(1, 1),
            focus: CodePosition(1, 99),
          ),
        ),
        'ETA',
      );
      // Ending at the start of a line takes the line end before it.
      expect(
        await c.textOf(
          const CodeSelection(
            side: PaneSide.neu,
            anchor: CodePosition(0, 0),
            focus: CodePosition(1, 0),
          ),
        ),
        'alpha\n',
      );
    });

    test('a unified selection copies its rows in order', () async {
      final c = make(MemoryLineSource(old: old, neu: neu));
      // Rows: c alpha, d beta, i BETA, c gamma, d last, i last, i more.
      expect(c.unifiedRows.rowCount, 7);
      final text = await c.textOf(
        const CodeSelection.unified(
          anchor: CodePosition(1, 2),
          focus: CodePosition(5, 2),
        ),
      );
      // The old last line has no terminator; the next row's one joins it.
      expect(text, 'ta\r\nBETA\ngamma\nlast\nla');
    });

    test('across a fold only the shown lines are copied', () async {
      final d = SyntheticDiff(const [Mod(1, 1), Eq(30), Mod(1, 1)]);
      final c = controllerOf(d, foldContext: 2);
      addTearDown(c.dispose);
      final g = c.geometry(PaneSide.neu);
      expect(g.isRowVisible(10), isFalse, reason: 'the fold hides line 10');
      final text = await c.textOf(
        const CodeSelection(
          side: PaneSide.neu,
          anchor: CodePosition(0, 1),
          focus: CodePosition(31, 5),
        ),
      );
      final shown = [
        for (var r = 0; r <= 31; r++)
          if (g.isRowVisible(r)) d.neu[r].text,
      ];
      expect(shown.length, lessThan(32));
      final expected = [
        shown.first.substring(1),
        ...shown.sublist(1, shown.length - 1),
        shown.last.substring(0, 5),
      ].join('\n');
      expect(text, expected);
      expect(text, isNot(contains('same 10')));

      // The same in the unified view.
      final u = c.unifiedGeometry;
      final rows = c.unifiedRows;
      final last = rows.rowCount - 1;
      final unified = await c.textOf(
        CodeSelection.unified(
          anchor: const CodePosition(0, 0),
          focus: CodePosition(last, 3),
        ),
      );
      expect(unified, isNot(contains('same 10')));
      final count = [
        for (var r = 0; r <= last; r++)
          if (u.isRowVisible(r)) r,
      ].length;
      expect('\n'.allMatches(unified).length, count - 1);
    });

    test('a copy across a fold loads only the shown lines', () async {
      final d = SyntheticDiff(const [Mod(1, 1), Eq(400), Mod(1, 1)]);
      final source = PagedSource(d.old, d.neu);
      final c = controllerOf(d, foldContext: 2, lines: source);
      addTearDown(c.dispose);
      bool anyHidden(PaneGeometry g, PaneSide side, int Function(int) rowOf) =>
          source.loads.any(
            (load) =>
                load.$1 == side &&
                [for (var l = load.$2.start; l < load.$2.end; l++) l]
                    .any((l) => !g.isRowVisible(rowOf(l))),
          );

      final g = c.geometry(PaneSide.neu);
      final text = await c.textOf(
        CodeSelection(
          side: PaneSide.neu,
          anchor: const CodePosition(0, 0),
          focus: CodePosition(g.rowCount - 1, 2),
        ),
      );
      expect(text, isNot(contains('same 200')));
      expect(anyHidden(g, PaneSide.neu, (l) => l), isFalse);

      source.loads.clear();
      final rows = c.unifiedRows;
      final u = c.unifiedGeometry;
      await c.textOf(
        CodeSelection.unified(
          anchor: const CodePosition(0, 0),
          focus: CodePosition(rows.rowCount - 1, 2),
        ),
      );
      expect(source.loads, isNotEmpty);
      for (final side in PaneSide.values) {
        expect(
          anyHidden(u, side, (l) => rows.rowOf(side, l)),
          isFalse,
          reason: 'no hidden ${side.name} line is loaded',
        );
      }
    });
  });

  testWidgets('copySelection copies whichever selection there is', (
    tester,
  ) async {
    final clipboard = mockClipboard(tester);
    final d = SyntheticDiff(const [Eq(3), Mod(1, 1), Eq(3)]);
    final c = controllerOf(d);
    addTearDown(c.dispose);
    expect(await c.copySelection(), isNull);

    c.textSelection.select(
      const CodeSelection(
        side: PaneSide.neu,
        anchor: CodePosition(3, 1),
        focus: CodePosition(4, 5),
      ),
    );
    final text = await c.copySelection();
    expect(
      text,
      '${d.neu[3].text.substring(1)}\n${d.neu[4].text.substring(0, 5)}',
    );
    expect(clipboard(), text);

    c.selection.start(PaneSide.old, 2);
    expect(await c.copySelection(), '${d.old[2].text}\n');

    c.unifiedSelection.start(0);
    c.selection.clear();
    expect(await c.copySelection(), '${d.neu[0].text}\n');
  });

  for (final unified in [false, true]) {
    group(unified ? 'unified view' : 'side-by-side view', () {
      viewTests(unified: unified);
    });
  }
}

/// A view of the golden diff (a changed block, a fold, a deletion) with
/// helpers that point at code in the new pane or the unified column.
final class View {
  new(this.tester, this.c, this.d, {required this.unified});

  final WidgetTester tester;
  final DiffViewController c;
  final SyntheticDiff d;
  final bool unified;

  PaneGeometry get g => unified ? c.unifiedGeometry : c.geometry(PaneSide.neu);

  ScrollPosition get position =>
      (unified ? c.unifiedScroll : c.scroll(PaneSide.neu)).position;

  GutterMetrics get gutter =>
      unified ? c.resources.unifiedGutter : c.resources.gutter;

  Finder get pane =>
      unified ? find.byType(UnifiedDiff) : find.byType(DiffPane).last;

  /// The row that shows new line [line].
  int rowOfNew(int line) =>
      unified ? c.unifiedRows.rowOf(PaneSide.neu, line) : line;

  /// The text [row] shows.
  String text(int row) {
    if (!unified) return d.neu[row].text;
    final rows = c.unifiedRows;
    final side = rows.textSideAt(row);
    final line = rows.lineAt(side, row);
    return (side == PaneSide.old ? d.old : d.neu)[line].text;
  }

  /// A selection in this view.
  CodeSelection selection(CodePosition anchor, CodePosition focus) => unified
      ? CodeSelection.unified(anchor: anchor, focus: focus)
      : CodeSelection(side: PaneSide.neu, anchor: anchor, focus: focus);

  /// The global point of [column] in [row]. Every synthetic line starts
  /// with a tab (four columns); the test font is one advance a glyph.
  Offset at(int row, int column) {
    final col = column == 0 ? 0 : column + 3;
    final a = c.resources.advance;
    return tester.getTopLeft(pane) +
        Offset(
          gutter.codeX + col * a + 0.5,
          g.topOfRow(row) - position.pixels + g.lineHeight / 2,
        );
  }

  /// A point in the gutter of [row].
  Offset gutterAt(int row) =>
      tester.getTopLeft(pane) +
      Offset(
        gutter.numberRight - 4,
        g.topOfRow(row) - position.pixels + g.lineHeight / 2,
      );

  Future<TestGesture> down(Offset at) async {
    final gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    return gesture;
  }

  Future<void> click(Offset at) async {
    final gesture = await down(at);
    await gesture.up();
    await tester.pump();
  }

  Future<void> drag(Offset from, Offset to) async {
    final gesture = await down(from);
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  /// Lets the multi-click time run out.
  Future<void> wait() => tester.pump(const Duration(milliseconds: 500));

  Future<void> key(LogicalKeyboardKey key, {bool meta = false}) async {
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(key);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
  }

  Future<void> shiftClick(Offset at) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await click(at);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
  }
}

Future<View> pumpView(
  WidgetTester tester, {
  required bool unified,
  bool enabled = true,
  InlayBuilder? inlayBuilder,
  List<Seg> segs = const [
    Eq(3),
    Mod(2, 3),
    Eq(2),
    Ins(2),
    Eq(30),
    Del(3),
    Eq(4),
    Mod(1, 1),
    Eq(3),
  ],
}) async {
  tester.view
    ..physicalSize = const Size(1600, 1200)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final d = SyntheticDiff(segs);
  final c = DiffViewController(
    document: d.document,
    lines: d.source,
    theme: DiffThemeData.light(),
    captureNames: testCaptures,
    textSelectionEnabled: enabled,
  );
  addTearDown(c.dispose);
  final theme = DiffThemeData.light();
  final inlay =
      inlayBuilder ??
      (context, spec) => SizedBox(height: 60, child: Text('inlay ${spec.id}'));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: unified
            ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
            : SideBySideDiff(controller: c, theme: theme, inlayBuilder: inlay),
      ),
    ),
  );
  await tester.pump();
  return View(tester, c, d, unified: unified);
}

void viewTests({required bool unified}) {
  testWidgets('a drag selects by character across lines; Cmd+C copies', (
    tester,
  ) async {
    final clipboard = mockClipboard(tester);
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    c.selection.start(PaneSide.neu, 0);
    final gesture = await v.down(v.at(1, 2));
    expect(c.selection.value, isNull, reason: 'a text drag clears lines');
    expect(c.textSelection.value, isNull, reason: 'nothing dragged yet');
    await gesture.moveTo(v.at(2, 6));
    await tester.pump();
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(1, 2), const CodePosition(2, 6)),
    );
    // Back up above the anchor: the focus follows.
    await gesture.moveTo(v.at(0, 3));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    final sel = c.textSelection.value!;
    expect(sel.anchor, const CodePosition(1, 2));
    expect(sel.focus, const CodePosition(0, 3));
    await v.key(LogicalKeyboardKey.keyC, meta: true);
    expect(
      clipboard(),
      '${v.text(0).substring(3)}\n${v.text(1).substring(0, 2)}',
    );
  });

  testWidgets('a double click selects a word, a triple click a line', (
    tester,
  ) async {
    final clipboard = mockClipboard(tester);
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    // `\tfunc f("same 0")`: offsets 1 to 5 are `func`.
    await v.click(v.at(0, 3));
    expect(c.textSelection.value, isNull);
    await v.click(v.at(0, 3));
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(0, 1), const CodePosition(0, 5)),
    );
    await v.click(v.at(0, 3));
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(0, 0), const CodePosition(1, 0)),
    );
    expect(await c.copySelection(), '${v.text(0)}\n');
    expect(clipboard(), '${v.text(0)}\n');

    // Too late for a double click: a click clears it.
    await v.wait();
    await v.click(v.at(2, 3));
    await v.wait();
    await v.click(v.at(2, 3));
    expect(c.textSelection.value, isNull);

    // A drag after a double click extends by words.
    await v.wait();
    await v.click(v.at(1, 3));
    final gesture = await v.down(v.at(1, 3));
    await gesture.moveTo(v.at(2, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    // `\tfunc f("same 2")`: offset 10 is in `same` (9 to 13).
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(1, 1), const CodePosition(2, 13)),
    );
  });

  testWidgets('shift-click extends; a click elsewhere or Escape clears', (
    tester,
  ) async {
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    await v.drag(v.at(0, 2), v.at(0, 4));
    await v.shiftClick(v.at(2, 5));
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(0, 2), const CodePosition(2, 5)),
    );
    await v.wait();
    await v.click(v.at(1, 1));
    expect(c.textSelection.value, isNull);

    await v.drag(v.at(0, 2), v.at(1, 4));
    expect(c.textSelection.value, isNotNull);
    await v.key(LogicalKeyboardKey.escape);
    expect(c.textSelection.value, isNull);

    // A gutter click starts a line selection and clears the text one.
    await v.drag(v.at(0, 2), v.at(1, 4));
    await v.wait();
    await v.click(v.gutterAt(2));
    expect(c.textSelection.value, isNull);
    if (unified) {
      expect(c.unifiedSelection.value, isNotNull);
    } else {
      expect(c.selection.value, isNotNull);
    }
    // And a text drag clears the line selection.
    await v.wait();
    await v.drag(v.at(0, 2), v.at(1, 4));
    expect(c.selection.value, isNull);
    expect(c.unifiedSelection.value, isNull);
    expect(c.textSelection.value, isNotNull);
  });

  testWidgets('shift-click extends from the last click', (tester) async {
    mockClipboard(tester);
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    var changes = 0;
    c.selectionChanges.addListener(() => changes++);
    await v.click(v.at(0, 2));
    expect(c.textSelection.value, isNull, reason: 'a click selects nothing');
    expect(changes, 0, reason: 'the place of a click is no selection');
    await v.shiftClick(v.at(2, 5));
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(0, 2), const CodePosition(2, 5)),
    );
    expect(
      await c.copySelection(),
      '${v.text(0).substring(2)}\n${v.text(1)}\n${v.text(2).substring(0, 5)}',
    );
  });

  testWidgets('shift-click before the last click selects backwards', (
    tester,
  ) async {
    mockClipboard(tester);
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    await v.click(v.at(2, 5));
    await v.shiftClick(v.at(1, 3));
    expect(
      c.textSelection.value,
      v.selection(const CodePosition(2, 5), const CodePosition(1, 3)),
    );
    expect(
      await c.copySelection(),
      '${v.text(1).substring(3)}\n${v.text(2).substring(0, 5)}',
    );
  });

  testWidgets('after Escape or clearTextSelection, shift-click selects '
      'nothing', (tester) async {
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    await v.drag(v.at(0, 2), v.at(1, 4));
    await v.key(LogicalKeyboardKey.escape);
    await v.shiftClick(v.at(2, 5));
    expect(c.textSelection.value, isNull);

    // Escape with only a click's place clears it too.
    await v.wait();
    await v.click(v.at(0, 2));
    await v.key(LogicalKeyboardKey.escape);
    await v.shiftClick(v.at(2, 5));
    expect(c.textSelection.value, isNull);

    await v.wait();
    await v.click(v.at(0, 2));
    c.clearTextSelection();
    await v.shiftClick(v.at(2, 5));
    expect(c.textSelection.value, isNull);
  });

  testWidgets('a gutter selection or turning selection off forgets the '
      'last click', (tester) async {
    final v = await pumpView(tester, unified: unified);
    final c = v.c;
    await v.click(v.at(0, 2));
    await v.wait();
    await v.click(v.gutterAt(3));
    await v.wait();
    await v.shiftClick(v.at(2, 5));
    expect(c.textSelection.value, isNull);

    await v.wait();
    await v.click(v.at(0, 2));
    c
      ..textSelectionEnabled = false
      ..textSelectionEnabled = true;
    await v.shiftClick(v.at(2, 5));
    expect(c.textSelection.value, isNull);
  });

  testWidgets('with text selection off, shift-click selects nothing', (
    tester,
  ) async {
    final v = await pumpView(tester, unified: unified, enabled: false);
    await v.click(v.at(0, 2));
    await v.shiftClick(v.at(2, 5));
    expect(v.c.textSelection.value, isNull);
  });

  if (!unified) {
    testWidgets('shift-click in the other pane places a new click there', (
      tester,
    ) async {
      final v = await pumpView(tester, unified: false);
      final c = v.c;
      final old = tester.getTopLeft(find.byType(DiffPane).first);
      // Old line 1, then new line 2: no selection across panes.
      final shift = old.dx - tester.getTopLeft(v.pane).dx;
      await v.click(v.at(1, 2).translate(shift, 0));
      await v.shiftClick(v.at(2, 5));
      expect(c.textSelection.value, isNull);
      // That Shift-click is now the place a Shift-click extends from.
      await v.shiftClick(v.at(3, 1));
      expect(
        c.textSelection.value,
        v.selection(const CodePosition(2, 5), const CodePosition(3, 1)),
      );
    });

    testWidgets('a click in the other pane clears it', (tester) async {
      final v = await pumpView(tester, unified: false);
      await v.drag(v.at(0, 2), v.at(1, 4));
      expect(v.c.textSelection.value, isNotNull);
      final old = tester.getTopLeft(find.byType(DiffPane).first);
      await v.click(old + const Offset(200, 30));
      expect(v.c.textSelection.value, isNull);
    });
  }

  testWidgets('dragging past the bottom edge scrolls', (tester) async {
    final v = await pumpView(
      tester,
      unified: unified,
      segs: const [Mod(1, 1), Eq(200), Mod(1, 1)],
    );
    final c = v.c;
    c.folds.expandAll(0);
    await tester.pump();
    v.position.jumpTo(0);
    await tester.pump();
    final gesture = await v.down(v.at(1, 2));
    final bottom = tester.getBottomLeft(v.pane);
    await gesture.moveTo(Offset(v.at(1, 4).dx, bottom.dy + 20));
    for (var i = 0; i < 100 && v.position.pixels < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(v.position.pixels, greaterThanOrEqualTo(400));
    final focus = c.textSelection.value!.focus;
    expect(
      v.g.topOfRow(focus.line) - v.position.pixels,
      greaterThan(v.position.viewportDimension - 2 * v.g.lineHeight),
      reason: 'the focus follows the scroll to the bottom edge',
    );
    await gesture.up();
    await tester.pump();
    expect(c.textSelection.value!.anchor, const CodePosition(1, 2));
  });

  testWidgets('a selection across a fold copies only what is shown', (
    tester,
  ) async {
    mockClipboard(tester);
    final v = await pumpView(tester, unified: unified);
    final fold = v.g.hiddenSpans.first;
    final above = fold.start - 1;
    final below = fold.end;
    await v.drag(v.at(above, 2), v.at(below, 4));
    expect(
      v.c.textSelection.value,
      v.selection(CodePosition(above, 2), CodePosition(below, 4)),
    );
    final text = await v.c.copySelection();
    expect(
      text,
      '${v.text(above).substring(2)}\n${v.text(below).substring(0, 4)}',
    );
  });

  testWidgets('a selection passes over an inlay in a change', (tester) async {
    mockClipboard(tester);
    final v = await pumpView(tester, unified: unified);
    // New lines 3 to 5 are the first change; the inlay sits after line 4.
    final c = v.c
      ..addInlay(const InlaySpec(id: 'note', side: PaneSide.neu, afterLine: 4));
    await tester.pump();
    await tester.pump();
    final r3 = v.rowOfNew(3);
    final r4 = v.rowOfNew(4);
    final r5 = v.rowOfNew(5);
    final inlay = tester.getCenter(find.text('inlay note'));
    final gesture = await v.down(v.at(r3, 2));
    await gesture.moveTo(Offset(v.at(r3, 2).dx, inlay.dy));
    await tester.pump();
    expect(
      c.textSelection.value!.focus,
      CodePosition(r4, v.text(r4).length),
      reason: 'over the inlay the focus is the end of the row above',
    );
    await gesture.moveTo(v.at(r5, 4));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(c.textSelection.value!.focus, CodePosition(r5, 4));
    final text = await c.copySelection();
    expect(
      text,
      '${v.text(r3).substring(2)}\n${v.text(r4)}\n'
      '${v.text(r5).substring(0, 4)}',
    );
    expect(text, isNot(contains('inlay')));

    // A click on the inlay neither starts nor clears a selection.
    await v.wait();
    await v.click(inlay);
    expect(c.textSelection.value, isNotNull);
  });

  testWidgets('a text field in an inlay keeps its own copy and Escape', (
    tester,
  ) async {
    final clipboard = mockClipboard(tester);
    final field = TextEditingController(text: 'comment text');
    addTearDown(field.dispose);
    final v = await pumpView(
      tester,
      unified: unified,
      inlayBuilder: (context, spec) =>
          SizedBox(height: 60, child: TextField(controller: field)),
    );
    final c = v.c;
    await v.drag(v.at(0, 1), v.at(0, 3));
    expect(c.textSelection.value, isNotNull);
    c.addInlay(const InlaySpec(id: 'note', side: PaneSide.neu, afterLine: 4));
    await tester.pump();
    await tester.pump();
    await v.wait();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    field.selection = const TextSelection(baseOffset: 0, extentOffset: 7);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(clipboard(), 'comment');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(
      c.textSelection.value,
      isNotNull,
      reason: "Escape in the field is the field's",
    );
  });

  testWidgets('a text cursor over code, as before over the gutter', (
    tester,
  ) async {
    final v = await pumpView(tester, unified: unified);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: v.gutterAt(1));
    await tester.pump();
    final tracker = RendererBinding.instance.mouseTracker;
    expect(tracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
    await mouse.moveTo(v.at(1, 3));
    await tester.pump();
    expect(tracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
    await mouse.moveTo(v.gutterAt(2));
    await tester.pump();
    expect(tracker.debugDeviceActiveCursor(1), SystemMouseCursors.basic);
  });

  testWidgets('with text selection off, code takes no selection', (
    tester,
  ) async {
    final v = await pumpView(tester, unified: unified, enabled: false);
    final c = v.c;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: v.gutterAt(1));
    await mouse.moveTo(v.at(1, 3));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );
    await mouse.removePointer();
    await v.drag(v.at(0, 2), v.at(1, 4));
    expect(c.textSelection.value, isNull);
    await v.click(v.at(0, 3));
    await v.click(v.at(0, 3));
    expect(c.textSelection.value, isNull);
    // The gutter still selects lines.
    await v.wait();
    await v.click(v.gutterAt(2));
    expect(unified ? c.unifiedSelection.value : c.selection.value, isNotNull);
  });
}
