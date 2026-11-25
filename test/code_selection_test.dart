import 'package:diff_view/diff_view.dart';
import 'package:diff_view/src/model/code_selection.dart' show wordRangeAt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CodePosition', () {
    test('orders by line, then column', () {
      const a = CodePosition(3, 9);
      const b = CodePosition(4, 0);
      const c = CodePosition(4, 2);
      expect(a.compareTo(b), lessThan(0));
      expect(c.compareTo(b), greaterThan(0));
      expect(b.compareTo(const CodePosition(4, 0)), 0);
      expect(b, const CodePosition(4, 0));
      expect(a.toString(), '3:9');
    });
  });

  group('CodeSelection', () {
    test('start and end are in order whichever way it was made', () {
      const s = CodeSelection(
        side: PaneSide.neu,
        anchor: CodePosition(7, 4),
        focus: CodePosition(2, 1),
      );
      expect(s.start, const CodePosition(2, 1));
      expect(s.end, const CodePosition(7, 4));
      expect(s.isCollapsed, isFalse);
      expect(s.isUnified, isFalse);
      expect(
        const CodeSelection.unified(
          anchor: CodePosition(1, 1),
          focus: CodePosition(1, 1),
        ).isCollapsed,
        isTrue,
      );
    });

    test('a unified selection has no side', () {
      const s = CodeSelection.unified(
        anchor: CodePosition(0, 0),
        focus: CodePosition(1, 0),
      );
      expect(s.side, isNull);
      expect(s.isUnified, isTrue);
      expect(
        s,
        const CodeSelection.unified(
          anchor: CodePosition(0, 0),
          focus: CodePosition(1, 0),
        ),
      );
      expect(
        s ==
            const CodeSelection(
              side: PaneSide.neu,
              anchor: CodePosition(0, 0),
              focus: CodePosition(1, 0),
            ),
        isFalse,
      );
    });
  });

  group('CodeSelectionController', () {
    test('holds a selection, never a collapsed one, and notifies', () {
      final c = CodeSelectionController();
      addTearDown(c.dispose);
      var calls = 0;
      c.addListener(() => calls++);
      const s = CodeSelection(
        side: PaneSide.old,
        anchor: CodePosition(1, 2),
        focus: CodePosition(3, 0),
      );
      c.select(s);
      expect(c.value, s);
      expect(calls, 1);
      c.select(s);
      expect(calls, 1, reason: 'no change, no notification');
      c.select(
        const CodeSelection(
          side: PaneSide.old,
          anchor: CodePosition(1, 2),
          focus: CodePosition(1, 2),
        ),
      );
      expect(c.value, isNull, reason: 'collapsed is nothing selected');
      expect(calls, 2);
      c
        ..select(s)
        ..clear();
      expect(c.value, isNull);
      expect(calls, 4);
    });
  });

  group('wordRangeAt', () {
    const text = '  final foo_bar2 = baz(1, "x");';
    String word(int offset) {
      final (s, e) = wordRangeAt(text, offset);
      return text.substring(s, e);
    }

    test('a word, a run of spaces or of punctuation', () {
      expect(word(4), 'final');
      expect(word(2), 'final', reason: 'the offset before a word');
      expect(word(10), 'foo_bar2');
      expect(word(0), '  ');
      expect(word(22), '(');
      expect(word(29), '");');
      expect(word(text.length), '");', reason: 'the end picks the last run');
    });

    test('an empty line and letters outside ASCII', () {
      expect(wordRangeAt('', 0), (0, 0));
      const t = 'x = größe;';
      final (s, e) = wordRangeAt(t, 6);
      expect(t.substring(s, e), 'größe');
    });
  });
}
