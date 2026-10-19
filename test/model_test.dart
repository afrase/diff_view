import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:side_by_side_diff/side_by_side_diff.dart';

import 'support.dart';

void main() {
  group('line_coords', () {
    test('conversions between the three conventions', () {
      expect(modelLineOf(0), isNull);
      expect(modelLineOf(1), 0);
      expect(displayLineOf(0), 1);
      expect(spanToLineRange(const ModelSpan(41, 47)), const LineRange(42, 47));
      expect(
        lineRangeToModelSpan(const LineRange(42, 47)),
        const ModelSpan(41, 47),
      );
      expect(spanToLineRange(const ModelSpan(0, 1)), const LineRange(1, 1));
      expect(() => spanToLineRange(const ModelSpan(3, 3)), throwsArgumentError);
    });

    test('round trip', () {
      for (final s in const [
        ModelSpan(0, 1),
        ModelSpan(5, 9),
        ModelSpan(19999, 20000),
      ]) {
        expect(lineRangeToModelSpan(spanToLineRange(s)), s);
      }
    });

    test('span helpers', () {
      const s = ModelSpan(3, 6);
      expect(s.length, 3);
      expect(s.contains(3), isTrue);
      expect(s.contains(6), isFalse);
      expect(s.overlaps(const ModelSpan(5, 9)), isTrue);
      expect(s.overlaps(const ModelSpan(6, 9)), isFalse);
      expect(const ModelSpan.empty(4).isEmpty, isTrue);
      expect(PaneSide.old.other, PaneSide.neu);
    });
  });

  group('DiffDocument', () {
    final d = SyntheticDiff(const [
      Eq(10),
      Mod(2, 5),
      Eq(10),
      Ins(3),
      Eq(5),
      Del(4),
      Eq(6),
    ]);
    final doc = d.document;

    test('sync pairs are the boundary pairs', () {
      expect(doc.syncPairs, [
        (0, 0),
        (10, 10),
        (12, 15),
        (22, 25),
        (22, 28),
        (27, 33),
        (31, 33),
        (37, 39),
      ]);
    });

    test('blockAt', () {
      expect(doc.blockAt(PaneSide.old, 9), -1);
      expect(doc.blockAt(PaneSide.old, 10), 0);
      expect(doc.blockAt(PaneSide.neu, 14), 0);
      expect(doc.blockAt(PaneSide.neu, 15), -1);
      expect(doc.blockAt(PaneSide.neu, 25), 1);
      expect(doc.blockAt(PaneSide.old, 22), -1, reason: 'empty old span');
      expect(doc.blockAt(PaneSide.old, 28), 2);
    });

    test('transferLine tracks 1:1 in a block then stops', () {
      expect(doc.transferLine(10, PaneSide.old), 10);
      expect(doc.transferLine(11, PaneSide.old), 11);
      expect(
        doc.transferLine(14, PaneSide.neu),
        11,
        reason: 'shorter side holds',
      );
      expect(doc.transferLine(5, PaneSide.old), 5);
      expect(
        doc.transferLine(20, PaneSide.old),
        23,
        reason: 'equal region offset',
      );
      expect(
        doc.transferLine(26, PaneSide.neu),
        22,
        reason: 'inserted: old side empty',
      );
      expect(
        doc.transferLine(29, PaneSide.old),
        33,
        reason: 'deleted: new side empty',
      );
      expect(doc.transferLine(36, PaneSide.old), 38);
    });

    test('firstBlockEndingAfter', () {
      expect(doc.firstBlockEndingAfter(PaneSide.old, 0), 0);
      expect(doc.firstBlockEndingAfter(PaneSide.old, 12), 1);
      expect(doc.firstBlockEndingAfter(PaneSide.old, 22), 1);
      expect(doc.firstBlockEndingAfter(PaneSide.old, 31), 3);
    });

    test('rejects overlapping or out-of-range spans', () {
      expect(
        () => DiffDocument(
          oldLineCount: 10,
          newLineCount: 10,
          blocks: const [
            DiffBlock(
              index: 0,
              kind: BlockKind.modified,
              old: ModelSpan(2, 5),
              neu: ModelSpan(2, 5),
            ),
            DiffBlock(
              index: 1,
              kind: BlockKind.modified,
              old: ModelSpan(4, 6),
              neu: ModelSpan(6, 7),
            ),
          ],
          gaps: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => DiffDocument(
          oldLineCount: 3,
          newLineCount: 3,
          blocks: const [],
          gaps: const [
            DiffGap(index: 0, old: ModelSpan(0, 4), neu: ModelSpan(0, 3)),
          ],
        ),
        throwsArgumentError,
      );
    });
  });

  group('HeightIndex', () {
    test('matches a naive model under random updates', () {
      final rnd = Random(7);
      const n = 300;
      final idx = HeightIndex(n, 19);
      final visible = List.filled(n, true);
      final extra = List<double>.filled(n + 1, 0);
      double naiveTop(int slot) {
        var y = 0.0;
        for (var i = 0; i < slot; i++) {
          y += (i < n && visible[i] ? 19 : 0) + extra[i];
        }
        return y;
      }

      for (var step = 0; step < 2000; step++) {
        switch (rnd.nextInt(3)) {
          case 0:
            final r = rnd.nextInt(n);
            visible[r] = !visible[r];
            idx.setRowVisible(r, visible: visible[r]);
          case 1:
            final s = rnd.nextInt(n + 1);
            extra[s] = rnd.nextBool() ? 0 : rnd.nextInt(200) + 0.5;
            idx.setExtraAbove(s, extra[s]);
          case 2:
            final a = rnd.nextInt(n);
            final b = min(n, a + rnd.nextInt(80));
            final v = rnd.nextBool();
            for (var r = a; r < b; r++) {
              visible[r] = v;
            }
            idx.setRowsVisible(ModelSpan(a, b), visible: v);
        }
        if (step % 50 == 0) {
          for (final s in [0, 1, 37, 150, n - 1, n]) {
            expect(idx.topOfSlot(s), closeTo(naiveTop(s), 1e-6));
          }
          expect(idx.contentHeight, closeTo(naiveTop(n + 1), 1e-6));
        }
      }
    });

    test('hit finds the slot containing y; zero-height runs resolve to the '
        'slot with height', () {
      final idx = HeightIndex(10, 20)
        ..setRowsVisible(const ModelSpan(3, 7), visible: false)
        ..setExtraAbove(3, 30); // placeholder of the fold
      expect(idx.hit(0), (slot: 0, dy: 0.0));
      expect(idx.hit(59.5).slot, 2);
      expect(idx.hit(60), (slot: 3, dy: 0.0));
      expect(idx.hit(89.9).slot, 3);
      expect(idx.hit(90), (slot: 7, dy: 0.0));
      expect(idx.topOfRow(7), 90);
      expect(idx.hit(1000000000).slot, 10, reason: 'past the end: sentinel');
      expect(idx.contentHeight, 6 * 20 + 30);
    });

    test('line height change rebuilds', () {
      final idx = HeightIndex(4, 10)
        ..setExtraAbove(2, 5)
        ..lineHeight = 20;
      expect(idx.topOfRow(2), 45);
      expect(idx.contentHeight, 85);
    });
  });

  group('FoldModel', () {
    // Gaps: leading 100, middle 60, trailing 3 (too short to fold).
    final d = SyntheticDiff(const [Eq(100), Mod(1, 1), Eq(60), Ins(2), Eq(3)]);
    final folds = FoldModel(d.document);

    test(
      'levels keep ctx·2^k lines next to blocks, none above a leading gap',
      () {
        expect(folds.regions.length, 2);
        final lead = folds.regions[0];
        expect(lead.hidden(PaneSide.old, 0), const ModelSpan(0, 96));
        expect(lead.hidden(PaneSide.old, 1), const ModelSpan(0, 92));
        expect(lead.hidden(PaneSide.old, 2), const ModelSpan(0, 84));
        final mid = folds.regions[1];
        expect(mid.gap.old, const ModelSpan(101, 161));
        expect(mid.hidden(PaneSide.old, 0), const ModelSpan(105, 157));
        expect(mid.hidden(PaneSide.old, 1), const ModelSpan(109, 153));
        expect(mid.hidden(PaneSide.old, 2), const ModelSpan(117, 145));
        expect(mid.hidden(PaneSide.neu, 2), const ModelSpan(117, 145));
      },
    );

    test('levels nest', () {
      for (final r in folds.regions) {
        for (var k = 1; k < r.levels.length; k++) {
          final outer = r.hidden(PaneSide.old, k - 1)!;
          final inner = r.hidden(PaneSide.old, k)!;
          expect(inner.start >= outer.start && inner.end <= outer.end, isTrue);
        }
      }
    });

    test('expand, collapse and reveal', () {
      final f = FoldModel(d.document);
      var notified = 0;
      f.addListener(() => notified++);
      expect(f.hiddenSpan(1, PaneSide.neu), const ModelSpan(105, 157));
      expect(f.expandOneLevel(1), isTrue);
      expect(f.hiddenSpan(1, PaneSide.neu), const ModelSpan(109, 153));
      f.expandAll(1);
      expect(f.hiddenSpan(1, PaneSide.neu), isNull);
      expect(f.isExpanded(1), isTrue);
      expect(f.expandOneLevel(1), isFalse);
      f.collapseEverything();
      expect(f.hiddenSpan(1, PaneSide.neu), const ModelSpan(105, 157));
      expect(f.reveal(PaneSide.old, 110), isTrue);
      expect(f.hiddenSpan(1, PaneSide.old), const ModelSpan(117, 145));
      expect(f.reveal(PaneSide.old, 130), isTrue);
      expect(f.hiddenSpan(1, PaneSide.old), isNull);
      expect(f.reveal(PaneSide.old, 100), isFalse, reason: 'a block line');
      expect(f.regionAt(PaneSide.old, 100), -1);
      expect(f.regionAt(PaneSide.neu, 120), 1);
      expect(notified, greaterThan(0));
    });

    test('negative context disables folding', () {
      expect(FoldModel(d.document, context: -1).regions, isEmpty);
    });
  });

  group('PaneGeometry', () {
    PaneGeometry make() => PaneGeometry(
      side: PaneSide.neu,
      rowCount: 100,
      lineHeight: 20,
      placeholderHeight: 30,
    );

    test('folds add a placeholder at the first hidden row', () {
      final g = make()..setHidden(const [ModelSpan(10, 50)]);
      expect(g.topOfRow(10), 200 + 30);
      expect(g.topOfRow(50), 200 + 30);
      expect(g.placeholderAt(10), 30);
      expect(g.contentHeight, 60 * 20 + 30);
      expect(g.nextVisibleRow(20), 50);
      expect(g.previousVisibleRow(20), 9);
      expect(g.stepVisible(9, 1), 50);
      expect(g.stepVisible(50, -1), 9);
      g.setHidden(const [ModelSpan(14, 46)]);
      expect(g.placeholderAt(10), 0);
      expect(g.placeholderAt(14), 30);
      expect(g.contentHeight, 68 * 20 + 30);
      g.setHidden(const []);
      expect(g.contentHeight, 2000);
    });

    test(
      'inlays sit before the placeholder in a slot and hide below hidden rows',
      () {
        final g = make()
          ..setHidden(const [ModelSpan(10, 50)])
          ..setInlayHeight(10, 100) // below row 9 (visible)
          ..setInlayHeight(30, 40); // below row 29 (hidden)
        expect(g.shownInlayHeight(10), 100);
        expect(g.shownInlayHeight(30), 0);
        expect(g.topOfRow(50), 200 + 100 + 30);
        expect(g.slotsWithExtras, [10]);
        g.setHidden(const []);
        expect(g.shownInlayHeight(30), 40);
        expect(g.slotsWithExtras, [10, 30]);
      },
    );

    test('onWillChange runs before every change with the old geometry', () {
      final g = make();
      final seen = <double>[];
      g
        ..onWillChange = (() => seen.add(g.topOfRow(50)))
        ..setInlayHeight(10, 60)
        ..setInlayHeight(10, 60) // no change, no call
        ..setHidden(const [ModelSpan(20, 30)]);
      expect(seen, [1000, 1060]);
    });

    test('anchorAt resolves rows and extras', () {
      final g = make()..setInlayHeight(5, 50);
      expect(g.anchorAt(110), (slot: 5, part: AnchorPart.slotTop));
      expect(g.anchorAt(150), (slot: 5, part: AnchorPart.rowTop));
      expect(g.anchorAt(41), (slot: 2, part: AnchorPart.rowTop));
      expect(g.anchorY((slot: 5, part: AnchorPart.slotTop)), 100);
      expect(g.anchorY((slot: 5, part: AnchorPart.rowTop)), 150);
      const hint = (slot: 3, part: AnchorPart.slotTop);
      g.anchorHint = hint;
      expect(g.takeAnchorHint(), hint);
      expect(g.takeAnchorHint(), isNull);
    });
  });

  group('SyncMap', () {
    final d = SyntheticDiff(const [Eq(10), Mod(2, 6), Eq(20), Del(4), Eq(10)]);
    PaneGeometry geo(PaneSide side) => PaneGeometry(
      side: side,
      rowCount: d.document.lineCount(side),
      lineHeight: 10,
      placeholderHeight: 15,
    );

    test('slope 1 in equal regions; the shorter side of a block holds', () {
      final o = geo(PaneSide.old);
      final n = geo(PaneSide.neu);
      final m = SyncMap.build(d.document, o, n);
      expect(m.map(55, PaneSide.old), 55);
      expect(m.map(105, PaneSide.old), 105);
      // Old lines 10..12 vs new 10..16: old 11.5 → new 11.5, then the old
      // side holds at line 12.
      expect(m.map(115, PaneSide.old), 115);
      expect(m.map(140, PaneSide.neu), 120);
      expect(m.map(160, PaneSide.neu), 120);
      expect(
        m.map(170, PaneSide.neu),
        130,
        reason: 'after the block: offset 4 lines',
      );
    });

    test('an inlay on one side maps to a flat segment on the other', () {
      final o = geo(PaneSide.old);
      final n = geo(PaneSide.neu)..setInlayHeight(5, 50);
      final m = SyncMap.build(d.document, o, n);
      expect(m.map(50, PaneSide.neu), 50);
      expect(m.map(75, PaneSide.neu), 50);
      expect(m.map(100, PaneSide.neu), 50);
      expect(m.map(110, PaneSide.neu), 60);
      expect(m.map(50, PaneSide.old), anyOf(50, 100));
      expect(m.map(60, PaneSide.old), 110);
    });

    test('knots are monotone on both axes', () {
      final o = geo(PaneSide.old)..setHidden(const [ModelSpan(14, 30)]);
      final n = geo(PaneSide.neu)
        ..setHidden(const [ModelSpan(18, 34)])
        ..setInlayHeight(3, 33);
      final m = SyncMap.build(d.document, o, n);
      for (var i = 1; i < m.knotCount; i++) {
        expect(m.knot(i).$1, greaterThanOrEqualTo(m.knot(i - 1).$1));
        expect(m.knot(i).$2, greaterThanOrEqualTo(m.knot(i - 1).$2));
      }
    });

    test(
      'slave offset anchors at 1/3, blends at the ends and snaps to pixels',
      () {
        final o = geo(PaneSide.old);
        final n = geo(PaneSide.neu);
        final m = SyncMap.build(d.document, o, n);
        final s = SyncScrollState();
        double slave(double off) => s.slaveOffsetFor(
          map: m,
          master: PaneSide.neu,
          m: off,
          viewportHeight: 90,
          masterMax: n.contentHeight - 90,
          slaveMax: o.contentHeight - 90,
          devicePixelRatio: 2,
          lineHeight: 10,
        );
        expect(slave(0), 0);
        s.reset();
        // Anchor at 30: new 230 (line 23) ↔ old 190.
        expect(slave(200), 160);
        s.reset();
        expect(slave(n.contentHeight - 90), o.contentHeight - 90);
        s.reset();
        expect(slave(200.3) * 2, (slave(200.3) * 2).roundToDouble());
      },
    );
  });

  group('LineSelection', () {
    test('span is inclusive of both ends in either direction', () {
      const a = LineSelection(side: PaneSide.neu, anchor: 1199, focus: 1259);
      expect(a.span, const ModelSpan(1199, 1260));
      expect(a.lineRange, const LineRange(1200, 1260));
      expect(a.withFocus(1190).span, const ModelSpan(1190, 1200));
    });

    test('controller start, extend, shift-click, cap', () {
      final c = LineSelectionController(cap: 10);
      var n = 0;
      c
        ..addListener(() => n++)
        ..extendTo(5);
      expect(c.value, isNull);
      c
        ..start(PaneSide.old, 4)
        ..extendTo(8);
      expect(c.value!.span, const ModelSpan(4, 9));
      c.shiftClick(PaneSide.old, 20);
      expect(c.value!.span, const ModelSpan(4, 21));
      expect(c.isOverCap, isTrue);
      c.shiftClick(PaneSide.neu, 3);
      expect(
        c.value,
        const LineSelection(side: PaneSide.neu, anchor: 3, focus: 3),
      );
      c.clear();
      expect(c.value, isNull);
      expect(n, 5);
    });

    test('copy text is each line plus a newline', () {
      final d = SyntheticDiff(const [Eq(3)]);
      expect(
        copyTextOf(d.neu.sublist(1, 3)),
        '\tfunc f("same 1")\n\tfunc f("same 2")\n',
      );
    });

    test('copy keeps each line ending: CRLF, and none at the end', () {
      const file = 'a\r\nb\r\nlast';
      final lines = [
        DiffLine(line: 0, text: 'a', ending: LineEnding.crlf),
        DiffLine(line: 1, text: 'b', ending: LineEnding.crlf),
        DiffLine(line: 2, text: 'last', ending: LineEnding.none),
      ];
      expect(copyTextOf(lines), file);
      expect(copyTextOf(lines.sublist(1)), 'b\r\nlast');
      expect(copyTextOf(lines.sublist(0, 1)), 'a\r\n');
    });
  });

  group('InlaySpec', () {
    test('belowRange places the inlay after the last line', () {
      final s = InlaySpec.belowRange(
        id: 't',
        side: PaneSide.neu,
        range: const LineRange(42, 47),
      );
      expect(s.afterLine, 46);
      expect(s.slot, 47);
    });
  });
}
