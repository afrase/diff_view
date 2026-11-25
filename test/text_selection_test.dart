import 'package:diff_view/diff_view.dart';
import 'package:flutter/foundation.dart';
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
}
