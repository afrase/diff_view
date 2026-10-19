import 'package:side_by_side_diff/src/model/height_index.dart';
import 'package:side_by_side_diff/src/model/line_coords.dart';

/// Which part of a slot an anchor holds still.
enum AnchorPart {
  /// The slot's top, before its extras: an inlay or placeholder in the slot
  /// keeps its top and grows downward.
  slotTop,

  /// The row's top, after the slot's extras: the line itself stays put.
  rowTop,
}

/// A point of the content kept at the same viewport y across a geometry
/// change.
typedef PaneAnchor = ({int slot, AnchorPart part});

/// Vertical layout of one pane: rows, folds (hidden rows plus their
/// placeholders) and inlays, on top of a [HeightIndex].
///
/// Within a slot the order is: inlays attached below the previous row, then
/// the placeholder of a fold whose first hidden row is this one, then the
/// row. An inlay attached below a hidden row is not shown.
///
/// Every change first calls [onWillChange], so the render object can record
/// its scroll anchor against the geometry as it was.
final class PaneGeometry {
  /// Creates the geometry of a pane with [rowCount] rows.
  new({
    required this.side,
    required int rowCount,
    required double lineHeight,
    required this._placeholderHeight,
  }) : index = HeightIndex(rowCount, lineHeight);

  /// The pane's side.
  final PaneSide side;

  /// The underlying index. Read-only for callers: mutate through this
  /// class so extras stay consistent and [onWillChange] fires.
  final HeightIndex index;

  double _placeholderHeight;
  List<ModelSpan> _hidden = const [];
  final Map<int, double> _inlays = {};
  final List<void Function()> _listeners = [];

  /// Called once before each change, with the geometry still unchanged.
  void Function()? onWillChange;

  /// An anchor the pane holds still across the next change instead of the
  /// point at its anchor fraction (a toggled fold's placeholder stays
  /// under the pointer). Consumed by [takeAnchorHint].
  PaneAnchor? anchorHint;

  /// Returns and clears [anchorHint].
  PaneAnchor? takeAnchorHint() {
    final h = anchorHint;
    anchorHint = null;
    return h;
  }

  /// Bumped by [dropAnchor]; the render object discards an anchor it
  /// recorded under an older value.
  int get anchorEpoch => _anchorEpoch;
  int _anchorEpoch = 0;

  /// Discards the anchor recorded for the next layout: the caller places
  /// the content itself after this change (a jump to a line it revealed),
  /// so no correction may be added on top.
  void dropAnchor() {
    _anchorEpoch++;
    anchorHint = null;
  }

  /// Bumped by every change.
  int get revision => _revision;
  int _revision = 0;

  /// Number of rows.
  int get rowCount => index.rowCount;

  /// Height of a visible row.
  double get lineHeight => index.lineHeight;

  /// Height of a fold placeholder.
  double get placeholderHeight => _placeholderHeight;

  /// Total content height.
  double get contentHeight => index.contentHeight;

  /// Hidden spans, sorted and disjoint.
  List<ModelSpan> get hiddenSpans => _hidden;

  /// Registers [listener], called after every change.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Removes a listener.
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Changes the metrics; every height is recomputed.
  void setMetrics({
    required double lineHeight,
    required double placeholderHeight,
  }) {
    if (lineHeight == index.lineHeight &&
        placeholderHeight == _placeholderHeight) {
      return;
    }
    _willChange();
    _placeholderHeight = placeholderHeight;
    index.lineHeight = lineHeight;
    for (final span in _hidden) {
      _setExtras(span.start);
    }
    _changed();
  }

  /// Replaces the hidden spans (sorted, disjoint).
  void setHidden(List<ModelSpan> spans) {
    if (_sameSpans(spans, _hidden)) return;
    _willChange();
    final before = _hidden;
    _hidden = List.unmodifiable(spans);
    final next = spans.toSet();
    final prev = before.toSet();
    final touched = <int>{};
    for (final s in before) {
      if (next.contains(s)) continue;
      index.setRowsVisible(s, visible: true);
      touched
        ..add(s.start)
        ..add(s.end);
    }
    for (final s in spans) {
      if (prev.contains(s)) continue;
      index.setRowsVisible(s, visible: false);
      touched
        ..add(s.start)
        ..add(s.end);
    }
    touched.addAll(_inlays.keys);
    for (final slot in touched) {
      if (slot <= rowCount) _setExtras(slot);
    }
    _changed();
  }

  /// Sets the total height of the inlays in [slot] (0 removes them).
  void setInlayHeight(int slot, double height) {
    if ((_inlays[slot] ?? 0) == height) return;
    _willChange();
    if (height == 0) {
      _inlays.remove(slot);
    } else {
      _inlays[slot] = height;
    }
    _setExtras(slot);
    _changed();
  }

  /// Replaces every inlay height at once (slot → total height).
  void setInlayHeights(Map<int, double> heights) {
    final slots = {..._inlays.keys, ...heights.keys};
    if (slots.every((s) => (_inlays[s] ?? 0) == (heights[s] ?? 0))) return;
    _willChange();
    _inlays
      ..clear()
      ..addAll({
        for (final e in heights.entries)
          if (e.value > 0) e.key: e.value,
      });
    slots.forEach(_setExtras);
    _changed();
  }

  /// Requested inlay height in [slot] (shown or not).
  double inlayHeight(int slot) => _inlays[slot] ?? 0;

  /// Inlay height actually shown in [slot] (0 below a hidden row).
  double shownInlayHeight(int slot) =>
      _inlayShown(slot) ? inlayHeight(slot) : 0;

  /// Placeholder height in [slot] (0 unless a hidden span starts there).
  double placeholderAt(int slot) =>
      hiddenSpanStartingAt(slot) == null ? 0 : _placeholderHeight;

  /// Slots with extra height, ascending.
  List<int> get slotsWithExtras {
    final slots = <int>{
      for (final s in _inlays.keys)
        if (_inlayShown(s)) s,
      for (final h in _hidden) h.start,
    }.toList()..sort();
    return slots;
  }

  /// Whether [row] is visible.
  bool isRowVisible(int row) => index.isRowVisible(row);

  /// The y where [slot] begins.
  double topOfSlot(int slot) => index.topOfSlot(slot);

  /// The y where [row] begins.
  double topOfRow(int row) => index.topOfRow(row);

  /// The y of an anchor.
  double anchorY(PaneAnchor anchor) => anchor.part == AnchorPart.slotTop
      ? index.topOfSlot(anchor.slot)
      : index.topOfRow(anchor.slot);

  /// The anchor at content y: the row if y is on a row, else the slot top.
  PaneAnchor anchorAt(double y) {
    final hit = index.hit(y);
    final onRow =
        hit.slot < rowCount &&
        index.isRowVisible(hit.slot) &&
        hit.dy >= index.extraAbove(hit.slot);
    return (
      slot: hit.slot,
      part: onRow ? AnchorPart.rowTop : AnchorPart.slotTop,
    );
  }

  /// The hidden span containing [row], or null.
  ModelSpan? hiddenSpanAt(int row) {
    final i = _spanIndexAtOrBefore(row);
    if (i < 0) return null;
    final s = _hidden[i];
    return s.contains(row) ? s : null;
  }

  /// The hidden span starting at [row], or null.
  ModelSpan? hiddenSpanStartingAt(int row) {
    final i = _spanIndexAtOrBefore(row);
    if (i < 0) return null;
    final s = _hidden[i];
    return s.start == row ? s : null;
  }

  /// [row] if visible, else the first visible row after its hidden span
  /// (may be [rowCount]).
  int nextVisibleRow(int row) {
    final s = hiddenSpanAt(row);
    return s == null ? row : s.end;
  }

  /// [row] if visible, else the last visible row before its hidden span
  /// (may be -1).
  int previousVisibleRow(int row) {
    final s = hiddenSpanAt(row);
    return s == null ? row : s.start - 1;
  }

  /// The visible row [steps] visible rows away from [row] (negative moves
  /// up), clamped to the first and last visible rows.
  int stepVisible(int row, int steps) {
    var r = row;
    final dir = steps.sign;
    for (var i = 0; i < steps.abs(); i++) {
      final next = dir > 0 ? nextVisibleRow(r + 1) : previousVisibleRow(r - 1);
      if (next < 0 || next >= rowCount) break;
      r = next;
    }
    return r;
  }

  bool _inlayShown(int slot) => slot == 0 || index.isRowVisible(slot - 1);

  void _setExtras(int slot) {
    index.setExtraAbove(slot, shownInlayHeight(slot) + placeholderAt(slot));
  }

  int _spanIndexAtOrBefore(int row) {
    var lo = 0;
    var hi = _hidden.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_hidden[mid].start <= row) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo - 1;
  }

  void _willChange() => onWillChange?.call();

  void _changed() {
    _revision++;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  static bool _sameSpans(List<ModelSpan> a, List<ModelSpan> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
