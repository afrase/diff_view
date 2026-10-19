import 'dart:math' as math;
import 'dart:typed_data';

import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/pane_geometry.dart';

/// Monotone piecewise-linear map between the two panes' content ys
///.
///
/// Knots come from IntelliJ's boundary pairs, the point where the shorter
/// side of an unequal block stops, and every slot with extra height (inlays,
/// fold placeholders) on either side, each placed before and after that
/// slot's extras. Consequences:
/// - in equal regions without extras the slope is exactly 1;
/// - inside an unequal block the shorter side tracks 1:1 and then holds;
/// - an inlay on one side maps to a flat segment on the other.
final class SyncMap {
  new _(this._old, this._neu);

  /// Builds the map of [document] over the two geometries.
  factory build(
    DiffDocument document,
    PaneGeometry oldPane,
    PaneGeometry newPane,
  ) {
    final events = <(int, int)>[...document.syncPairs];
    for (final b in document.blocks) {
      if (b.old.length != b.neu.length) {
        final m = math.min(b.old.length, b.neu.length);
        events.add((b.old.start + m, b.neu.start + m));
      }
    }
    for (final s in oldPane.slotsWithExtras) {
      events.add((s, _transferSlot(document, s, PaneSide.old)));
    }
    for (final s in newPane.slotsWithExtras) {
      events.add((_transferSlot(document, s, PaneSide.neu), s));
    }
    events.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    final xs = Float64List(events.length * 2 + 1);
    final ys = Float64List(events.length * 2 + 1);
    var n = 0;
    var px = 0.0;
    var py = 0.0;
    void knot(double x, double y) {
      px = math.max(px, x);
      py = math.max(py, y);
      if (n > 0 && xs[n - 1] == px && ys[n - 1] == py) return;
      xs[n] = px;
      ys[n] = py;
      n++;
    }

    (int, int)? last;
    for (final e in events) {
      if (e == last) continue;
      last = e;
      final (lo, ln) = e;
      knot(oldPane.topOfSlot(lo), newPane.topOfSlot(ln));
      knot(_rowTop(oldPane, lo), _rowTop(newPane, ln));
    }
    knot(oldPane.contentHeight, newPane.contentHeight);
    return SyncMap._(
      Float64List.sublistView(xs, 0, n),
      Float64List.sublistView(ys, 0, n),
    );
  }

  final Float64List _old;
  final Float64List _neu;

  /// Number of knots.
  int get knotCount => _old.length;

  /// Knot [i] as `(oldY, newY)`.
  (double, double) knot(int i) => (_old[i], _neu[i]);

  /// Maps content y [y] on [from] to the other pane.
  double map(double y, PaneSide from) {
    final xs = from == PaneSide.old ? _old : _neu;
    final ys = from == PaneSide.old ? _neu : _old;
    if (xs.isEmpty) return y;
    if (y <= xs.first) return ys.first + (y - xs.first);
    if (y >= xs.last) return ys.last + (y - xs.last);
    // Last knot with x <= y.
    var lo = 0;
    var hi = xs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (xs[mid] <= y) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = lo - 1;
    final x0 = xs[i];
    final x1 = xs[i + 1];
    if (x1 == x0) return ys[i + 1];
    return ys[i] + (ys[i + 1] - ys[i]) * (y - x0) / (x1 - x0);
  }

  static double _rowTop(PaneGeometry g, int slot) =>
      slot >= g.rowCount ? g.topOfSlot(slot) : g.topOfRow(slot);

  // transferLine for a slot: the sentinel slot maps to the other sentinel.
  static int _transferSlot(DiffDocument d, int slot, PaneSide from) {
    if (slot >= d.lineCount(from)) return d.lineCount(from.other);
    return d.transferLine(slot, from);
  }
}

/// Where the slave pane scrolls for a master offset: the content
/// at 1/3 of the viewport stays level across panes, blending to the top and
/// bottom edges so both panes reach their ends together, snapped to
/// physical pixels, with IntelliJ's hysteresis against sub-line reversals.
final class SyncScrollState {
  double? _lastMaster;
  double? _lastSlave;

  /// Forgets the hysteresis history (after a jump or a master change).
  void reset() {
    _lastMaster = null;
    _lastSlave = null;
  }

  /// The slave offset for master offset [m].
  double slaveOffsetFor({
    required SyncMap map,
    required PaneSide master,
    required double m,
    required double viewportHeight,
    required double masterMax,
    required double slaveMax,
    required double devicePixelRatio,
    required double lineHeight,
  }) {
    final h = viewportHeight;
    var y = 0.0;
    if (h > 0) {
      var a = math.min(1 / 3, m / h);
      a = math.max(a, 1 - (masterMax - m) / h);
      a = a.clamp(0.0, 1.0);
      y = map.map(m + a * h, master) - a * h;
    } else {
      y = map.map(m, master);
    }
    y = y.clamp(0.0, math.max(0, slaveMax));
    y = (y * devicePixelRatio).roundToDouble() / devicePixelRatio;
    final lm = _lastMaster;
    final ls = _lastSlave;
    if (lm != null && ls != null) {
      final ds = y - ls;
      final dm = m - lm;
      if (ds.sign == -dm.sign && ds != 0 && ds.abs() < lineHeight) y = ls;
    }
    _lastMaster = m;
    _lastSlave = y;
    return y;
  }
}
