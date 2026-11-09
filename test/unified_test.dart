import 'dart:ui';

import 'package:diff_view/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Row [row] as `kind old new` (`-` for a missing line).
String describe(UnifiedRows rows, int row) {
  String n(int line) => line < 0 ? '-' : '$line';
  final kind = switch (rows.kindAt(row)) {
    UnifiedRowKind.context => 'c',
    UnifiedRowKind.deleted => 'd',
    UnifiedRowKind.inserted => 'i',
  };
  return '$kind ${n(rows.oldLineAt(row))} ${n(rows.newLineAt(row))}';
}

List<String> describeAll(UnifiedRows rows) => [
  for (var r = 0; r < rows.rowCount; r++) describe(rows, r),
];

/// 30 repetitions of (40 equal, modified 3/5, 20 equal, inserted 4,
/// 10 equal, deleted 2): about 2,300 lines a side.
SyntheticDiff bigDiff() => SyntheticDiff([
  for (var i = 0; i < 30; i++) ...const [
    Eq(40),
    Mod(3, 5),
    Eq(20),
    Ins(4),
    Eq(10),
    Del(2),
  ],
  const Eq(12),
]);

class Harness {
  new(this.diff, {int foldContext = 4})
    : controller = DiffViewController(
        document: diff.document,
        lines: diff.source,
        theme: DiffThemeData.light(),
        captureNames: testCaptures,
        foldContext: foldContext,
      );

  final SyntheticDiff diff;
  final DiffViewController controller;
  final Map<String, double> heights = {};

  Widget app({bool unified = true}) {
    Widget inlay(BuildContext context, InlaySpec spec) =>
        SizedBox(height: heights[spec.id] ?? 60, child: Text(spec.id));
    return MaterialApp(
      home: Scaffold(
        body: unified
            ? UnifiedDiff(
                controller: controller,
                theme: DiffThemeData.light(),
                inlayBuilder: inlay,
              )
            : SideBySideDiff(
                controller: controller,
                theme: DiffThemeData.light(),
                inlayBuilder: inlay,
              ),
      ),
    );
  }

  PaneGeometry get g => controller.unifiedGeometry;

  ScrollPosition get pos => controller.unifiedScroll.position;

  /// Viewport y of [row].
  double y(int row) => g.topOfRow(row) - pos.pixels;
}

Future<Harness> pumpHarness(
  WidgetTester tester, {
  int foldContext = 4,
  SyntheticDiff? diff,
}) async {
  tester.view
    ..physicalSize = const Size(1600, 1200)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final h = Harness(diff ?? bigDiff(), foldContext: foldContext);
  addTearDown(h.controller.dispose);
  await tester.pumpWidget(h.app());
  await tester.pump();
  return h;
}

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

void main() {
  group('UnifiedRows', () {
    test('unchanged lines once, then each block: deleted, then inserted', () {
      final d = SyntheticDiff(const [
        Eq(2),
        Mod(2, 3),
        Eq(1),
        Ins(2),
        Eq(1),
        Del(2),
        Eq(1),
      ]);
      final rows = UnifiedRows.build(d.document);
      expect(describeAll(rows), [
        'c 0 0',
        'c 1 1',
        'd 2 -',
        'd 3 -',
        'i - 2',
        'i - 3',
        'i - 4',
        'c 4 5',
        'i - 6',
        'i - 7',
        'c 5 8',
        'd 6 -',
        'd 7 -',
        'c 8 9',
      ]);
      expect(rows.rowOf(PaneSide.old, 4), 7);
      expect(rows.rowOf(PaneSide.neu, 5), 7);
      expect(rows.rowOf(PaneSide.old, 7), 12);
      expect(rows.textSideAt(7), PaneSide.neu);
      expect(rows.textSideAt(11), PaneSide.old);
      expect(rows.lineAt(PaneSide.old, 11), 6);
      final lines = rows.linesIn(const ModelSpan(3, 9));
      expect(lines.old, const ModelSpan(3, 5));
      expect(lines.neu, const ModelSpan(2, 7));
      expect(rows.rowsOf(old: const ModelSpan(4, 6)), const ModelSpan(7, 11));
      expect(
        rows.rowsOf(old: const ModelSpan(6, 7), neu: const ModelSpan(8, 10)),
        const ModelSpan(10, 14),
      );
      expect(rows.rowsOf(old: const ModelSpan.empty(3)), isNull);
    });

    test('an added file is all inserted rows, a deleted one all deleted', () {
      final added = UnifiedRows.build(SyntheticDiff(const [Ins(3)]).document);
      expect(describeAll(added), ['i - 0', 'i - 1', 'i - 2']);
      expect(added.linesIn(const ModelSpan(0, 3)).old.isEmpty, isTrue);
      final deleted = UnifiedRows.build(SyntheticDiff(const [Del(2)]).document);
      expect(describeAll(deleted), ['d 0 -', 'd 1 -']);
      expect(deleted.textSideAt(1), PaneSide.old);
    });

    test('an empty diff has no rows', () {
      final rows = UnifiedRows.build(SyntheticDiff(const []).document);
      expect(rows.rowCount, 0);
      final lines = rows.linesIn(const ModelSpan.empty(0));
      expect(lines.old.isEmpty && lines.neu.isEmpty, isTrue);
    });

    test('an unchanged region of unequal lengths pairs what it can', () {
      final doc = DiffDocument(
        oldLineCount: 3,
        newLineCount: 2,
        blocks: const [],
        gaps: const [
          DiffGap(index: 0, old: ModelSpan(0, 3), neu: ModelSpan(0, 2)),
        ],
      );
      expect(describeAll(UnifiedRows.build(doc)), ['c 0 0', 'c 1 1', 'c 2 -']);
    });

    test('20,000 lines a side build in well under a frame budget', () {
      final d = SyntheticDiff([
        for (var i = 0; i < 200; i++) ...const [Eq(90), Mod(5, 7), Del(5)],
      ]);
      final watch = Stopwatch()..start();
      final rows = UnifiedRows.build(d.document);
      expect(watch.elapsedMilliseconds, lessThan(50));
      expect(rows.rowCount, 200 * (90 + 5 + 7 + 5));
    });
  });

  group('unified folds', () {
    late DiffViewController c;
    setUp(() {
      final d = SyntheticDiff(const [Eq(20), Mod(1, 1), Eq(20)]);
      c = DiffViewController(
        document: d.document,
        lines: d.source,
        theme: DiffThemeData.light(),
        foldContext: 2,
      );
    });
    tearDown(() => c.dispose());

    test('hide the rows of both sides hidden lines', () {
      expect(c.unifiedRows.rowCount, 42);
      expect(c.unifiedGeometry.hiddenSpans, const [
        ModelSpan(0, 18),
        ModelSpan(24, 42),
      ]);
      expect(c.unifiedFoldRegionAtSlot(0), 0);
      expect(c.unifiedFoldRegionAtSlot(24), 1);
      expect(c.unifiedFoldRegionAtSlot(23), -1);
    });

    test('expand level by level, and with the panes', () {
      final g = c.unifiedGeometry;
      c.toggleFold(1);
      expect(g.hiddenSpans.last, const ModelSpan(26, 42));
      expect(
        c.geometry(PaneSide.neu).hiddenSpans.last,
        const ModelSpan(25, 41),
      );
      c.toggleFold(1);
      expect(g.hiddenSpans.last, const ModelSpan(30, 42));
      c.toggleFold(1);
      expect(g.hiddenSpans, const [ModelSpan(0, 18)]);
      expect(g.anchorHint, isNull, reason: 'no view took the hint');
      c.folds.collapseEverything();
      expect(g.hiddenSpans.length, 2);
      c.toggleFold(0, all: true);
      expect(g.hiddenSpans, const [ModelSpan(24, 42)]);
    });
  });

  testWidgets('inlays land after the row of their line, either side', (
    tester,
  ) async {
    final h = await pumpHarness(
      tester,
      foldContext: -1,
      diff: SyntheticDiff(const [Eq(5), Mod(2, 2), Eq(5)]),
    );
    final c = h.controller;
    const specs = [
      InlaySpec(id: 'top', side: PaneSide.neu, afterLine: -1),
      InlaySpec(id: 'old', side: PaneSide.old, afterLine: 6),
      InlaySpec(id: 'new', side: PaneSide.neu, afterLine: 6),
      InlaySpec(id: 'ctx old', side: PaneSide.old, afterLine: 8),
      InlaySpec(id: 'ctx new', side: PaneSide.neu, afterLine: 8),
    ];
    // Rows: 0-4 context, 5-6 deleted (old 5, 6), 7-8 inserted (new 5, 6),
    // 9-13 context (old and new 7-11).
    expect([for (final s in specs) c.unifiedSlotOf(s)], [0, 7, 9, 11, 11]);
    specs.forEach(c.addInlay);
    await tester.pump();
    await tester.pump();
    final g = h.g;
    expect(g.inlayHeight(0), 60);
    expect(g.inlayHeight(7), 60);
    expect(g.inlayHeight(11), 120, reason: 'both sides of row 10 stack');
    final top = tester.getTopLeft(find.byType(UnifiedDiff)).dy;
    // Content y: the inlays above the anchor scrolled the view down.
    double inlayY(String id) =>
        tester.getTopLeft(find.text(id)).dy - top + h.pos.pixels;
    expect(inlayY('top'), 0);
    expect(inlayY('old'), g.topOfSlot(7));
    expect(g.topOfRow(7), g.topOfSlot(7) + 60, reason: 'inserted rows below');
    expect(inlayY('new'), g.topOfSlot(9));
    expect(inlayY('ctx old'), g.topOfSlot(11));
    expect(inlayY('ctx new'), g.topOfSlot(11) + 60);
    // In the inlay column, right of the unified gutter.
    expect(
      tester.getTopLeft(find.text('old')).dx -
          tester.getTopLeft(find.byType(UnifiedDiff)).dx,
      c.resources.unifiedGutter.gutterWidth + 4,
    );
  });

  testWidgets('an inlay in a fold reveals its row', (tester) async {
    final h = await pumpHarness(tester);
    final c = h.controller;
    final hidden = h.g.hiddenSpans.first;
    final line = c.unifiedRows.oldLineAt(hidden.start + 5);
    c.addInlay(InlaySpec(id: 'x', side: PaneSide.old, afterLine: line));
    await tester.pump();
    final slot = c.unifiedSlotOf(c.inlays.single);
    expect(h.g.isRowVisible(slot - 1), isTrue);
    expect(h.g.shownInlayHeight(slot), 60);
  });

  testWidgets('gutter drag, Shift+Down, shift-click and copy', (tester) async {
    final h = await pumpHarness(
      tester,
      foldContext: -1,
      diff: SyntheticDiff(const [Eq(5), Mod(2, 2), Eq(5)]),
    );
    final c = h.controller;
    final clipboard = mockClipboard(tester);
    final pane = find.byType(UnifiedDiff);
    final origin = tester.getTopLeft(pane);
    final lh = c.resources.lineHeight;
    final gx = c.resources.unifiedGutter.numberRight - 4;
    Offset at(int row) => origin + Offset(gx, h.y(row) + lh / 2);

    final drag = await tester.startGesture(
      at(4),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(c.unifiedSelection.value, const RowSelection(anchor: 4, focus: 4));
    await drag.moveTo(at(8));
    await tester.pump();
    await drag.up();
    await tester.pump();
    expect(c.unifiedSelection.value!.span, const ModelSpan(4, 9));
    expect(c.selection.value, isNull, reason: 'the panes are untouched');
    final lines = c.unifiedRows.linesIn(c.unifiedSelection.value!.span);
    expect(lines.old, const ModelSpan(4, 7));
    expect(lines.neu, const ModelSpan(4, 7));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.unifiedSelection.value!.span, const ModelSpan(4, 10));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final click = await tester.startGesture(
      at(2),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.unifiedSelection.value!.span, const ModelSpan(2, 5));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.unifiedSelection.value!.span, const ModelSpan(4, 9));

    // Cmd+C copies the shown text: deleted lines, then inserted ones.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    final d = h.diff;
    final expected = [
      d.neu[4],
      d.old[5],
      d.old[6],
      d.neu[5],
      d.neu[6],
    ].map((l) => '${l.text}\n').join();
    expect(clipboard(), expected);
    expect(await c.unifiedTextOf(const ModelSpan(4, 9)), expected);
    expect(expected, isNot(contains('+')));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(c.unifiedSelection.value, isNull);
  });

  testWidgets('jumpToLine and ensureLineVisible scroll the unified view', (
    tester,
  ) async {
    final h = await pumpHarness(
      tester,
      diff: SyntheticDiff(const [Mod(1, 1), Eq(3000), Mod(1, 1), Eq(3000)]),
    );
    final c = h.controller;
    // Old line L of the first gap is row L + 1 (the block's two rows first).
    expect(h.g.isRowVisible(1501), isFalse);
    c.jumpToLine(PaneSide.old, 1500, viewportY: 200);
    await tester.pump();
    await tester.pump();
    expect(h.g.isRowVisible(1501), isTrue);
    expect(c.viewportYOfLine(PaneSide.old, 1500), closeTo(200, 0.5));
    expect(c.viewportYOfLine(PaneSide.neu, 1500), closeTo(200, 0.5));
    c.ensureLineVisible(PaneSide.neu, 1600);
    await tester.pump();
    final y = c.viewportYOfLine(PaneSide.neu, 1600)!;
    expect(y + c.resources.lineHeight, closeTo(h.pos.viewportDimension, 0.5));
    // A line past the end is clamped.
    c.jumpToLine(PaneSide.neu, 1 << 30);
    await tester.pump();
    expect(h.pos.pixels, h.pos.maxScrollExtent);
  });

  testWidgets('a jump made before the first layout is made after it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final h = Harness(bigDiff(), foldContext: -1);
    addTearDown(h.controller.dispose);
    h.controller.jumpToLine(PaneSide.old, 700, viewportY: 120);
    await tester.pumpWidget(h.app());
    await tester.pump();
    expect(h.controller.viewportYOfLine(PaneSide.old, 700), closeTo(120, 0.5));
  });

  testWidgets('switching views keeps the line in place', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final h = Harness(bigDiff(), foldContext: -1);
    final c = h.controller;
    addTearDown(c.dispose);
    await tester.pumpWidget(h.app(unified: false));
    c.jumpToLine(PaneSide.neu, 1000, viewportY: 200);
    await tester.pump();
    expect(c.viewportYOfLine(PaneSide.neu, 1000), closeTo(200, 0.5));

    await tester.pumpWidget(h.app());
    await tester.pump();
    expect(c.scroll(PaneSide.neu).hasClients, isFalse);
    expect(c.viewportYOfLine(PaneSide.neu, 1000), closeTo(200, 0.5));

    await tester.pumpWidget(h.app(unified: false));
    await tester.pump();
    expect(c.unifiedScroll.hasClients, isFalse);
    expect(c.viewportYOfLine(PaneSide.neu, 1000), closeTo(200, 0.5));
  });

  testWidgets('a clicked fold placeholder stays put and expands downward', (
    tester,
  ) async {
    final h = await pumpHarness(tester);
    final c = h.controller;
    final g = h.g;
    final span = g.hiddenSpans[3];
    final region = c.unifiedFoldRegionAtSlot(span.start);
    h.pos.jumpTo(g.topOfSlot(span.start) - 40);
    await tester.pump();
    final box = tester.getTopLeft(find.byType(UnifiedDiff));
    final gesture = await tester.startGesture(
      box + Offset(300, 40 + g.placeholderHeight / 2),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(c.folds.expandedLevel(region), 1);
    expect(g.topOfSlot(span.start) - h.pos.pixels, closeTo(40, 0.5));
    expect(g.hiddenSpans[3].start, span.start + 4);
  });

  testWidgets('the horizontal offset follows the unified rows', (tester) async {
    final diff = bigDiff();
    for (final side in [diff.old, diff.neu]) {
      side[3] = DiffLine(line: 3, text: 'long ${'x' * 600}');
    }
    final h = await pumpHarness(tester, foldContext: -1, diff: diff);
    final c = h.controller..scrollHorizontally(4000, codeWidth: 600);
    await tester.pump();
    expect(c.horizontal.value, greaterThan(1000));
    h.pos.jumpTo(3000);
    await tester.pump();
    expect(c.horizontal.value, 0);
  });

  testWidgets('both views share the layout cache', (tester) async {
    final h = await pumpHarness(tester, foldContext: -1);
    final c = h.controller;
    // Rows 0-39 are context rows: they show (and cache) new lines 0-39.
    for (var line = 0; line < 20; line++) {
      expect(
        c.resources.lines.contains(PaneSide.neu.index | (line << 1)),
        isTrue,
      );
    }
    final before = c.resources.lines.length;
    final rows = h.g.index.hit(h.pos.viewportDimension).slot + 1;
    await tester.pumpWidget(h.app(unified: false));
    await tester.pump();
    // Only the old pane adds layouts; the new pane reuses the unified ones.
    expect(c.resources.lines.length - before, lessThanOrEqualTo(rows));
  });

  testWidgets('an empty diff lays out', (tester) async {
    final h = await pumpHarness(tester, diff: SyntheticDiff(const []));
    expect(h.g.rowCount, 0);
    expect(tester.takeException(), isNull);
  });
}
