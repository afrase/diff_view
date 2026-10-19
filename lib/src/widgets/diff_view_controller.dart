import 'dart:async';

import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/fold_model.dart';
import 'package:diff_view/src/model/inlays.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/line_source.dart';
import 'package:diff_view/src/model/pane_geometry.dart';
import 'package:diff_view/src/model/selection.dart';
import 'package:diff_view/src/model/sync_map.dart';
import 'package:diff_view/src/render/diff_theme.dart';
import 'package:diff_view/src/render/paint_resources.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
    selection.addListener(_selectionSignal.fire);
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

  /// Horizontal code offset, shared by both panes.
  final ValueNotifier<double> horizontal = ValueNotifier(0);

  /// Whether the panes scroll together (setting `diff.sync_scroll`).
  bool syncEnabled = true;

  /// Paint probe for panes.
  void Function(PaneSide side, double pixels)? onPanePaint;

  /// Paint probe for selection overlays.
  SelectionPaintObserver? onSelectionPaint;

  DiffPaintResources _resources;
  late final List<PaneGeometry> _geometries;
  final List<ScrollController> _scrolls = [
    ScrollController(debugLabel: 'diff.old'),
    ScrollController(debugLabel: 'diff.new'),
  ];
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

  /// Fires when either pane's geometry changes.
  Listenable get geometryChanges => _geometrySignal;

  /// Fires when the selection changes.
  Listenable get selectionChanges => _selectionSignal;

  /// The inlays of both panes. Changing them notifies listeners.
  List<InlaySpec> get inlays => _inlays;
  set inlays(List<InlaySpec> value) {
    _inlays = List.unmodifiable(value);
    notifyListeners();
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
    for (final g in _geometries) {
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
    if (all) {
      folds.expandAll(region);
    } else {
      folds.expandOneLevel(region);
    }
  }

  /// The fold region whose placeholder is drawn in [slot] of [side], or -1.
  int foldRegionAtSlot(PaneSide side, int slot) {
    final span = geometry(side).hiddenSpanStartingAt(slot);
    return span == null ? -1 : folds.regionAt(side, span.start);
  }

  /// Scrolls [side] so model line [line] sits at [viewportY] (default: the
  /// 1/3 anchor), revealing it if folded, and makes [side] the master.
  /// A [line] outside the side's lines is clamped to the first or last.
  ///
  /// Before the pane is laid out (no scroll position yet, as when a file is
  /// opened at line N), nothing changes now: the jump is kept and made
  /// after the first frame that lays the pane out. A later jump replaces
  /// it.
  void jumpToLine(PaneSide side, int line, {double? viewportY}) {
    final c = scroll(side);
    if (!c.hasClients || !c.position.hasContentDimensions) {
      _pendingJump = (side, line, viewportY);
      _schedulePendingJump();
      return;
    }
    _pendingJump = null;
    final count = geometry(side).rowCount;
    if (count == 0) return;
    final target = line.clamp(0, count - 1);
    final g = geometry(side);
    folds.reveal(side, target);
    // The reveal recorded an anchor at the old position; this jump places
    // the content itself, so layout must not correct on top of it. The
    // geometry is already updated, the scroll extent only at layout: clamp
    // against the new content height.
    g.dropAnchor();
    master = side;
    final position = c.position;
    final y = viewportY ?? position.viewportDimension / 3;
    final maxExtent = g.contentHeight - position.viewportDimension;
    position.jumpTo(
      (g.topOfRow(target) - y).clamp(
        position.minScrollExtent,
        maxExtent < position.minScrollExtent
            ? position.minScrollExtent
            : maxExtent,
      ),
    );
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
  /// the pane is not laid out.
  double? viewportYOfLine(PaneSide side, int line) {
    final c = scroll(side);
    if (!c.hasClients) return null;
    return geometry(side).topOfRow(line) - c.position.pixels;
  }

  /// Scrolls [side] the least amount that shows model line [line].
  void ensureLineVisible(PaneSide side, int line) {
    final c = scroll(side);
    if (!c.hasClients) return;
    master = side;
    final p = c.position;
    final top = geometry(side).topOfRow(line);
    final bottom = top + geometry(side).lineHeight;
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
  /// line on screen in either pane. [codeWidth] is the width of a pane's
  /// code area; it is remembered so the offset is clamped again when
  /// vertical scrolling or a geometry change brings shorter lines into view
  /// (otherwise both panes could show only empty rows).
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
      final g = geometry(side);
      final p = c.position.pixels;
      final first = g.index.hit(p).slot;
      final last = g.index.hit(p + c.position.viewportDimension).slot;
      // Visible rows only, as paint draws them: a fold on screen hides
      // rows that neither count nor get a layout built.
      for (
        var r = g.nextVisibleRow(first);
        r <= last && r < g.rowCount;
        r = g.nextVisibleRow(r + 1)
      ) {
        final line = lines.lineAt(side, r);
        if (line == null) continue;
        final layout = resources.lines.getOrBuild(
          side.index | (r << 1),
          line,
          () => resources.layouts.build(line),
        );
        if (layout.width > w) w = layout.width;
      }
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
    for (final g in _geometries) {
      g.removeListener(_geometryChanged);
    }
    for (final c in _scrolls) {
      c.dispose();
    }
    _geometrySignal.dispose();
    _selectionSignal.dispose();
    horizontal.dispose();
    unawaited(Future<void>.value().then((_) => _resources.dispose()));
    super.dispose();
  }
}
