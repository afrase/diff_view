import 'dart:ui';

import 'package:diff_view/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// 30 repetitions of (40 equal, modified 3/5, 20 equal, inserted 4,
/// 10 equal, deleted 2): about 2,300 lines a side, 90 blocks, 90 gaps.
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

  Widget app() => MaterialApp(
    home: Scaffold(
      body: SideBySideDiff(
        controller: controller,
        theme: DiffThemeData.light(),
        inlayBuilder: (context, spec) =>
            SizedBox(height: heights[spec.id] ?? 60, child: Text(spec.id)),
      ),
    ),
  );

  ScrollPosition pos(PaneSide side) => controller.scroll(side).position;

  double y(PaneSide side, int line) => controller.viewportYOfLine(side, line)!;
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

void main() {
  testWidgets('inlays above the anchor do not move it; below grows down', (
    tester,
  ) async {
    final h = await pumpHarness(tester, foldContext: -1);
    final c = h.controller;
    const anchor = 1000;
    c.jumpToLine(PaneSide.neu, anchor, viewportY: 200);
    await tester.pump();
    expect(h.y(PaneSide.neu, anchor), 200);
    final oldBefore = h.pos(PaneSide.old).pixels;

    // Above the anchor (the anchor point is 1/3 of 548 px ≈ 183 px).
    c.addInlay(const InlaySpec(id: 'a', side: PaneSide.neu, afterLine: 990));
    await tester.pump();
    await tester.pump();
    expect(h.y(PaneSide.neu, anchor), closeTo(200, 0.5));
    expect(h.pos(PaneSide.old).pixels, closeTo(oldBefore, 0.5));

    // Below the anchor.
    c.addInlay(const InlaySpec(id: 'b', side: PaneSide.neu, afterLine: 1005));
    await tester.pump();
    await tester.pump();
    expect(h.y(PaneSide.neu, anchor), closeTo(200, 0.5));

    // Grow the inlay above to 30 lines, then delete it.
    h.heights['a'] = 30 * 18;
    c.inlays = [...c.inlays]; // rebuilds the inlay widgets
    await tester.pump();
    await tester.pump();
    expect(c.geometry(PaneSide.neu).inlayHeight(991), 540);
    expect(h.y(PaneSide.neu, anchor), closeTo(200, 0.5));
    c.removeInlay('a');
    await tester.pump();
    await tester.pump();
    expect(h.y(PaneSide.neu, anchor), closeTo(200, 0.5));

    // 50 inlays above the viewport.
    for (var i = 0; i < 50; i++) {
      c.addInlay(
        InlaySpec(id: 'm$i', side: PaneSide.neu, afterLine: 100 + i * 10),
      );
    }
    await tester.pump();
    await tester.pump();
    expect(h.y(PaneSide.neu, anchor), closeTo(200, 0.5));
    expect(h.pos(PaneSide.old).pixels, closeTo(oldBefore, 0.5));
  });

  testWidgets('an inlay in the slave pane keeps the slave anchored too', (
    tester,
  ) async {
    final h = await pumpHarness(tester, foldContext: -1);
    final c = h.controller..jumpToLine(PaneSide.neu, 1000, viewportY: 200);
    await tester.pump();
    await tester.pump();
    final oldLine = c.document.transferLine(1000, PaneSide.neu);
    final oldY = h.y(PaneSide.old, oldLine);
    c.addInlay(InlaySpec(id: 'o', side: PaneSide.old, afterLine: oldLine - 8));
    await tester.pump();
    await tester.pump();
    expect(h.y(PaneSide.old, oldLine), closeTo(oldY, 0.5));
    expect(h.y(PaneSide.neu, 1000), closeTo(200, 0.5));
  });

  testWidgets('a clicked fold placeholder stays put and expands downward', (
    tester,
  ) async {
    final h = await pumpHarness(tester);
    final c = h.controller;
    final g = c.geometry(PaneSide.neu);
    final span = g.hiddenSpans[3];
    final region = c.folds.regionAt(PaneSide.neu, span.start);
    // Placeholder near the top of the viewport (above the 1/3 anchor).
    c.master = PaneSide.neu;
    h.pos(PaneSide.neu).jumpTo(g.topOfSlot(span.start) - 40);
    await tester.pump();
    final before = g.topOfSlot(span.start) - h.pos(PaneSide.neu).pixels;
    expect(before, 40);
    final box = tester.getTopLeft(find.byType(DiffPane).last);
    final gesture = await tester.startGesture(
      box + Offset(200, before + g.placeholderHeight / 2),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pump();
    await tester.pump();
    expect(c.folds.expandedLevel(region), 1);
    expect(
      g.topOfSlot(span.start) - h.pos(PaneSide.neu).pixels,
      closeTo(40, 0.5),
    );
    final next = c.folds.hiddenSpan(region, PaneSide.neu)!;
    expect(next.start, span.start + 4);
  });

  testWidgets('changed rows repaint; horizontal offset re-clamps', (
    tester,
  ) async {
    final h = await pumpHarness(tester, foldContext: -1);
    final c = h.controller;
    // Rows 3 change after they were painted (a row fetched again): the
    // cached layouts must not be reused.
    for (final side in [h.diff.old, h.diff.neu]) {
      side[3] = DiffLine(line: 3, text: 'long ${'x' * 600}');
    }
    c.scroll(PaneSide.neu).jumpTo(1);
    await tester.pump();
    expect(c.resources.lines.invalidated, 2);
    c.scrollHorizontally(4000, codeWidth: 600);
    await tester.pump();
    expect(c.horizontal.value, greaterThan(1000));
    // Scroll to where every line is short: the offset follows them back.
    c.scroll(PaneSide.neu).jumpTo(3000);
    await tester.pump();
    expect(c.horizontal.value, 0);
    // A line past the end is clamped, not thrown.
    c.jumpToLine(PaneSide.neu, 1 << 30);
    await tester.pump();
    expect(h.pos(PaneSide.neu).pixels, h.pos(PaneSide.neu).maxScrollExtent);
  });

  testWidgets('the old pane follows the new pane through the sync map', (
    tester,
  ) async {
    final h = await pumpHarness(tester);
    final c = h.controller..master = PaneSide.neu;
    final s = SyncScrollState();
    for (final target in [500.0, 3000.0, 8000.0]) {
      h.pos(PaneSide.neu).jumpTo(target);
      await tester.pump();
      s.reset();
      final expected = s.slaveOffsetFor(
        map: c.syncMap,
        master: PaneSide.neu,
        m: h.pos(PaneSide.neu).pixels,
        viewportHeight: h.pos(PaneSide.neu).viewportDimension,
        masterMax: h.pos(PaneSide.neu).maxScrollExtent,
        slaveMax: h.pos(PaneSide.old).maxScrollExtent,
        devicePixelRatio: 2,
        lineHeight: c.resources.lineHeight,
      );
      expect(h.pos(PaneSide.old).pixels, closeTo(expected, 0.01));
    }
  });

  testWidgets('gutter drag with autoscroll, shift-click, Shift+Down, copy', (
    tester,
  ) async {
    final h = await pumpHarness(tester, foldContext: -1);
    final c = h.controller;
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
    c.jumpToLine(PaneSide.neu, 1199, viewportY: 100);
    await tester.pump();
    final pane = find.byType(DiffPane).last;
    final origin = tester.getTopLeft(pane);
    final size = tester.getSize(pane);
    final lh = c.resources.lineHeight;
    final gx = c.resources.gutter.numberRight - 4;
    final gesture = await tester.startGesture(
      origin + Offset(gx, 100 + lh / 2),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(
      c.selection.value,
      const LineSelection(side: PaneSide.neu, anchor: 1199, focus: 1199),
    );
    // Past the bottom edge: autoscroll until line 1,260 (model 1259).
    await gesture.moveTo(origin + Offset(gx, size.height + 20));
    for (var i = 0; i < 400 && c.selection.value!.focus < 1259; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final y = h.y(PaneSide.neu, 1259);
    await gesture.moveTo(origin + Offset(gx, y + lh / 2));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(c.selection.value!.span, const ModelSpan(1199, 1260));
    expect(c.selection.value!.side, PaneSide.neu);

    // Shift+Down extends by one visible line.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.selection.value!.span, const ModelSpan(1199, 1261));

    // Shift+click on another gutter row extends.
    c.jumpToLine(PaneSide.neu, 1240, viewportY: 100);
    await tester.pump();
    final y2 = h.y(PaneSide.neu, 1262);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final click = await tester.startGesture(
      origin + Offset(gx, y2 + lh / 2),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.selection.value!.span, const ModelSpan(1199, 1263));

    final text = await c.copySelection();
    final expected = h.diff.neu
        .sublist(1199, 1263)
        .map((l) => '${l.text}\n')
        .join();
    expect(text, expected);
    expect(clipboard, expected);
  });

  //.5 / B18: the anchor holds what is under the 1/3 point, also when
  // that is a placeholder or an inlay and the change is earlier in the
  // same slot.
  group('anchor on extras', () {
    double anchorPoint(Harness h) => h.pos(PaneSide.neu).viewportDimension / 3;

    testWidgets('a placeholder stays when an inlay is added above it', (
      tester,
    ) async {
      final h = await pumpHarness(tester);
      final c = h.controller..master = PaneSide.neu;
      final g = c.geometry(PaneSide.neu);
      final span = g.hiddenSpans[5];
      final slotTop = g.topOfSlot(span.start);
      h
          .pos(PaneSide.neu)
          .jumpTo(slotTop + g.placeholderHeight / 2 - anchorPoint(h));
      await tester.pump();
      double placeholderY() =>
          g.topOfSlot(span.start) +
          g.shownInlayHeight(span.start) -
          h.pos(PaneSide.neu).pixels;
      final before = placeholderY();
      final rowAfter = h.y(PaneSide.neu, span.end);
      c.addInlay(
        InlaySpec(id: 'c', side: PaneSide.neu, afterLine: span.start - 1),
      );
      await tester.pump();
      await tester.pump();
      expect(g.shownInlayHeight(span.start), 60);
      expect(placeholderY(), closeTo(before, 0.5));
      expect(h.y(PaneSide.neu, span.end), closeTo(rowAfter, 0.5));
    });

    testWidgets('an inlay stays when the one stacked above it is removed', (
      tester,
    ) async {
      final h = await pumpHarness(tester, foldContext: -1);
      final c = h.controller..master = PaneSide.neu;
      final g = c.geometry(PaneSide.neu);
      h.heights
        ..['first'] = 100
        ..['second'] = 200;
      c
        ..addInlay(
          const InlaySpec(id: 'first', side: PaneSide.neu, afterLine: 1000),
        )
        ..addInlay(
          const InlaySpec(id: 'second', side: PaneSide.neu, afterLine: 1000),
        );
      await tester.pump();
      await tester.pump();
      expect(g.inlayHeight(1001), 300);
      // The 1/3 point 50 px into the second inlay.
      h.pos(PaneSide.neu).jumpTo(g.topOfSlot(1001) + 150 - anchorPoint(h));
      await tester.pump();
      double secondTop() =>
          tester.getTopLeft(find.text('second')).dy -
          tester.getTopLeft(find.byType(DiffPane).last).dy;
      final before = secondTop();
      final line = h.y(PaneSide.neu, 1001);
      c.removeInlay('first');
      await tester.pump();
      await tester.pump();
      expect(g.inlayHeight(1001), 200);
      expect(secondTop(), closeTo(before, 0.5));
      expect(h.y(PaneSide.neu, 1001), closeTo(line, 0.5));
      // The anchored inlay itself removed: the row after it holds still.
      c.removeInlay('second');
      await tester.pump();
      await tester.pump();
      expect(h.y(PaneSide.neu, 1001), closeTo(line, 0.5));
    });
  });

  testWidgets('jumpToLine into a fold puts the line where asked', (
    tester,
  ) async {
    final h = await pumpHarness(
      tester,
      diff: SyntheticDiff(const [
        Mod(1, 1),
        Eq(3000),
        Mod(1, 1),
        Eq(3000),
        Mod(1, 1),
        Eq(3000),
      ]),
    );
    final c = h.controller;
    final g = c.geometry(PaneSide.neu);
    // 6000 and 10 are shown context; the others are folded, below and
    // above the viewport (each jump reveals the whole region).
    for (final line in [6000, 1500, 4500, 7500, 10]) {
      expect(g.isRowVisible(line), line == 6000 || line == 10, reason: '$line');
      c.jumpToLine(PaneSide.neu, line, viewportY: 200);
      await tester.pump();
      await tester.pump();
      expect(g.isRowVisible(line), isTrue);
      final p = h.pos(PaneSide.neu);
      final want = (g.topOfRow(line) - 200).clamp(0.0, p.maxScrollExtent);
      expect(p.pixels, closeTo(want, 0.5), reason: 'line $line');
      if (line != 6000 && line != 10) {
        expect(h.y(PaneSide.neu, line), closeTo(200, 0.5), reason: '$line');
      }
    }
  });

  testWidgets('jumpToLine before the first layout is made after it', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final h = Harness(bigDiff(), foldContext: -1);
    addTearDown(h.controller.dispose);
    // Not attached yet: no throw, no fold or scroll state touched.
    final c = h.controller
      ..jumpToLine(PaneSide.neu, 500, viewportY: 50)
      ..jumpToLine(PaneSide.neu, 1000, viewportY: 200); // replaces the first
    expect(c.scroll(PaneSide.neu).hasClients, isFalse);
    await tester.pumpWidget(h.app());
    await tester.pump();
    expect(h.y(PaneSide.neu, 1000), closeTo(200, 0.5));
    expect(c.master, PaneSide.neu);
  });

  testWidgets('Cmd+C without a line selection reaches an ancestor', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final h = Harness(bigDiff(), foldContext: -1);
    addTearDown(h.controller.dispose);
    final c = h.controller;
    var ancestorCopies = 0;
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Focus(
            onKeyEvent: (node, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.keyC) {
                ancestorCopies++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: SideBySideDiff(
              controller: c,
              theme: DiffThemeData.light(),
              inlayBuilder: (context, spec) => const SizedBox(height: 60),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Future<void> cmdC() async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
    }

    // A click in the code area focuses the pane and selects nothing.
    final pane = find.byType(DiffPane).last;
    final click = await tester.startGesture(
      tester.getCenter(pane),
      kind: PointerDeviceKind.mouse,
    );
    await click.up();
    await tester.pump();
    expect(c.selection.value, isNull);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      focused.findAncestorWidgetOfExactType<DiffPane>(),
      isNotNull,
      reason: 'the pane has focus',
    );
    await cmdC();
    expect(ancestorCopies, 1);
    expect(clipboard, isNull);

    // With a line selection the pane copies and the ancestor sees nothing.
    c.selection.start(PaneSide.neu, 3);
    await cmdC();
    expect(ancestorCopies, 1);
    expect(clipboard, '${h.diff.neu[3].text}\n');
  });

  testWidgets('the horizontal clamp skips the rows a fold hides', (
    tester,
  ) async {
    final diff = SyntheticDiff(const [Mod(1, 1), Eq(20000), Mod(1, 1), Eq(50)]);
    for (final side in [diff.old, diff.neu]) {
      side[0] = DiffLine(line: 0, text: 'long ${'x' * 600}');
    }
    final h = await pumpHarness(tester, diff: diff);
    final c = h.controller;
    final g = c.geometry(PaneSide.neu);
    expect(g.hiddenSpans, isNotEmpty);
    expect(g.hiddenSpans.first.length, greaterThan(19000));
    await tester.pump();
    final cached = c.resources.lines.length;
    c.scrollHorizontally(400, codeWidth: 600);
    await tester.pump();
    // Only the visible rows were measured, and line 0 is the widest.
    expect(c.resources.lines.length, lessThan(cached + 20));
    expect(c.horizontal.value, 400);
    final watch = Stopwatch()..start();
    c.scroll(PaneSide.neu).jumpTo(1);
    await tester.pump();
    expect(watch.elapsedMilliseconds, lessThan(200));
    expect(c.resources.lines.length, lessThan(cached + 20));
  });
}
