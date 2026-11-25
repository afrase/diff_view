import 'package:diff_view/src/model/line_coords.dart';
import 'package:flutter/foundation.dart';

/// A place in the code of a diff view: between two characters of a line.
///
/// [line] is the model line of the selection's side (convention 1), or the
/// row of a unified view. [column] is a UTF-16 offset into the line's text
/// as the file has it (a tab counts as one), from 0 to the text's length.
@immutable
final class CodePosition implements Comparable<CodePosition> {
  /// Creates a position.
  const new(this.line, this.column);

  /// The model line, or the unified row.
  final int line;

  /// The UTF-16 offset into the line's text.
  final int column;

  @override
  int compareTo(CodePosition other) =>
      line != other.line ? line - other.line : column - other.column;

  @override
  bool operator ==(Object other) =>
      other is CodePosition && other.line == line && other.column == column;

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => '$line:$column';
}

/// A text selection in the code of one pane of a side-by-side view, or of
/// a unified view: from where the drag started ([anchor]) to where it is
/// now ([focus]).
@immutable
final class CodeSelection {
  /// Creates a selection in the pane of [side].
  const new({
    required PaneSide this.side,
    required this.anchor,
    required this.focus,
  });

  /// Creates a selection in a unified view; its positions' lines are rows.
  const new unified({required this.anchor, required this.focus}) : side = null;

  /// The pane the selection is in, or null in a unified view.
  final PaneSide? side;

  /// Where the selection started.
  final CodePosition anchor;

  /// Where the selection extends to.
  final CodePosition focus;

  /// Whether the selection is in a unified view.
  bool get isUnified => side == null;

  /// The earlier of [anchor] and [focus].
  CodePosition get start => anchor.compareTo(focus) <= 0 ? anchor : focus;

  /// The later of [anchor] and [focus].
  CodePosition get end => anchor.compareTo(focus) <= 0 ? focus : anchor;

  /// Whether nothing is selected: [anchor] is [focus].
  bool get isCollapsed => anchor == focus;

  @override
  bool operator ==(Object other) =>
      other is CodeSelection &&
      other.side == side &&
      other.anchor == anchor &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(side, anchor, focus);

  @override
  String toString() =>
      'CodeSelection(${side?.name ?? 'unified'} $anchor to $focus)';
}

/// The text selection of a file view. Its [value] is never collapsed: a
/// collapsed selection is stored as null, nothing selected.
final class CodeSelectionController extends ChangeNotifier
    implements ValueListenable<CodeSelection?> {
  CodeSelection? _value;

  /// The selection, or null.
  @override
  CodeSelection? get value => _value;

  /// Replaces the selection with [selection]; a collapsed one clears it.
  void select(CodeSelection? selection) {
    final next = selection == null || selection.isCollapsed ? null : selection;
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// Clears the selection.
  void clear() => select(null);
}

/// The word around UTF-16 [offset] of [text], as `(start, end)`: the run
/// of characters of one class (letters, digits and `_`; spaces and tabs;
/// other punctuation) that holds the character at [offset], or the one
/// before it at the end of the text. Characters outside ASCII count as
/// letters.
(int, int) wordRangeAt(String text, int offset) {
  if (text.isEmpty) return (0, 0);
  final at = offset >= text.length
      ? text.length - 1
      : (offset < 0 ? 0 : offset);
  final kind = _classOf(text.codeUnitAt(at));
  var start = at;
  while (start > 0 && _classOf(text.codeUnitAt(start - 1)) == kind) {
    start--;
  }
  var end = at + 1;
  while (end < text.length && _classOf(text.codeUnitAt(end)) == kind) {
    end++;
  }
  return (start, end);
}

// 0 space, 1 word, 2 punctuation.
int _classOf(int c) {
  if (c == 0x20 || c == 0x09) return 0;
  if ((c >= 0x30 && c <= 0x39) ||
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c > 0x7F) {
    return 1;
  }
  return 2;
}
