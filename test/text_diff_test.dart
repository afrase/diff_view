import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:side_by_side_diff/side_by_side_diff.dart';

List<String> _texts(MemoryLineSource s, PaneSide side, int n) => [
  for (var i = 0; i < n; i++) s.lineAt(side, i)!.text,
];

void main() {
  group('myersDiff', () {
    test('rebuilds b from a for random inputs', () {
      final r = Random(1);
      for (var t = 0; t < 300; t++) {
        final a = List.generate(r.nextInt(30), (_) => r.nextInt(4));
        final b = List.generate(r.nextInt(30), (_) => r.nextInt(4));
        final ops = myersDiff(a, b);
        final out = <int>[];
        var i = 0;
        var j = 0;
        for (final op in ops) {
          switch (op) {
            case EditOp.equal:
              expect(a[i], b[j]);
              out.add(a[i]);
              i++;
              j++;
            case EditOp.delete:
              i++;
            case EditOp.insert:
              out.add(b[j]);
              j++;
          }
        }
        expect(i, a.length);
        expect(out, b);
      }
    });

    test('is minimal on a known case', () {
      // ABCABBA -> CBABAC has an edit distance of 5.
      final ops = myersDiff('ABCABBA'.codeUnits, 'CBABAC'.codeUnits);
      expect(ops.where((o) => o != EditOp.equal).length, 5);
    });
  });

  group('TextDiff', () {
    test('equal texts have one gap and no blocks', () {
      final d = TextDiff.compute('a\nb\n', 'a\nb\n');
      expect(d.document.blocks, isEmpty);
      expect(d.document.gaps, hasLength(1));
      expect(d.document.oldLineCount, 2);
    });

    test('finds inserted, deleted and modified blocks', () {
      final d = TextDiff.compute(
        'keep\nold line\nkeep2\ngone\nend\n',
        'keep\nnew line\nkeep2\nend\nadded\n',
      );
      final kinds = d.document.blocks.map((b) => b.kind).toList();
      expect(kinds, [
        BlockKind.modified,
        BlockKind.deleted,
        BlockKind.inserted,
      ]);
      expect(_texts(d.lines, PaneSide.neu, 5), [
        'keep',
        'new line',
        'keep2',
        'end',
        'added',
      ]);
      expect(d.lines.lineAt(PaneSide.old, 1)!.kind, LineKind.modified);
      expect(d.lines.lineAt(PaneSide.old, 3)!.kind, LineKind.deleted);
      expect(d.lines.lineAt(PaneSide.neu, 4)!.kind, LineKind.added);
      expect(d.lines.lineAt(PaneSide.neu, 4)!.block, 2);
    });

    test('marks the changed word inside a modified line', () {
      final d = TextDiff.compute('let x = 1;\n', 'let y = 1;\n');
      final oldInner = d.lines.lineAt(PaneSide.old, 0)!.inner;
      final newInner = d.lines.lineAt(PaneSide.neu, 0)!.inner;
      expect(oldInner.toList(), [4, 1, innerChanged]);
      expect(newInner.toList(), [4, 1, innerChanged]);
    });

    test('keeps line endings, including a missing final newline', () {
      final d = TextDiff.compute('a\r\nb', 'a\r\nb\n');
      expect(d.lines.lineAt(PaneSide.old, 0)!.ending, LineEnding.crlf);
      expect(d.lines.lineAt(PaneSide.old, 1)!.ending, LineEnding.none);
      expect(d.lines.lineAt(PaneSide.neu, 1)!.ending, LineEnding.lf);
    });

    test('handles empty texts', () {
      final d = TextDiff.compute('', 'x\n');
      expect(d.document.oldLineCount, 0);
      expect(d.document.blocks.single.kind, BlockKind.inserted);
    });
  });
}
