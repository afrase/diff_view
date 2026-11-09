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
}
