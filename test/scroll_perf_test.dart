import 'package:diff_view/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// 20,000 lines a side: 200 repetitions of (92 equal, modified 4/4,
/// inserted 4, deleted 4).
SyntheticDiff hugeDiff() => SyntheticDiff([
  for (var i = 0; i < 200; i++) ...const [Eq(92), Mod(4, 4), Ins(4), Del(4)],
]);

/// Scrolls [scroll] down [frames] frames of [step] px and returns the
/// 50th and 95th percentiles of the frame times (build, layout and
/// paint), in µs. The first [warmUp] frames are not counted.
///
/// flutter test runs in debug mode on a machine doing other work, so the
/// times are printed for a person to compare, never asserted on: the
/// guards are the counts in [expectPaintsOnlyNewRows].
Future<(int, int)> scrollTimes(
  WidgetTester tester,
  ScrollController scroll, {
  int frames = 400,
  int warmUp = 40,
  double step = 47,
}) async {
  final times = <int>[];
  final watch = Stopwatch();
  for (var i = 0; i < frames; i++) {
    final p = scroll.position;
    p.jumpTo((p.pixels + step).clamp(0, p.maxScrollExtent));
    watch
      ..reset()
      ..start();
    await tester.pump();
    watch.stop();
    if (i >= warmUp) times.add(watch.elapsedMicroseconds);
  }
  times.sort();
  return (
    times[(times.length * 0.5).floor()],
    times[(times.length * 0.95).floor()],
  );
}

/// The scroll controllers of [c]'s panes as shown: the unified view's
/// one, or both sides'.
List<ScrollController> panes(DiffViewController c, {required bool unified}) =>
    unified
    ? [c.unifiedScroll]
    : [c.scroll(PaneSide.old), c.scroll(PaneSide.neu)];

/// The deterministic guards on what a scroll of [c] cost, after
/// [scrollTimes] scrolled it from the top: each pane laid out about one
/// line per row that came on screen, not one per row per frame, and
/// recoloured at most one per line laid out; the line cache stayed in its
/// budget; and scrolling back over rows just painted, then repainting,
/// lays out and recolours nothing.
///
/// "About": the cache's eviction is a second-chance approximation of
/// least recently used, so a row can be evicted while still near the
/// screen and laid out again (a few per 2,000 rows here), and the slack
/// is one screenful a pane. Laying rows out on every frame would go over
/// it hundreds of times.
Future<void> expectPaintsOnlyNewRows(
  WidgetTester tester,
  DiffViewController c, {
  required bool unified,
}) async {
  final layouts = c.resources.layouts;
  final lineHeight = c.resources.lineHeight;
  var shown = 0;
  var slack = 0;
  for (final s in panes(c, unified: unified)) {
    final p = s.position;
    shown += ((p.pixels + p.viewportDimension) / lineHeight).ceil() + 1;
    slack += (p.viewportDimension / lineHeight).ceil();
  }
  expect(layouts.builds, greaterThanOrEqualTo(shown ~/ 2));
  expect(layouts.builds, lessThanOrEqualTo(shown + slack));
  expect(layouts.contrastBuilds, lessThanOrEqualTo(layouts.builds));
  expect(
    c.resources.lines.paragraphs,
    lessThanOrEqualTo(DiffPaintResources.defaultMaxCachedLines),
  );
  final builds = layouts.builds;
  final contrastBuilds = layouts.contrastBuilds;
  final s = panes(c, unified: unified).last.position;
  s.jumpTo(s.pixels - s.viewportDimension / 2);
  await tester.pump();
  for (final ro in tester.renderObjectList<RenderDiffPane>(
    find.byType(DiffPaneViewport),
  )) {
    ro.markNeedsPaint();
  }
  await tester.pump();
  expect(layouts.builds, builds, reason: 'laid out again on a repaint');
  expect(
    layouts.contrastBuilds,
    contrastBuilds,
    reason: 'recoloured again on a repaint',
  );
}

Widget inlay(BuildContext context, InlaySpec spec) =>
    const SizedBox(height: 60);

Future<DiffViewController> pumpView(
  WidgetTester tester,
  SyntheticDiff d,
  DiffThemeData theme, {
  required bool unified,
  bool textSelectionEnabled = true,
}) async {
  final c = DiffViewController(
    document: d.document,
    lines: d.source,
    theme: theme,
    captureNames: testCaptures,
    foldContext: -1,
    textSelectionEnabled: textSelectionEnabled,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: unified
          ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
          : SideBySideDiff(controller: c, theme: theme, inlayBuilder: inlay),
    ),
  );
  return c;
}

Future<void> unpump(WidgetTester tester, DiffViewController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

/// A light theme whose [keyword] and [string] read on its background
/// and under 4.5 on its tints.
DiffThemeData lightTheme({
  double minTextContrast = 0,
  Color keyword = const Color(0xFF0033B3),
  Color string = const Color(0xFF067D17),
}) => DiffThemeData(
  brightness: Brightness.light,
  background: const Color(0xFFFFFFFF),
  text: const Color(0xFF080808),
  gutterBackground: const Color(0xFFF7F8FA),
  gutterText: const Color(0xFF8C8C8C),
  gutterTextChanged: const Color(0xFF4A4A4A),
  insertedLine: const Color(0xFFE3F5E3),
  insertedWord: const Color(0xFFB8E6B8),
  deletedLine: const Color(0xFFEDEDED),
  deletedWord: const Color(0xFFD6D6D6),
  modifiedLine: const Color(0xFFE6EEFC),
  modifiedWord: const Color(0xFFC2D6FA),
  ribbonInserted: const Color(0xFFD2EFD2),
  ribbonDeleted: const Color(0xFFE2E2E2),
  ribbonModified: const Color(0xFFD6E3FA),
  dividerBackground: const Color(0xFFF7F8FA),
  selection: const Color(0x553D7EFF),
  selectionOverCap: const Color(0x55E8A33D),
  foldPlaceholderBackground: const Color(0xFFF0F2F5),
  foldPlaceholderText: const Color(0xFF6F737A),
  loadingBar: const Color(0xFFE6E8EB),
  hoverAffordance: const Color(0xFF3574F0),
  syntax: {
    'keyword': SyntaxStyle(keyword, bold: true),
    'string': SyntaxStyle(string),
  },
  minTextContrast: minTextContrast,
);

void setView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1600, 1200)
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void main() {
  // Unified must scroll as cheaply as side by side: rows are painted, not
  // built as widgets, and each lays out once.
  testWidgets('a 20,000-line unified diff scrolls like side by side', (
    tester,
  ) async {
    setView(tester);
    final d = hugeDiff();
    expect(d.document.oldLineCount, 20000);
    expect(d.document.newLineCount, 20000);
    final p95s = <String>[];
    for (final unified in [false, true]) {
      final c = await pumpView(
        tester,
        d,
        DiffThemeData.light(),
        unified: unified,
      );
      final (_, p95) = await scrollTimes(
        tester,
        unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
      );
      expect(find.byType(Text), findsNothing);
      await expectPaintsOnlyNewRows(tester, c, unified: unified);
      p95s.add('${unified ? 'unified' : 'side by side'} $p95 µs');
      await unpump(tester, c);
    }
    debugPrint('scroll p95: ${p95s.join(', ')}');
  });

  // Text selection lays out nothing more while nothing is selected, and a
  // selection of the whole file paints only the rows on screen: it lays
  // out what scrolling with no selection does.
  testWidgets('text selection does not slow scrolling', (tester) async {
    setView(tester);
    final d = hugeDiff();
    final theme = DiffThemeData.light();
    for (final unified in [false, true]) {
      final times = <String>[];
      final builds = <int>[];
      for (final (name, enabled, selectAll) in [
        ('off', false, false),
        ('nothing selected', true, false),
        ('all selected', true, true),
      ]) {
        final c = await pumpView(
          tester,
          d,
          theme,
          unified: unified,
          textSelectionEnabled: enabled,
        );
        if (selectAll) {
          const start = CodePosition(0, 0);
          final end = CodePosition(
            unified ? c.unifiedRows.rowCount - 1 : 19999,
            0,
          );
          c.textSelection.select(
            unified
                ? CodeSelection.unified(anchor: start, focus: end)
                : CodeSelection(side: PaneSide.neu, anchor: start, focus: end),
          );
          await tester.pump();
        }
        final (_, p95) = await scrollTimes(
          tester,
          unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
        );
        await expectPaintsOnlyNewRows(tester, c, unified: unified);
        builds.add(c.resources.layouts.builds);
        times.add('$name $p95 µs');
        await unpump(tester, c);
      }
      // Turned on with nothing selected, it lays out exactly what off does.
      expect(builds[1], builds[0], reason: 'lines laid out: $builds');
      debugPrint(
        'scroll p95 ${unified ? 'unified' : 'side by side'}: '
        '${times.join(', ')}',
      );
    }
  });

  // A least text contrast works nothing out while it is off; on, it
  // recolours at most once per line laid out, never on a repaint.
  testWidgets('a least text contrast recolours each new row once', (
    tester,
  ) async {
    setView(tester);
    final d = hugeDiff();
    for (final unified in [false, true]) {
      final times = <String>[];
      for (final min in [0.0, 4.5]) {
        final c = await pumpView(
          tester,
          d,
          lightTheme(minTextContrast: min),
          unified: unified,
        );
        final (_, p95) = await scrollTimes(
          tester,
          unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
        );
        await expectPaintsOnlyNewRows(tester, c, unified: unified);
        final layouts = c.resources.layouts;
        if (min == 0) {
          expect(layouts.contrastBuilds, 0);
          expect(layouts.contrastResolved, 0);
        } else {
          expect(layouts.contrastBuilds, greaterThan(0));
        }
        times.add(
          '$min: $p95 µs, ${layouts.builds} lines laid out, '
          '${layouts.contrastBuilds} recoloured',
        );
        await unpump(tester, c);
      }
      debugPrint(
        'scroll p95 ${unified ? 'unified' : 'side by side'}, contrast '
        '${times.join('; ')}',
      );
    }
  });

  // The worst case for a least text contrast, as a benchmark: every row a
  // changed one, every token dim on its tint, and a fling's 600 px a
  // frame, so each frame lays out and recolours a screenful of new rows.
  // The times are printed; on the machine this was written on a new row
  // cost about twice as much to lay out with the contrast on.
  testWidgets('benchmark: a least text contrast at its worst', (tester) async {
    setView(tester);
    final d = SyntheticDiff([const Mod(20000, 20000)]);
    for (final unified in [false, true]) {
      final times = <String>[];
      for (final min in [0.0, 4.5]) {
        final c = await pumpView(
          tester,
          d,
          lightTheme(
            minTextContrast: min,
            keyword: const Color(0xFF5A82D0),
            string: const Color(0xFF4AA05A),
          ),
          unified: unified,
        );
        final (p50, p95) = await scrollTimes(
          tester,
          unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
          frames: 200,
          warmUp: 20,
          step: 600,
        );
        await expectPaintsOnlyNewRows(tester, c, unified: unified);
        final layouts = c.resources.layouts;
        if (min > 0) {
          // Every changed row is recoloured.
          expect(layouts.contrastBuilds, layouts.builds);
        }
        times.add(
          '$min: p50 $p50 µs, p95 $p95 µs, '
          '${layouts.contrastBuilds} recoloured',
        );
        await unpump(tester, c);
      }
      debugPrint(
        'worst case ${unified ? 'unified' : 'side by side'}, contrast '
        '${times.join('; ')}',
      );
    }
  });
}
