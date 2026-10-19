import 'dart:typed_data';

import 'package:diff_view/src/model/line_coords.dart';

/// Vertical geometry of one pane as a Fenwick tree over slots.
///
/// Slot `i` (`0 <= i < rowCount`) is row `i` plus what is drawn between
/// row `i - 1` and row `i` (inlays below row `i - 1`, then the placeholder
/// of a fold whose first hidden row is `i`). Its height is
/// `rowHeight(i) + extraAbove(i)`, where `rowHeight(i)` is the line height
/// when the row is visible and 0 when it is folded. A sentinel slot
/// `rowCount` holds what is drawn below the last row.
///
/// Every query and point update is O(log n); bulk visibility changes larger
/// than an eighth of the rows rebuild the tree in O(n).
final class HeightIndex {
  /// Creates an index of [rowCount] visible rows of [lineHeight] and no
  /// extras.
  new(this.rowCount, double lineHeight)
    : assert(rowCount >= 0, 'rowCount must not be negative'),
      assert(lineHeight > 0, 'lineHeight must be positive'),
      _lineHeight = lineHeight,
      _visible = Uint8List(rowCount)..fillRange(0, rowCount, 1),
      _extra = Float64List(rowCount + 1),
      _tree = Float64List(rowCount + 2) {
    _topStep = _highestPowerOfTwo(_size);
    rebuild();
  }

  /// Number of rows (slots without the sentinel).
  final int rowCount;

  double _lineHeight;
  final Uint8List _visible;
  final Float64List _extra;
  // 1-based Fenwick tree over the rowCount + 1 slots.
  final Float64List _tree;
  late final int _topStep;
  double _total = 0;

  int get _size => rowCount + 1;

  /// Height of a visible row.
  double get lineHeight => _lineHeight;

  set lineHeight(double value) {
    assert(value > 0, 'lineHeight must be positive');
    if (value == _lineHeight) return;
    _lineHeight = value;
    rebuild();
  }

  /// Total height of every slot.
  double get contentHeight => _total;

  /// Whether [row] is visible (not folded).
  bool isRowVisible(int row) => _visible[row] == 1;

  /// Extra height drawn above [slot]'s row.
  double extraAbove(int slot) => _extra[slot];

  /// Height of [slot]: its row (0 when folded) plus its extras.
  double slotHeight(int slot) =>
      (slot < rowCount && _visible[slot] == 1 ? _lineHeight : 0) + _extra[slot];

  /// Shows or hides [row].
  void setRowVisible(int row, {required bool visible}) {
    final v = visible ? 1 : 0;
    if (_visible[row] == v) return;
    _visible[row] = v;
    _add(row, visible ? _lineHeight : -_lineHeight);
  }

  /// Shows or hides every row of [rows].
  void setRowsVisible(ModelSpan rows, {required bool visible}) {
    assert(rows.end <= rowCount, 'span past the last row');
    if (rows.length * 8 > rowCount) {
      _visible.fillRange(rows.start, rows.end, visible ? 1 : 0);
      rebuild();
      return;
    }
    for (var r = rows.start; r < rows.end; r++) {
      setRowVisible(r, visible: visible);
    }
  }

  /// Sets the extra height above [slot]'s row (`slot == rowCount` is the
  /// sentinel below the last row).
  void setExtraAbove(int slot, double height) {
    assert(height >= 0, 'extra height must not be negative');
    final delta = height - _extra[slot];
    if (delta == 0) return;
    _extra[slot] = height;
    _add(slot, delta);
  }

  /// The y where [slot] begins (before its extras).
  double topOfSlot(int slot) {
    var sum = 0.0;
    for (var i = slot; i > 0; i -= i & -i) {
      sum += _tree[i];
    }
    return sum;
  }

  /// The y where [row] itself begins (after the extras of its slot).
  double topOfRow(int row) => topOfSlot(row) + _extra[row];

  /// The slot containing [y] and the offset of [y] within it. A run of
  /// zero-height slots resolves to its last slot (the one that has height).
  /// Ys past the end resolve to the sentinel slot.
  ({int slot, double dy}) hit(double y) {
    var pos = 0;
    var rem = y < 0 ? 0.0 : y;
    for (var step = _topStep; step > 0; step >>= 1) {
      final next = pos + step;
      if (next <= _size && _tree[next] <= rem) {
        pos = next;
        rem -= _tree[next];
      }
    }
    // pos slots end at or before y, so y lies in slot `pos`.
    if (pos >= _size) {
      return (slot: rowCount, dy: y - topOfSlot(rowCount));
    }
    return (slot: pos, dy: rem);
  }

  /// Recomputes the tree from the row and extra arrays in O(n). Also clears
  /// rounding residue left by many point updates.
  void rebuild() {
    _tree.fillRange(0, _tree.length, 0);
    var total = 0.0;
    for (var i = 1; i <= _size; i++) {
      final h = slotHeight(i - 1);
      total += h;
      _tree[i] += h;
      final j = i + (i & -i);
      if (j <= _size) _tree[j] += _tree[i];
    }
    _total = total;
  }

  void _add(int slot, double delta) {
    for (var i = slot + 1; i <= _size; i += i & -i) {
      _tree[i] += delta;
    }
    _total += delta;
  }

  static int _highestPowerOfTwo(int n) {
    var p = 1;
    while (p * 2 <= n) {
      p *= 2;
    }
    return p;
  }
}
