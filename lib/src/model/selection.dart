import 'package:meta/meta.dart';
import 'package:side_by_side_diff/src/model/diff_line.dart';
import 'package:side_by_side_diff/src/model/line_coords.dart';

/// A range of whole lines on one side: where the gutter drag
/// started ([anchor]) and where it is now ([focus]), both model lines.
@immutable
final class LineSelection {
  /// Creates a selection.
  const new({required this.side, required this.anchor, required this.focus});

  /// The side the selection was started on; it never changes while the
  /// selection is extended.
  final PaneSide side;

  /// The line the selection started at.
  final int anchor;

  /// The line the selection extends to.
  final int focus;

  /// The selected lines (convention 1, never empty).
  ModelSpan get span => anchor <= focus
      ? ModelSpan(anchor, focus + 1)
      : ModelSpan(focus, anchor + 1);

  /// The selection as a review [LineRange] (convention 3).
  LineRange get lineRange => spanToLineRange(span);

  /// A copy with a new [focus].
  LineSelection withFocus(int focus) =>
      LineSelection(side: side, anchor: anchor, focus: focus);

  @override
  bool operator ==(Object other) =>
      other is LineSelection &&
      other.side == side &&
      other.anchor == anchor &&
      other.focus == focus;

  @override
  int get hashCode => Object.hash(side, anchor, focus);

  @override
  String toString() => 'LineSelection(${side.name} $span)';
}

/// Line-selection state of one file view: gutter drag, Shift+click and
/// Shift+arrow extension.
final class LineSelectionController {
  /// Creates a controller. Ranges longer than [cap] lines are allowed but
  /// flagged by [isOverCap] (the band turns amber).
  new({this.cap = 200});

  /// Viewer limit on a comment range.
  final int cap;

  LineSelection? _value;
  final List<void Function()> _listeners = [];

  /// The current selection, or null.
  LineSelection? get value => _value;

  /// Whether the selection is longer than [cap].
  bool get isOverCap => (_value?.span.length ?? 0) > cap;

  /// Registers [listener], called after every change.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Removes a listener.
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Starts a selection of [line] on [side] (mouse down in the gutter).
  void start(PaneSide side, int line) =>
      _set(LineSelection(side: side, anchor: line, focus: line));

  /// Moves the focus to [line], keeping the side (drag).
  void extendTo(int line) {
    final v = _value;
    if (v == null) return;
    _set(v.withFocus(line));
  }

  /// Shift+click on [line] of [side]: extends the selection when it is on
  /// the same side, else starts a new one.
  void shiftClick(PaneSide side, int line) {
    final v = _value;
    if (v == null || v.side != side) {
      start(side, line);
    } else {
      extendTo(line);
    }
  }

  /// Clears the selection.
  void clear() => _set(null);

  void _set(LineSelection? next) {
    if (next == _value) return;
    _value = next;
    for (final l in List.of(_listeners)) {
      l();
    }
  }
}

/// The clipboard text of whole lines: each line's text followed by its own
/// terminator ([DiffLine.ending]: `\n`, `\r\n`, or none for a last line
/// without one), so the copy is byte-identical to that part of the file.
String copyTextOf(Iterable<DiffLine> lines) {
  final out = StringBuffer();
  for (final l in lines) {
    out
      ..write(l.text)
      ..write(l.ending.terminator);
  }
  return out.toString();
}
