import 'package:diff_view/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// 20,000 lines a side: 200 repetitions of (92 equal, modified 4/4,
/// inserted 4, deleted 4).
SyntheticDiff hugeDiff() => SyntheticDiff([
  for (var i = 0; i < 200; i++) ...const [Eq(92), Mod(4, 4), Ins(4), Del(4)],
]);

/// Scrolls the view down [frames] frames of [step] px and returns the 95th
/// percentile of the frame times (build, layout and paint), in µs. The
/// first [warmUp] frames are not counted.
Future<int> scrollP95(
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
  return times[(times.length * 0.95).floor()];
}

void main() {
  // flutter test runs in debug mode, so the numbers are only good for a
  // comparison: unified must scroll about as cheaply as side by side.
  testWidgets('a 20,000-line unified diff scrolls like side by side', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final d = hugeDiff();
    expect(d.document.oldLineCount, 20000);
    expect(d.document.newLineCount, 20000);
    Future<int> run({required bool unified}) async {
      final c = DiffViewController(
        document: d.document,
        lines: d.source,
        theme: DiffThemeData.light(),
        captureNames: testCaptures,
        foldContext: -1,
      );
      final theme = DiffThemeData.light();
      Widget inlay(BuildContext context, InlaySpec spec) =>
          const SizedBox(height: 60);
      await tester.pumpWidget(
        MaterialApp(
          home: unified
              ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
              : SideBySideDiff(
                  controller: c,
                  theme: theme,
                  inlayBuilder: inlay,
                ),
        ),
      );
      final p95 = await scrollP95(
        tester,
        unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
      );
      // Paragraph caches stay bounded; rows are painted, not built.
      expect(
        c.resources.lines.length,
        lessThanOrEqualTo(DiffPaintResources.defaultMaxCachedLines),
      );
      expect(find.byType(Text), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      return p95;
    }

    // Twice each, keeping the better run, to damp JIT and GC noise.
    final split = [
      await run(unified: false),
      await run(unified: false),
    ].reduce((a, b) => a < b ? a : b);
    final unified = [
      await run(unified: true),
      await run(unified: true),
    ].reduce((a, b) => a < b ? a : b);
    debugPrint('scroll p95: side by side $split µs, unified $unified µs');
    expect(unified, lessThan(split * 1.5 + 1000));
  });

  // Text selection costs nothing per frame while nothing is selected, and
  // a selection of the whole file paints only the rows on screen.
  testWidgets('text selection does not slow scrolling', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final d = hugeDiff();
    final theme = DiffThemeData.light();
    Future<int> run({
      required bool unified,
      required bool enabled,
      bool selectAll = false,
    }) async {
      final c = DiffViewController(
        document: d.document,
        lines: d.source,
        theme: theme,
        captureNames: testCaptures,
        foldContext: -1,
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
      }
      Widget inlay(BuildContext context, InlaySpec spec) =>
          const SizedBox(height: 60);
      await tester.pumpWidget(
        MaterialApp(
          home: unified
              ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
              : SideBySideDiff(
                  controller: c,
                  theme: theme,
                  inlayBuilder: inlay,
                ),
        ),
      );
      final p95 = await scrollP95(
        tester,
        unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      return p95;
    }

    Future<int> best({
      required bool unified,
      required bool enabled,
      bool selectAll = false,
    }) async => [
      await run(unified: unified, enabled: enabled, selectAll: selectAll),
      await run(unified: unified, enabled: enabled, selectAll: selectAll),
    ].reduce((a, b) => a < b ? a : b);

    for (final unified in [false, true]) {
      final off = await best(unified: unified, enabled: false);
      final idle = await best(unified: unified, enabled: true);
      final all = await best(unified: unified, enabled: true, selectAll: true);
      debugPrint(
        'scroll p95 ${unified ? 'unified' : 'side by side'}: '
        'off $off µs, nothing selected $idle µs, all selected $all µs',
      );
      expect(idle, lessThan(off * 1.5 + 1000));
      expect(all, lessThan(off * 1.5 + 1000));
    }
  });

  // A least text contrast costs nothing while it is off, and on it builds
  // a recoloured paragraph once per changed line that needs one: scrolling
  // through fresh rows of a large diff costs about what it costs without.
  testWidgets('a least text contrast does not slow scrolling', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final d = hugeDiff();
    Future<(int, int)> run({
      required bool unified,
      required double minTextContrast,
    }) async {
      // The light theme's strings read under 4.5 on its word tints.
      final theme = DiffThemeData(
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
        syntax: const {
          'keyword': SyntaxStyle(Color(0xFF0033B3), bold: true),
          'string': SyntaxStyle(Color(0xFF067D17)),
        },
        minTextContrast: minTextContrast,
      );
      final c = DiffViewController(
        document: d.document,
        lines: d.source,
        theme: theme,
        captureNames: testCaptures,
        foldContext: -1,
      );
      Widget inlay(BuildContext context, InlaySpec spec) =>
          const SizedBox(height: 60);
      await tester.pumpWidget(
        MaterialApp(
          home: unified
              ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
              : SideBySideDiff(
                  controller: c,
                  theme: theme,
                  inlayBuilder: inlay,
                ),
        ),
      );
      final p95 = await scrollP95(
        tester,
        unified ? c.unifiedScroll : c.scroll(PaneSide.neu),
      );
      final builds = c.resources.layouts.contrastBuilds;
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      return (p95, builds);
    }

    Future<(int, int)> best({
      required bool unified,
      required double minTextContrast,
    }) async {
      final a = await run(unified: unified, minTextContrast: minTextContrast);
      final b = await run(unified: unified, minTextContrast: minTextContrast);
      return a.$1 < b.$1 ? a : b;
    }

    for (final unified in [false, true]) {
      final (off, offBuilds) = await best(unified: unified, minTextContrast: 0);
      final (on, onBuilds) = await best(unified: unified, minTextContrast: 4.5);
      debugPrint(
        'scroll p95 ${unified ? 'unified' : 'side by side'}: '
        'contrast off $off µs, on $on µs ($onBuilds recoloured lines)',
      );
      expect(offBuilds, 0);
      expect(onBuilds, greaterThan(0));
      expect(on, lessThan(off * 1.5 + 1000));
    }
  });
}
