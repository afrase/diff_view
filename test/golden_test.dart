import 'package:diff_view/diff_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// Goldens use the test font (every glyph a one-em box), which renders the
// same on macOS and Linux; colors, tints, word highlights, syntax runs,
// gutter, placeholders, inlays, the selection band and the ribbons are what
// they pin.
Future<DiffViewController> pumpGolden(
  WidgetTester tester,
  DiffThemeData theme, {
  bool unified = false,
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
    ..physicalSize = const Size(900, 420)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final d = SyntheticDiff(segs);
  final c = DiffViewController(
    document: d.document,
    lines: d.source,
    theme: theme,
    captureNames: testCaptures,
    devicePixelRatio: 1,
  );
  addTearDown(c.dispose);
  Widget inlay(BuildContext context, InlaySpec spec) => Container(
    height: 40,
    color: theme.foldPlaceholderBackground,
    alignment: Alignment.centerLeft,
    child: Text(spec.id, style: TextStyle(color: theme.text, fontSize: 12)),
  );
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: unified
          ? UnifiedDiff(controller: c, theme: theme, inlayBuilder: inlay)
          : SideBySideDiff(controller: c, theme: theme, inlayBuilder: inlay),
    ),
  );
  if (d.neu.length > 5) {
    c.addInlay(const InlaySpec(id: 'thread', side: PaneSide.neu, afterLine: 5));
  }
  if (unified) {
    // The deleted rows of the first block.
    c.unifiedSelection
      ..start(3)
      ..extendTo(4);
  } else {
    c.selection
      ..start(PaneSide.old, 3)
      ..extendTo(4);
  }
  await tester.pump();
  await tester.pump();
  return c;
}

void main() {
  testWidgets('side-by-side, light', (tester) async {
    await pumpGolden(tester, DiffThemeData.light());
    await expectLater(
      find.byType(SideBySideDiff),
      matchesGoldenFile('goldens/side_by_side_light.png'),
    );
  });

  testWidgets('side-by-side, dark', (tester) async {
    await pumpGolden(tester, DiffThemeData.dark());
    await expectLater(
      find.byType(SideBySideDiff),
      matchesGoldenFile('goldens/side_by_side_dark.png'),
    );
  });

  testWidgets('side-by-side, scrolled with the fold expanded one level', (
    tester,
  ) async {
    final c = await pumpGolden(tester, DiffThemeData.light());
    c.toggleFold(c.folds.regionAt(PaneSide.neu, 20));
    await tester.pump();
    c.master = PaneSide.neu;
    c.scroll(PaneSide.neu).jumpTo(120);
    await tester.pump();
    await tester.pump();
    await expectLater(
      find.byType(SideBySideDiff),
      matchesGoldenFile('goldens/side_by_side_scrolled.png'),
    );
  });

  testWidgets('unified, light', (tester) async {
    await pumpGolden(tester, DiffThemeData.light(), unified: true);
    await expectLater(
      find.byType(UnifiedDiff),
      matchesGoldenFile('goldens/unified_light.png'),
    );
  });

  testWidgets('unified, dark', (tester) async {
    await pumpGolden(tester, DiffThemeData.dark(), unified: true);
    await expectLater(
      find.byType(UnifiedDiff),
      matchesGoldenFile('goldens/unified_dark.png'),
    );
  });

  testWidgets('unified, an added file', (tester) async {
    final c = await pumpGolden(
      tester,
      DiffThemeData.light(),
      unified: true,
      segs: const [Ins(8)],
    );
    c.unifiedSelection.clear();
    await tester.pump();
    await expectLater(
      find.byType(UnifiedDiff),
      matchesGoldenFile('goldens/unified_added.png'),
    );
  });
}
