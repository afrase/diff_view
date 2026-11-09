import 'dart:typed_data';

import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/line_coords.dart';

/// What a row of a unified diff shows.
enum UnifiedRowKind {
  /// An unchanged line, shown once.
  context,

  /// An old-side line of a block (`−`).
  deleted,

  /// A new-side line of a block (`+`).
  inserted,
}

/// The rows of a unified (single-column) diff and their old and new lines.
///
/// Unchanged lines appear once. Each block shows its old lines, then its
/// new lines. An unchanged region whose sides differ in length (a
/// whitespace policy) pairs the lines it can and then shows the rest of
/// the longer side alone. Rows, like lines, are 0-based (convention 1);
/// both sides' lines appear in order, so a span of rows covers a span of
/// lines on each side.
final class UnifiedRows {
  /// Lays out the rows of [document].
  factory build(DiffDocument document) {
    final oldCount = document.oldLineCount;
    final newCount = document.newLineCount;
    var paired = 0;
    var o = 0;
    var n = 0;
    for (final b in document.blocks) {
      paired += _min(b.old.start - o, b.neu.start - n);
      o = b.old.end;
      n = b.neu.end;
    }
    paired += _min(oldCount - o, newCount - n);
    final rowCount = oldCount + newCount - paired;

    final oldBefore = Int32List(rowCount + 1);
    final newBefore = Int32List(rowCount + 1);
    final kinds = Uint8List(rowCount);
    final rowOfOld = Int32List(oldCount);
    final rowOfNew = Int32List(newCount);
    var row = 0;
    o = 0;
    n = 0;
    void emit({required bool old, required bool neu, required int kind}) {
      oldBefore[row] = o;
      newBefore[row] = n;
      kinds[row] = kind;
      if (old) rowOfOld[o++] = row;
      if (neu) rowOfNew[n++] = row;
      row++;
    }

    void context(int oldEnd, int newEnd) {
      final pairs = _min(oldEnd - o, newEnd - n);
      for (var i = 0; i < pairs; i++) {
        emit(old: true, neu: true, kind: 0);
      }
      while (o < oldEnd) {
        emit(old: true, neu: false, kind: 0);
      }
      while (n < newEnd) {
        emit(old: false, neu: true, kind: 0);
      }
    }

    for (final b in document.blocks) {
      context(b.old.start, b.neu.start);
      while (o < b.old.end) {
        emit(old: true, neu: false, kind: 1);
      }
      while (n < b.neu.end) {
        emit(old: false, neu: true, kind: 2);
      }
    }
    context(oldCount, newCount);
    oldBefore[row] = o;
    newBefore[row] = n;
    return UnifiedRows._(oldBefore, newBefore, kinds, rowOfOld, rowOfNew);
  }

  new _(
    this._oldBefore,
    this._newBefore,
    this._kinds,
    this._rowOfOld,
    this._rowOfNew,
  );

  // Lines of each side in the rows before row r (r = 0..rowCount): the
  // line row r shows, when it shows one of that side.
  final Int32List _oldBefore;
  final Int32List _newBefore;
  final Uint8List _kinds;
  final Int32List _rowOfOld;
  final Int32List _rowOfNew;

  /// Number of rows.
  int get rowCount => _kinds.length;

  /// What [row] shows.
  UnifiedRowKind kindAt(int row) => UnifiedRowKind.values[_kinds[row]];

  /// The old line [row] shows, or -1.
  int oldLineAt(int row) =>
      _oldBefore[row + 1] > _oldBefore[row] ? _oldBefore[row] : -1;

  /// The new line [row] shows, or -1.
  int newLineAt(int row) =>
      _newBefore[row + 1] > _newBefore[row] ? _newBefore[row] : -1;

  /// The line [row] shows on [side], or -1.
  int lineAt(PaneSide side, int row) =>
      side == PaneSide.old ? oldLineAt(row) : newLineAt(row);

  /// The side whose text [row] shows: the new side when the row has a new
  /// line, else the old side.
  PaneSide textSideAt(int row) =>
      _newBefore[row + 1] > _newBefore[row] ? PaneSide.neu : PaneSide.old;

  /// The row that shows [line] of [side].
  int rowOf(PaneSide side, int line) =>
      side == PaneSide.old ? _rowOfOld[line] : _rowOfNew[line];

  /// The lines of each side that the rows of [rows] show.
  ({ModelSpan old, ModelSpan neu}) linesIn(ModelSpan rows) => (
    old: ModelSpan(_oldBefore[rows.start], _oldBefore[rows.end]),
    neu: ModelSpan(_newBefore[rows.start], _newBefore[rows.end]),
  );

  /// The rows that show [old] and [neu] (either may be null), from the
  /// first such row to the last; null when both are null or empty.
  ModelSpan? rowsOf({ModelSpan? old, ModelSpan? neu}) {
    var start = -1;
    var end = -1;
    for (final (side, span) in [(PaneSide.old, old), (PaneSide.neu, neu)]) {
      if (span == null || span.isEmpty) continue;
      final s = rowOf(side, span.start);
      final e = rowOf(side, span.end - 1) + 1;
      if (start < 0 || s < start) start = s;
      if (e > end) end = e;
    }
    return start < 0 ? null : ModelSpan(start, end);
  }

  static int _min(int a, int b) => a < b ? a : b;
}
