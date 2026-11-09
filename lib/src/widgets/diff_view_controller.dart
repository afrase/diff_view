import 'dart:async';

import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/diff_line.dart';
import 'package:diff_view/src/model/fold_model.dart';
import 'package:diff_view/src/model/inlays.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/line_source.dart';
import 'package:diff_view/src/model/pane_geometry.dart';
import 'package:diff_view/src/model/selection.dart';
import 'package:diff_view/src/model/sync_map.dart';
import 'package:diff_view/src/model/unified_rows.dart';
import 'package:diff_view/src/render/diff_theme.dart';
import 'package:diff_view/src/render/paint_resources.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Called after a pane painted its selection overlay (tests and probes).
typedef SelectionPaintObserver = void Function(
  PaneSide side,
  LineSelection? selection,
);

final class _Signal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// State of one open side-by-side file view : folds,
/// both panes' geometry and scroll controllers, the sync coupling, inlays
/// and the line selection.
///
/// A unified view of the same file (`UnifiedDiff`) shares the folds,
/// inlays, theme and caches, and has its own rows, geometry, scroll
/// controller and selection. The scroll methods ([jumpToLine],
/// [viewportYOfLine], [ensureLineVisible]) act on the side-by-side panes
/// when they are laid out, else on the unified view. When one view
/// replaces the other, the new one opens at the line the old one showed.
///
/// Create one per open file and dispose it when the file closes.
class DiffViewController extends ChangeNotifier {
  /// Creates the view state of [document] with rows from [lines].
  new({
    required this.document,
    required this.lines,
    required DiffThemeData theme,
    this.captureNames = const [],
    int foldContext = 4,
    double devicePixelRatio = 2,
    this.maxCachedLines = DiffPaintResources.defaultMaxCachedLines,
  }) : folds = FoldModel(document, context: foldContext),
       _resources = DiffPaintResources(
         theme: theme,
         captureNames: captureNames,
         devicePixelRatio: devicePixelRatio,
         maxLineCount: document.oldLineCount > document.newLineCount
             ? document.oldLineCount
             : document.newLineCount,
         maxCachedLines: maxCachedLines,
       ) {
    _geometries = [
      for (final side in PaneSide.values)
        PaneGeometry(
          side: side,
          rowCount: document.lineCount(side),
          lineHeight: _resources.lineHeight,
          placeholderHeight: _resources.placeholderHeight,
        )..addListener(_geometryChanged),
    ];
    folds.addListener(_applyFolds);
    _applyFolds();
    for (final side in PaneSide.values) {
      _scrolls[side.index].addListener(() => _onScroll(side));
    }
    _unifiedScroll.addListener(reclampHorizontal);
    selection.addListener(_selectionSignal.fire);
    unifiedSelection.addListener(_selectionSignal.fire);
  }

  /// The file's header.
  final DiffDocument document;

  /// Row source.
  final DiffLineSource lines;

  /// Capacity of the line layout cache.
  final int maxCachedLines;

  /// Capture names of the file's syntax tokens (id → name).
  final List<String> captureNames;

  /// Fold state, shared by both panes.
  final FoldModel folds;

  /// The gutter line selection.
  final LineSelectionController selection = LineSelectionController();

  /// The gutter row selection of the unified view.
  final RowSelectionController unifiedSelection = RowSelectionController();

  /// Horizontal code offset, shared by both panes.
  final ValueNotifier<double> horizontal = ValueNotifier(0);

  /// Whether the panes scroll together (setting `diff.sync_scroll`).
  bool syncEnabled = true;

  /// Paint probe for panes. A unified view reports [PaneSide.neu].
  void Function(PaneSide side, double pixels)? onPanePaint;

  /// Paint probe for selection overlays.
  SelectionPaintObserver? onSelectionPaint;

  DiffPaintResources _resources;
  late final List<PaneGeometry> _geometries;
  final List<ScrollController> _scrolls = [
    ScrollController(debugLabel: 'diff.old'),
    ScrollController(debugLabel: 'diff.new'),
  ];
  final ScrollController _unifiedScroll = ScrollController(
    debugLabel: 'diff.unified',
  );
  UnifiedRows? _unifiedRows;
  PaneGeometry? _unifiedGeometry;
  // Fold region of each unified hidden span, by its first row.
  Map<int, int> _unifiedFoldRegions = const {};
  final _Signal _geometrySignal = _Signal();
  final _Signal _selectionSignal = _Signal();
  final SyncScrollState _sync = SyncScrollState();
  SyncMap? _syncMap;
  PaneSide _master = PaneSide.neu;
  bool _syncing = false;
  bool _resyncScheduled = false;
  double? _codeWidth;
  List<InlaySpec> _inlays = const [];
  // A jump asked for before its pane was laid out, made after a frame.
  (PaneSide, int, double?)? _pendingJump;
  bool _pendingJumpScheduled = false;
  bool _disposed = false;

  /// Paint resources (theme, caches, metrics).
  DiffPaintResources get resources => _resources;

  /// The geometry of [side]'s pane.
  PaneGeometry geometry(PaneSide side) => _geometries[side.index];

  /// The scroll controller of [side]'s pane.
  ScrollController scroll(PaneSide side) => _scrolls[side.index];

  /// The rows of the unified view, built on first use.
  UnifiedRows get unifiedRows => _unifiedRows ??= UnifiedRows.build(document);

  /// The geometry of the unified view, built on first use.
  PaneGeometry get unifiedGeometry {
    final existing = _unifiedGeometry;
    if (existing != null) return existing;
    final g = PaneGeometry(
      side: PaneSide.neu,
      rowCount: unifiedRows.rowCount,
      lineHeight: _resources.lineHeight,
      placeholderHeight: _resources.placeholderHeight,
    );
    _unifiedGeometry = g;
    _applyUnifiedFolds(g);
    g.addListener(_geometryChanged);
    return g;
  }

  /// The scroll controller of the unified view.
  ScrollController get unifiedScroll => _unifiedScroll;

  /// Fires when either pane's geometry, or the unified view's, changes.
  Listenable get geometryChanges => _geometrySignal;

  /// Fires when the selection or the unified selection changes.
  Listenable get selectionChanges => _selectionSignal;

  /// The inlays of both panes. Changing them notifies listeners.
  List<InlaySpec> get inlays => _inlays;
  set inlays(List<InlaySpec> value) {
    _inlays = List.unmodifiable(value);
    notifyListeners();
  }

  /// The unified slot [spec] is drawn in: the slot after the row of its
  /// line, whichever side the line is on (0 above the first row).
  int unifiedSlotOf(InlaySpec spec) {
    final count = document.lineCount(spec.side);
    if (spec.afterLine < 0 || count == 0) return 0;
    final line = spec.afterLine < count ? spec.afterLine : count - 1;
    return unifiedRows.rowOf(spec.side, line) + 1;
  }

  /// Adds [spec], revealing its line if a fold hides it.
  void addInlay(InlaySpec spec) {
    if (spec.afterLine >= 0) folds.reveal(spec.side, spec.afterLine);
    inlays = [..._inlays, spec];
  }

  /// Removes the inlay with [id].
  void removeInlay(String id) => inlays = [
    for (final s in _inlays)
      if (s.id != id) s,
  ];

  /// The pane that drives sync scrolling: the one the user scrolled last.
  PaneSide get master => _master;
  set master(PaneSide value) {
    if (value == _master) return;
    _master = value;
    _sync.reset();
  }

  /// The sync map, rebuilt lazily after geometry changes.
  SyncMap get syncMap => _syncMap ??= SyncMap.build(
    document,
    geometry(PaneSide.old),
    geometry(PaneSide.neu),
  );

  /// Updates the theme and the device pixel ratio the metrics snap to.
  void configure({
    required DiffThemeData theme,
    required double devicePixelRatio,
  }) {
    if (identical(theme, _resources.theme) &&
        devicePixelRatio == _resources.devicePixelRatio) {
      return;
    }
    final old = _resources;
    _resources = DiffPaintResources(
      theme: theme,
      captureNames: captureNames,
      devicePixelRatio: devicePixelRatio,
      maxLineCount: document.oldLineCount > document.newLineCount
          ? document.oldLineCount
          : document.newLineCount,
      maxCachedLines: maxCachedLines,
    );
    for (final g in [..._geometries, ?_unifiedGeometry]) {
      g.setMetrics(
        lineHeight: _resources.lineHeight,
        placeholderHeight: _resources.placeholderHeight,
      );
    }
    notifyListeners();
    SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  /// Expands fold [region] by one level, or completely with [all]. The
  /// placeholder clicked stays where it is.
  void toggleFold(int region, {bool all = false}) {
    for (final side in PaneSide.values) {
      final span = folds.hiddenSpan(region, side);
      if (span != null) {
        geometry(side).anchorHint = (
          slot: span.start,
          part: AnchorPart.slotTop,
        );
      }
    }
    final unified = _unifiedGeometry;
    final rows = unified == null ? const <ModelSpan>[] : _unifiedHidden(region);
    if (unified != null && rows.isNotEmpty) {
      unified.anchorHint = (slot: rows.first.start, part: AnchorPart.slotTop);
    }
    if (all) {
      folds.expandAll(region);
    } else {
      folds.expandOneLevel(region);
    }
    // A view that is not laid out took no hint; it must not keep it for a
    // later change.
    for (final g in [..._geometries, ?unified]) {
      g.anchorHint = null;
    }
  }

  /// The fold region whose placeholder is drawn in [slot] of [side], or -1.
  int foldRegionAtSlot(PaneSide side, int slot) {
    final span = geometry(side).hiddenSpanStartingAt(slot);
    return span == null ? -1 : folds.regionAt(side, span.start);
  }

  /// The fold region whose placeholder is drawn in [slot] of the unified
  /// view, or -1.
  int unifiedFoldRegionAtSlot(int slot) => _unifiedFoldRegions[slot] ?? -1;

  /// Scrolls [side] so model line [line] sits at [viewportY] (default: the
  /// 1/3 anchor), revealing it if folded, and makes [side] the master.
  /// A [line] outside the side's lines is clamped to the first or last.
  /// In a unified view it scrolls the row that shows the line.
  ///
  /// Before the pane is laid out (no scroll position yet, as when a file is
  /// opened at line N), nothing changes now: the jump is kept and made
  /// after the first frame that lays the pane out. A later jump replaces
  /// it.
  void jumpToLine(PaneSide side, int line, {double? viewportY}) {
    final c = scroll(side);
    final split = c.hasClients && c.position.hasContentDimensions;
    final u = _unifiedScroll;
    if (!split && !(u.hasClients && u.position.hasContentDimensions)) {
      _pendingJump = (side, line, viewportY);
      _schedulePendingJump();
      return;
    }
    _pendingJump = null;
    final count = geometry(side).rowCount;
    if (count == 0) return;
    final target = line.clamp(0, count - 1);
    final g = split ? geometry(side) : unifiedGeometry;
    folds.reveal(side, target);
    // The reveal recorded an anchor at the old position; this jump places
    // the content itself, so layout must not correct on top of it. The
    // geometry is already updated, the scroll extent only at layout: clamp
    // against the new content height.
    g.dropAnchor();
    if (split) master = side;
    final row = split ? target : unifiedRows.rowOf(side, target);
    final position = split ? c.position : u.position;
    final y = viewportY ?? position.viewportDimension / 3;
    final maxExtent = g.contentHeight - position.viewportDimension;
    position.jumpTo(
      (g.topOfRow(row) - y).clamp(
        position.minScrollExtent,
        maxExtent < position.minScrollExtent
            ? position.minScrollExtent
            : maxExtent,
      ),
    );
  }

  /// Keeps the line the leaving view shows at its anchor, so the view that
  /// replaces it opens there: called by `SideBySideDiff` and `UnifiedDiff`
  /// as they leave the tree, while their scroll positions still exist.
  @internal
  void keepPosition({required bool unified}) {
    // An empty master (the old pane of an added file) has no line to
    // keep; the other pane has.
    final pane = geometry(_master).rowCount == 0 ? _master.other : _master;
    final s = unified ? _unifiedScroll : scroll(pane);
    if (!s.hasClients || !s.position.hasContentDimensions) return;
    final g = unified ? unifiedGeometry : geometry(pane);
    if (g.rowCount == 0) return;
    final p = s.position;
    final hit = g.index.hit(p.pixels + p.viewportDimension / 3).slot;
    var row = g.nextVisibleRow(hit < g.rowCount ? hit : g.rowCount - 1);
    if (row >= g.rowCount) row = g.previousVisibleRow(g.rowCount - 1);
    if (row < 0) return;
    final side = unified ? unifiedRows.textSideAt(row) : pane;
    final line = unified ? unifiedRows.lineAt(side, row) : row;
    _pendingJump = (side, line, g.topOfRow(row) - p.pixels);
    _schedulePendingJump();
  }

  void _schedulePendingJump() {
    if (_pendingJumpScheduled) return;
    _pendingJumpScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendingJumpScheduled = false;
      final jump = _pendingJump;
      if (_disposed || jump == null) return;
      // Still not laid out: jumpToLine waits for the next frame again.
      jumpToLine(jump.$1, jump.$2, viewportY: jump.$3);
    });
  }

  /// Where model line [line] of [side] is in its viewport now, or null if
  /// the pane is not laid out. In a unified view, where the row that shows
  /// the line is.
  double? viewportYOfLine(PaneSide side, int line) {
    final c = scroll(side);
    if (c.hasClients) return geometry(side).topOfRow(line) - c.position.pixels;
    if (!_unifiedScroll.hasClients) return null;
    final row = unifiedRows.rowOf(side, line);
    return unifiedGeometry.topOfRow(row) - _unifiedScroll.position.pixels;
  }

  /// Scrolls [side] the least amount that shows model line [line]. In a
  /// unified view it shows the row of the line.
  void ensureLineVisible(PaneSide side, int line) {
    final c = scroll(side);
    if (!c.hasClients) {
      if (line >= 0 && line < document.lineCount(side)) {
        ensureUnifiedRowVisible(unifiedRows.rowOf(side, line));
      }
      return;
    }
    master = side;
    _scrollToShow(c.position, geometry(side), line);
  }

  /// Scrolls the unified view the least amount that shows [row].
  void ensureUnifiedRowVisible(int row) {
    if (!_unifiedScroll.hasClients) return;
    _scrollToShow(_unifiedScroll.position, unifiedGeometry, row);
  }

  static void _scrollToShow(ScrollPosition p, PaneGeometry g, int row) {
    final top = g.topOfRow(row);
    final bottom = top + g.lineHeight;
    if (top < p.pixels) {
      p.jumpTo(top.clamp(p.minScrollExtent, p.maxScrollExtent));
    } else if (bottom > p.pixels + p.viewportDimension) {
      p.jumpTo(
        (bottom - p.viewportDimension).clamp(
          p.minScrollExtent,
          p.maxScrollExtent,
        ),
      );
    }
  }

  /// Moves the shared horizontal offset by [dx], clamped to the widest
  /// line on screen in either pane or the unified view. [codeWidth] is the
  /// width of a pane's code area; it is remembered so the offset is clamped
  /// again when vertical scrolling or a geometry change brings shorter
  /// lines into view (otherwise both panes could show only empty rows).
  void scrollHorizontally(double dx, {required double codeWidth}) {
    _codeWidth = codeWidth;
    horizontal.value = (horizontal.value + dx).clamp(
      0.0,
      _maxHorizontal(codeWidth),
    );
  }

  double _maxHorizontal(double codeWidth) =>
      (_maxLineWidth() - codeWidth + 2 * resources.advance).clamp(
        0.0,
        double.infinity,
      );

  /// Clamps the horizontal offset to the lines on screen now. Only ever
  /// moves it left.
  void reclampHorizontal() {
    final w = _codeWidth;
    if (w == null || horizontal.value == 0) return;
    final max = _maxHorizontal(w);
    if (horizontal.value > max) horizontal.value = max;
  }

  double _maxLineWidth() {
    var w = 0.0;
    for (final side in PaneSide.values) {
      final c = scroll(side);
      if (!c.hasClients) continue;
      final width = _widestOnScreen(
        geometry(side),
        c.position,
        (r) => (side, r),
      );
      if (width > w) w = width;
    }
    if (_unifiedScroll.hasClients) {
      final rows = unifiedRows;
      final width = _widestOnScreen(unifiedGeometry, _unifiedScroll.position, (
        r,
      ) {
        final side = rows.textSideAt(r);
        return (side, rows.lineAt(side, r));
      });
      if (width > w) w = width;
    }
    return w;
  }

  // The widest line drawn in [g]'s viewport; [lineOf] maps a row to the
  // side and line it shows.
  double _widestOnScreen(
    PaneGeometry g,
    ScrollPosition position,
    (PaneSide, int) Function(int row) lineOf,
  ) {
    var w = 0.0;
    final p = position.pixels;
    final first = g.index.hit(p).slot;
    final last = g.index.hit(p + position.viewportDimension).slot;
    // Visible rows only, as paint draws them: a fold on screen hides
    // rows that neither count nor get a layout built.
    for (
      var r = g.nextVisibleRow(first);
      r <= last && r < g.rowCount;
      r = g.nextVisibleRow(r + 1)
    ) {
      final (side, number) = lineOf(r);
      final line = lines.lineAt(side, number);
      if (line == null) continue;
      final layout = resources.lines.getOrBuild(
        side.index | (number << 1),
        line,
        () => resources.layouts.build(line),
      );
      if (layout.width > w) w = layout.width;
    }
    return w;
  }

  /// Copies the selected lines of the selection's side to the clipboard,
  /// loading rows that are not in memory. Returns the text, or
  /// null when nothing is selected.
  Future<String?> copySelection() async {
    final sel = selection.value;
    if (sel == null) return null;
    final text = copyTextOf(await lines.load(sel.side, sel.span));
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  /// Copies the shown text of the unified selection's rows to the
  /// clipboard (see [unifiedTextOf]). Returns the text, or null when
  /// nothing is selected.
  Future<String?> copyUnifiedSelection() async {
    final sel = unifiedSelection.value;
    if (sel == null) return null;
    final text = await unifiedTextOf(sel.span);
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  /// The text the unified [rows] show, without markers: each row's line
  /// (the new one of an unchanged row) with its terminator, loading lines
  /// that are not in memory. A line without a terminator (an old last
  /// line) that is not the last one copied ends with the next line's
  /// terminator, or `\n`.
  Future<String> unifiedTextOf(ModelSpan rows) async {
    final r = unifiedRows;
    final spans = r.linesIn(rows);
    final old = spans.old.isEmpty
        ? const <DiffLine>[]
        : await lines.load(PaneSide.old, spans.old);
    final neu = spans.neu.isEmpty
        ? const <DiffLine>[]
        : await lines.load(PaneSide.neu, spans.neu);
    final shown = [
      for (var row = rows.start; row < rows.end; row++)
        if (r.newLineAt(row) >= 0)
          neu[r.newLineAt(row) - spans.neu.start]
        else
          old[r.oldLineAt(row) - spans.old.start],
    ];
    final out = StringBuffer();
    for (var i = 0; i < shown.length; i++) {
      final l = shown[i];
      var end = l.ending.terminator;
      if (end.isEmpty && i + 1 < shown.length) {
        final next = shown[i + 1].ending.terminator;
        end = next.isEmpty ? '\n' : next;
      }
      out
        ..write(l.text)
        ..write(end);
    }
    return out.toString();
  }

  /// Re-aligns the slave pane to the master now.
  void syncNow() {
    if (!syncEnabled) return;
    final m = scroll(_master);
    final s = scroll(_master.other);
    if (!m.hasClients || !s.hasClients) return;
    final mp = m.position;
    final sp = s.position;
    if (!mp.hasContentDimensions || !sp.hasContentDimensions) return;
    final target = _sync.slaveOffsetFor(
      map: syncMap,
      master: _master,
      m: mp.pixels,
      viewportHeight: mp.viewportDimension,
      masterMax: mp.maxScrollExtent,
      slaveMax: sp.maxScrollExtent,
      devicePixelRatio: resources.devicePixelRatio,
      lineHeight: resources.lineHeight,
    );
    if ((target - sp.pixels).abs() < 1e-3) return;
    _syncing = true;
    try {
      sp.jumpTo(target);
    } finally {
      _syncing = false;
    }
  }

  void _onScroll(PaneSide side) {
    if (_syncing || side != _master) return;
    syncNow();
    reclampHorizontal();
  }

  void _applyFolds() {
    for (final side in PaneSide.values) {
      geometry(side)
          .setHidden([for (final (_, span) in folds.hiddenSpans(side)) span]);
    }
    final unified = _unifiedGeometry;
    if (unified != null) _applyUnifiedFolds(unified);
  }

  // The unified rows region [i] hides now: the rows whose lines are hidden
  // on their own sides. A region whose sides differ in length can hide
  // two spans (paired rows, then rows of the longer side alone).
  List<ModelSpan> _unifiedHidden(int i) => unifiedRows.rowsWithin(
    old: folds.hiddenSpan(i, PaneSide.old),
    neu: folds.hiddenSpan(i, PaneSide.neu),
  );

  void _applyUnifiedFolds(PaneGeometry g) {
    final spans = <ModelSpan>[];
    final regions = <int, int>{};
    for (var i = 0; i < folds.regions.length; i++) {
      for (final span in _unifiedHidden(i)) {
        spans.add(span);
        regions[span.start] = i;
      }
    }
    _unifiedFoldRegions = regions;
    g.setHidden(spans);
  }

  void _geometryChanged() {
    _syncMap = null;
    _geometrySignal.fire();
    if (_resyncScheduled) return;
    _resyncScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _resyncScheduled = false;
      syncNow();
      reclampHorizontal();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    folds.removeListener(_applyFolds);
    for (final g in [..._geometries, ?_unifiedGeometry]) {
      g.removeListener(_geometryChanged);
    }
    for (final c in _scrolls) {
      c.dispose();
    }
    _unifiedScroll.dispose();
    _geometrySignal.dispose();
    _selectionSignal.dispose();
    horizontal.dispose();
    unawaited(Future<void>.value().then((_) => _resources.dispose()));
    super.dispose();
  }
}
