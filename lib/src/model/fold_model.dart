import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/line_coords.dart';

/// The hidden spans of one fold level. A side's span is null when
/// that side keeps fewer than two lines hidden at this level.
typedef FoldLevelSpans = ({ModelSpan? old, ModelSpan? neu});

/// One foldable unchanged region (a gap) and its nested levels.
final class FoldRegion {
  new _(this.gap, this.levels);

  /// The gap this region folds.
  final DiffGap gap;

  /// Hidden spans per level, outermost (largest) first. Level `k + 1` is
  /// nested in level `k` on both sides.
  final List<FoldLevelSpans> levels;

  /// The hidden span on [side] at [level], or null.
  ModelSpan? hidden(PaneSide side, int level) {
    if (level >= levels.length) return null;
    final spans = levels[level];
    return side == PaneSide.old ? spans.old : spans.neu;
  }
}

/// Fold state of one file view, synced across both panes.
///
/// Each gap gets up to [maxLevels] nested folds. With context `ctx`, level
/// `k` keeps `ctx · 2^k` lines visible next to each neighbouring block (none
/// above a leading gap, none below a trailing one) and hides the rest of
/// the gap; a side that would hide fewer than two lines hides nothing. The
/// expanded level of a region is 0 (collapsed to level 0, the most hidden)
/// up to `levels.length` (fully expanded); each step reveals more context.
final class FoldModel {
  /// Builds the regions of [document]. A negative [context] disables
  /// folding.
  new(this.document, {this.context = 4, this.maxLevels = 3})
    : assert(maxLevels >= 1, 'at least one level'),
      regions = context < 0
          ? const []
          : _regions(document, context, maxLevels) {
    _expanded = List.filled(regions.length, 0);
    _byStart = [
      for (final side in PaneSide.values)
        [for (final r in regions) r.gap.span(side).start],
    ];
  }

  /// The document folded.
  final DiffDocument document;

  /// Lines kept next to each block at level 0.
  final int context;

  /// Nesting depth.
  final int maxLevels;

  /// Foldable regions in file order.
  final List<FoldRegion> regions;

  late final List<int> _expanded;
  late final List<List<int>> _byStart;
  final List<void Function()> _listeners = [];

  /// Registers [listener], called after every state change.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// Removes a listener.
  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// Expanded level of region [i] (`0..levels.length`).
  int expandedLevel(int i) => _expanded[i];

  /// Whether region [i] hides nothing.
  bool isExpanded(int i) => _expanded[i] >= regions[i].levels.length;

  /// Sets region [i] to [level], clamped to its range. Returns whether the
  /// state changed.
  bool setLevel(int i, int level) {
    final clamped = level.clamp(0, regions[i].levels.length);
    if (clamped == _expanded[i]) return false;
    _expanded[i] = clamped;
    _notify();
    return true;
  }

  /// Reveals one more level of region [i] (a click on its placeholder).
  bool expandOneLevel(int i) => setLevel(i, _expanded[i] + 1);

  /// Expands region [i] completely (Alt+click, "Expand all").
  bool expandAll(int i) => setLevel(i, regions[i].levels.length);

  /// Collapses region [i] to level 0.
  bool collapse(int i) => setLevel(i, 0);

  /// Collapses every region to level 0.
  void collapseEverything() => _setAll((_) => 0);

  /// Expands every region.
  void expandEverything() => _setAll((i) => regions[i].levels.length);

  /// Sets every region at once (one notification).
  void setLevels(int Function(int region) level) =>
      _setAll((i) => level(i).clamp(0, regions[i].levels.length));

  /// The span region [i] hides on [side] now, or null.
  ModelSpan? hiddenSpan(int i, PaneSide side) =>
      regions[i].hidden(side, _expanded[i]);

  /// Every span hidden on [side] now, in file order, with its region.
  Iterable<(int, ModelSpan)> hiddenSpans(PaneSide side) sync* {
    for (var i = 0; i < regions.length; i++) {
      final span = hiddenSpan(i, side);
      if (span != null) yield (i, span);
    }
  }

  /// The region whose gap contains [line] on [side], or -1.
  int regionAt(PaneSide side, int line) {
    final starts = _byStart[side.index];
    var lo = 0;
    var hi = starts.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (starts[mid] <= line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = lo - 1;
    if (i < 0) return -1;
    return regions[i].gap.span(side).contains(line) ? i : -1;
  }

  /// Expands, as little as needed, so that [line] on [side] is visible
  /// (navigation targets and thread anchors,  pins). Returns whether
  /// anything changed.
  bool reveal(PaneSide side, int line) {
    final i = regionAt(side, line);
    if (i < 0) return false;
    var level = _expanded[i];
    while (regions[i].hidden(side, level)?.contains(line) ?? false) {
      level++;
    }
    return setLevel(i, level);
  }

  void _setAll(int Function(int region) level) {
    var changed = false;
    for (var i = 0; i < regions.length; i++) {
      final l = level(i);
      if (l != _expanded[i]) {
        _expanded[i] = l;
        changed = true;
      }
    }
    if (changed) _notify();
  }

  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  static List<FoldRegion> _regions(DiffDocument doc, int ctx, int maxLevels) {
    final out = <FoldRegion>[];
    for (final gap in doc.gaps) {
      final trailing =
          gap.old.end == doc.oldLineCount && gap.neu.end == doc.newLineCount;
      final levels = <FoldLevelSpans>[];
      for (var k = 0; k < maxLevels; k++) {
        final keep = ctx << k;
        final lead = gap.isLeading ? 0 : keep;
        final trail = trailing ? 0 : keep;
        ModelSpan? hide(ModelSpan s) {
          final start = s.start + lead;
          final end = s.end - trail;
          return end - start >= 2 ? ModelSpan(start, end) : null;
        }

        final spans = (old: hide(gap.old), neu: hide(gap.neu));
        if (spans.old == null && spans.neu == null) break;
        levels.add(spans);
      }
      if (levels.isNotEmpty) out.add(FoldRegion._(gap, levels));
    }
    return List.unmodifiable(out);
  }
}
