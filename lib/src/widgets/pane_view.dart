import 'dart:async';
import 'dart:math' as math;

import 'package:diff_view/src/model/code_selection.dart';
import 'package:diff_view/src/model/diff_line.dart';
import 'package:diff_view/src/model/inlays.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/pane_geometry.dart';
import 'package:diff_view/src/model/unified_rows.dart';
import 'package:diff_view/src/render/paint_resources.dart';
import 'package:diff_view/src/render/render_diff_pane.dart';
import 'package:diff_view/src/widgets/diff_pane.dart';
import 'package:diff_view/src/widgets/diff_view_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// One scrollable column of a diff view and how its input reaches the
/// controller: a pane of a side-by-side view ([SidePaneModel]) or the
/// column of a unified view ([UnifiedPaneModel]). Rows are the column's
/// geometry rows.
@immutable
sealed class PaneModel {
  const new(this.controller);

  /// The file view.
  final DiffViewController controller;

  /// The side reported to paint probes.
  PaneSide get side;

  /// The rows of a unified view, or null.
  UnifiedRows? get unified;

  /// Vertical layout of the column.
  PaneGeometry get geometry;

  /// The column's scroll controller.
  ScrollController get scroll;

  /// Horizontal layout of the column.
  GutterMetrics get gutter;

  /// Marks the column as the one the user scrolled last.
  void makeMaster();

  /// The fold region whose placeholder is drawn in [slot], or -1.
  int foldRegionAtSlot(int slot);

  /// The slot [spec] is drawn in, or null when it belongs to another pane.
  int? inlaySlot(InlaySpec spec);

  /// The selection's anchor and focus, whichever column it is in, or null.
  ({int anchor, int focus})? get selection;

  /// The rows selected in this column, or null.
  ModelSpan? get selectedRows;

  /// Whether the selection is longer than its cap.
  bool get selectionOverCap;

  /// Starts a selection at [row] (mouse down in the gutter).
  void startSelection(int row);

  /// Shift+click on [row].
  void shiftClick(int row);

  /// Moves the selection's focus to [row] (drag).
  void extendSelection(int row);

  /// Moves the focus [step] visible rows and scrolls it into view (Shift+↑
  /// or Shift+↓). Returns false when nothing is selected.
  bool stepSelection(int step);

  /// Clears the selection.
  void clearSelection();

  /// Copies the selection; see [DiffViewController.copySelection].
  Future<String?> copySelection();

  /// Reports a painted selection overlay to the controller's probe.
  void didPaintSelection();

  /// The side and model line that [row] shows.
  (PaneSide, int) lineOfRow(int row);

  /// A text selection in this column.
  CodeSelection textSelection(CodePosition anchor, CodePosition focus);

  /// The text selection when it is in this column, or null.
  CodeSelection? get ownTextSelection {
    final sel = controller.textSelection.value;
    if (sel == null) return null;
    return sel.side == (unified == null ? side : null) ? sel : null;
  }
}

/// One pane of a side-by-side view.
final class SidePaneModel extends PaneModel {
  /// Creates the model of [side]'s pane.
  const new(super.controller, this.side);

  @override
  final PaneSide side;

  DiffViewController get _c => controller;

  @override
  UnifiedRows? get unified => null;

  @override
  PaneGeometry get geometry => _c.geometry(side);

  @override
  ScrollController get scroll => _c.scroll(side);

  @override
  GutterMetrics get gutter => _c.resources.gutter;

  @override
  void makeMaster() => _c.master = side;

  @override
  int foldRegionAtSlot(int slot) => _c.foldRegionAtSlot(side, slot);

  @override
  int? inlaySlot(InlaySpec spec) => spec.side == side ? spec.slot : null;

  @override
  ({int anchor, int focus})? get selection {
    final sel = _c.selection.value;
    return sel == null ? null : (anchor: sel.anchor, focus: sel.focus);
  }

  @override
  ModelSpan? get selectedRows {
    final sel = _c.selection.value;
    return sel != null && sel.side == side ? sel.span : null;
  }

  @override
  bool get selectionOverCap => _c.selection.isOverCap;

  @override
  void startSelection(int row) => _c.selection.start(side, row);

  @override
  void shiftClick(int row) => _c.selection.shiftClick(side, row);

  @override
  void extendSelection(int row) => _c.selection.extendTo(row);

  @override
  bool stepSelection(int step) {
    final sel = _c.selection.value;
    if (sel == null) return false;
    final focus = _c.geometry(sel.side).stepVisible(sel.focus, step);
    _c.selection.extendTo(focus);
    _c.ensureLineVisible(sel.side, focus);
    return true;
  }

  @override
  void clearSelection() => _c.selection.clear();

  @override
  Future<String?> copySelection() => _c.copySelection();

  @override
  void didPaintSelection() =>
      _c.onSelectionPaint?.call(side, _c.selection.value);

  @override
  (PaneSide, int) lineOfRow(int row) => (side, row);

  @override
  CodeSelection textSelection(CodePosition anchor, CodePosition focus) =>
      CodeSelection(side: side, anchor: anchor, focus: focus);

  @override
  bool operator ==(Object other) =>
      other is SidePaneModel &&
      other.controller == controller &&
      other.side == side;

  @override
  int get hashCode => Object.hash(controller, side);
}

/// The column of a unified view.
final class UnifiedPaneModel extends PaneModel {
  /// Creates the model of [controller]'s unified column.
  const new(super.controller);

  DiffViewController get _c => controller;

  @override
  PaneSide get side => PaneSide.neu;

  @override
  UnifiedRows get unified => _c.unifiedRows;

  @override
  PaneGeometry get geometry => _c.unifiedGeometry;

  @override
  ScrollController get scroll => _c.unifiedScroll;

  @override
  GutterMetrics get gutter => _c.resources.unifiedGutter;

  @override
  void makeMaster() {}

  @override
  int foldRegionAtSlot(int slot) => _c.unifiedFoldRegionAtSlot(slot);

  @override
  int? inlaySlot(InlaySpec spec) => _c.unifiedSlotOf(spec);

  @override
  ({int anchor, int focus})? get selection {
    final sel = _c.unifiedSelection.value;
    return sel == null ? null : (anchor: sel.anchor, focus: sel.focus);
  }

  @override
  ModelSpan? get selectedRows => _c.unifiedSelection.value?.span;

  @override
  bool get selectionOverCap => _c.unifiedSelection.isOverCap;

  @override
  void startSelection(int row) => _c.unifiedSelection.start(row);

  @override
  void shiftClick(int row) => _c.unifiedSelection.shiftClick(row);

  @override
  void extendSelection(int row) => _c.unifiedSelection.extendTo(row);

  @override
  bool stepSelection(int step) {
    final sel = _c.unifiedSelection.value;
    if (sel == null) return false;
    final focus = geometry.stepVisible(sel.focus, step);
    _c.unifiedSelection.extendTo(focus);
    _c.ensureUnifiedRowVisible(focus);
    return true;
  }

  @override
  void clearSelection() => _c.unifiedSelection.clear();

  @override
  Future<String?> copySelection() => _c.copySelection();

  @override
  void didPaintSelection() {}

  @override
  (PaneSide, int) lineOfRow(int row) {
    final rows = unified;
    final side = rows.textSideAt(row);
    return (side, rows.lineAt(side, row));
  }

  @override
  CodeSelection textSelection(CodePosition anchor, CodePosition focus) =>
      CodeSelection.unified(anchor: anchor, focus: focus);

  @override
  bool operator ==(Object other) =>
      other is UnifiedPaneModel && other.controller == controller;

  @override
  int get hashCode => controller.hashCode;
}

/// A scrollable diff column: the [DiffPaneViewport], the selection/hover
/// overlay, gutter drag-select with autoscroll, Shift+click and Shift+↑/↓
/// extension, text selection in the code (drag, double and triple click,
/// Shift+click, with autoscroll), fold placeholder clicks, horizontal
/// scrolling and copy.
/// [DiffPane] and `UnifiedDiff` show one each.
class PaneView extends StatefulWidget {
  /// Creates the column of [model].
  const new({
    required this.model,
    required this.inlayBuilder,
    this.autoscroll = const AutoscrollSpeed(),
    this.focusNode,
    super.key,
  });

  /// What the column shows.
  final PaneModel model;

  /// Builds inlay widgets.
  final InlayBuilder inlayBuilder;

  /// Autoscroll speed of gutter drags.
  final AutoscrollSpeed autoscroll;

  /// Focus node for keyboard input; one is created if null.
  final FocusNode? focusNode;

  @override
  State<PaneView> createState() => _PaneViewState();
}

class _PaneViewState extends State<PaneView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_autoscrollTick);
  final ValueNotifier<int?> _hoverRow = ValueNotifier(null);
  final ValueNotifier<MouseCursor> _cursor = ValueNotifier(MouseCursor.defer);
  FocusNode? _ownFocus;
  _Drag _drag = _Drag.none;
  Offset _pointer = Offset.zero;
  Duration _lastTick = Duration.zero;
  // Text drags: the unit (character, word or line) the drag started on,
  // which stays selected whichever way the drag goes.
  CodePosition _unitStart = const CodePosition(0, 0);
  CodePosition _unitEnd = const CodePosition(0, 0);
  // Clicks in a row at one place: 1, 2 (word) or 3 (line).
  int _clicks = 0;
  Offset _lastClick = Offset.zero;
  Timer? _clickTimer;

  double get _pointerY => _pointer.dy;

  PaneModel get _m => widget.model;
  DiffViewController get _c => widget.model.controller;
  PaneGeometry get _geometry => _m.geometry;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ticker.dispose();
    _clickTimer?.cancel();
    _hoverRow.dispose();
    _cursor.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  ScrollPosition? get _position {
    final s = _m.scroll;
    return s.hasClients ? s.position : null;
  }

  /// The row under viewport y [y], resolving inlays, placeholders and the
  /// area past the last row to the nearest row in the drag direction.
  int _rowAt(double y, {required bool downward}) {
    final p = _position;
    final g = _geometry;
    if (p == null || g.rowCount == 0) return 0;
    final hit = g.index.hit(p.pixels + y);
    final slot = hit.slot;
    int row;
    if (slot < g.rowCount &&
        g.isRowVisible(slot) &&
        hit.dy >= g.index.extraAbove(slot)) {
      row = slot;
    } else if (downward || slot >= g.rowCount) {
      row = g.previousVisibleRow(slot - 1);
    } else {
      row = g.nextVisibleRow(slot);
    }
    return row.clamp(0, g.rowCount - 1);
  }

  bool _inGutter(Offset local) => local.dx < _m.gutter.gutterWidth;

  /// Whether viewport point [local] is on the code of a row.
  bool _onCode(Offset local) {
    final p = _position;
    final g = _geometry;
    if (p == null || _inGutter(local)) return false;
    final hit = g.index.hit(p.pixels + local.dy);
    return hit.slot < g.rowCount &&
        g.isRowVisible(hit.slot) &&
        hit.dy >= g.index.extraAbove(hit.slot);
  }

  /// Whether viewport y [y] is on an inlay.
  bool _onInlay(double y) {
    final p = _position;
    if (p == null) return false;
    final hit = _geometry.index.hit(p.pixels + y);
    return hit.dy < _geometry.shownInlayHeight(hit.slot);
  }

  DiffLine? _lineAtRow(int row) {
    final (side, line) = _m.lineOfRow(row);
    return _c.lines.lineAt(side, line);
  }

  int _lengthOfRow(int row) => _lineAtRow(row)?.text.length ?? 0;

  /// The offset at viewport x [x] in [row].
  int _columnAt(int row, double x) {
    final res = _c.resources;
    final codeX = x - _m.gutter.codeX + _c.horizontal.value;
    final (side, number) = _m.lineOfRow(row);
    final line = _c.lines.lineAt(side, number);
    if (line == null) return math.max(0, (codeX / res.advance).round());
    final layout = res.lines.getOrBuild(
      side.index | (number << 1),
      line,
      () => res.layouts.build(line),
    );
    return layout.offsetAt(codeX, res.advance);
  }

  /// The code position under viewport point [local]. Off a row (an inlay,
  /// a fold placeholder, past the last row) it is the end of the row above
  /// when [downward], else the start of the row below.
  CodePosition? _codePositionAt(Offset local, {required bool downward}) {
    final p = _position;
    final g = _geometry;
    if (p == null || g.rowCount == 0) return null;
    final hit = g.index.hit(p.pixels + local.dy);
    final slot = hit.slot;
    if (slot < g.rowCount &&
        g.isRowVisible(slot) &&
        hit.dy >= g.index.extraAbove(slot)) {
      return CodePosition(slot, _columnAt(slot, local.dx));
    }
    final above = g.previousVisibleRow(math.min(slot, g.rowCount) - 1);
    final below = slot < g.rowCount ? g.nextVisibleRow(slot) : g.rowCount;
    if ((downward || below >= g.rowCount) && above >= 0) {
      return CodePosition(above, _lengthOfRow(above));
    }
    if (below < g.rowCount) return CodePosition(below, 0);
    return null;
  }

  /// The word or line around [pos], by the click count.
  (CodePosition, CodePosition) _unitAt(CodePosition pos) {
    final row = pos.line;
    if (_clicks >= 3) {
      final next = _geometry.nextVisibleRow(row + 1);
      return (
        CodePosition(row, 0),
        next < _geometry.rowCount
            ? CodePosition(next, 0)
            : CodePosition(row, _lengthOfRow(row)),
      );
    }
    if (_clicks == 2) {
      final (s, e) = wordRangeAt(_lineAtRow(row)?.text ?? '', pos.column);
      return (CodePosition(row, s), CodePosition(row, e));
    }
    return (pos, pos);
  }

  void _countClick(Offset local) {
    final again =
        (_clickTimer?.isActive ?? false) &&
        (local - _lastClick).distance <= kDoubleTapSlop;
    _clicks = again ? math.min(_clicks + 1, 3) : 1;
    _lastClick = local;
    _clickTimer?.cancel();
    _clickTimer = Timer(kDoubleTapTimeout, () {});
  }

  void _startTextDrag(Offset local) {
    if (_onInlay(local.dy)) return;
    final pos = _codePositionAt(local, downward: true);
    if (pos == null) return;
    final current = _m.ownTextSelection;
    if (HardwareKeyboard.instance.isShiftPressed && current != null) {
      _clicks = 1;
      _clickTimer?.cancel();
      _unitStart = current.anchor;
      _unitEnd = current.anchor;
      _c.textSelection.select(_m.textSelection(current.anchor, pos));
    } else {
      _countClick(local);
      final (start, end) = _unitAt(pos);
      _unitStart = start;
      _unitEnd = end;
      // A click clears every selection; a double or triple click selects
      // its unit.
      _c.textSelection.select(_m.textSelection(start, end));
      _c.selection.clear();
      _c.unifiedSelection.clear();
    }
    _drag = _Drag.text;
    _pointer = local;
  }

  void _updateTextFocus() {
    final p = _position;
    final h = p?.viewportDimension ?? 0;
    if (p == null || h <= 0) return;
    final y = _pointerY.clamp(0.0, h - 0.01);
    final hit = _geometry.index.hit(p.pixels + y).slot;
    final downward =
        _overshoot() > 0 || (_pointerY >= 0 && hit > _unitStart.line);
    var pos = _codePositionAt(Offset(_pointer.dx, y), downward: downward);
    if (pos == null) return;
    // Past the top or bottom of the file: its first or last character.
    if (_pointerY < 0 && p.pixels <= p.minScrollExtent) {
      pos = CodePosition(pos.line, 0);
    } else if (_pointerY > h && p.pixels >= p.maxScrollExtent) {
      pos = CodePosition(pos.line, _lengthOfRow(pos.line));
    }
    final (start, end) = _unitAt(pos);
    _c.textSelection.select(
      pos.compareTo(_unitStart) < 0
          ? _m.textSelection(_unitEnd, start)
          : _m.textSelection(_unitStart, end),
    );
  }

  void _onPointerDown(PointerDownEvent e) {
    _m.makeMaster();
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryButton) {
      return;
    }
    _focus.requestFocus();
    final p = _position;
    if (p == null) return;
    final local = e.localPosition;
    final hit = _geometry.index.hit(p.pixels + local.dy);
    final placeholderTop =
        _geometry.topOfSlot(hit.slot) + _geometry.shownInlayHeight(hit.slot);
    final region = _m.foldRegionAtSlot(hit.slot);
    final y = p.pixels + local.dy;
    if (region >= 0 &&
        y >= placeholderTop &&
        y < placeholderTop + _geometry.placeholderHeight) {
      _c
        ..clearTextSelection()
        ..toggleFold(region, all: HardwareKeyboard.instance.isAltPressed);
      return;
    }
    if (!_inGutter(local)) {
      if (_c.textSelectionEnabled) _startTextDrag(local);
      return;
    }
    final row = _rowAt(local.dy, downward: true);
    if (HardwareKeyboard.instance.isShiftPressed) {
      _m.shiftClick(row);
    } else {
      _m.startSelection(row);
    }
    _drag = _Drag.lines;
    _pointer = local;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_drag == _Drag.none) return;
    _pointer = e.localPosition;
    _updateFocus();
    final overshoot = _overshoot();
    if (overshoot != 0 && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (overshoot == 0 && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (_drag == _Drag.none) return;
    _drag = _Drag.none;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onPointerHover(PointerHoverEvent e) {
    final local = e.localPosition;
    _hoverRow.value = _inGutter(local)
        ? _rowAt(local.dy, downward: true)
        : null;
    _cursor.value = _c.textSelectionEnabled && _onCode(local)
        ? SystemMouseCursors.text
        : MouseCursor.defer;
  }

  void _updateFocus() {
    if (_drag == _Drag.text) {
      _updateTextFocus();
    } else {
      _updateDragFocus();
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    _m.makeMaster();
    if (e is PointerScrollEvent && e.scrollDelta.dx != 0) {
      _c.scrollHorizontally(e.scrollDelta.dx, codeWidth: _codeWidth());
    }
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    if (e.panDelta.dx != 0) {
      _c.scrollHorizontally(-e.panDelta.dx, codeWidth: _codeWidth());
    }
  }

  double _codeWidth() {
    final box = context.findRenderObject() as RenderBox?;
    final w = box?.hasSize ?? false ? box!.size.width : 0.0;
    return math.max(0, w - _m.gutter.codeX);
  }

  double _overshoot() {
    final h = _position?.viewportDimension ?? 0;
    if (_pointerY < 0) return _pointerY;
    if (_pointerY > h) return _pointerY - h;
    return 0;
  }

  void _updateDragFocus() {
    final sel = _m.selection;
    final h = _position?.viewportDimension ?? 0;
    if (sel == null || h <= 0) return;
    final y = _pointerY.clamp(0.0, h - 0.01);
    final downward =
        _pointerY >= 0 && (_overshoot() > 0 || sel.focus >= sel.anchor);
    _m.extendSelection(_rowAt(y, downward: downward));
  }

  void _autoscrollTick(Duration elapsed) {
    final p = _position;
    if (p == null || _drag == _Drag.none) {
      _ticker.stop();
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    final v = widget.autoscroll.speedFor(_overshoot());
    if (v == 0) {
      _ticker.stop();
      return;
    }
    _m.makeMaster();
    final target = (p.pixels + v * dt).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (target != p.pixels) p.jumpTo(target);
    _updateFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // A focused descendant, such as a text field in an inlay, keeps its own
    // keys: copy and Escape there are the field's, not the code's.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final key = e.logicalKey;
    if (keys.isShiftPressed &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      return _m.stepSelection(step)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if ((keys.isMetaPressed || keys.isControlPressed) &&
        key == LogicalKeyboardKey.keyC) {
      // Without a selection the shortcut is not ours: an ancestor's copy
      // must still see it.
      if (_m.selection == null && _c.textSelection.value == null) {
        return KeyEventResult.ignored;
      }
      unawaited(_m.copySelection());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        (_m.selection != null || _c.textSelection.value != null)) {
      _m.clearSelection();
      _c.clearTextSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: (_) => _m.makeMaster(),
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: ValueListenableBuilder<MouseCursor>(
          valueListenable: _cursor,
          builder: (context, cursor, child) => MouseRegion(
            cursor: cursor,
            onExit: (_) {
              _hoverRow.value = null;
              _cursor.value = MouseCursor.defer;
            },
            child: child,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Scrollable(
                controller: _m.scroll,
                physics: const ClampingScrollPhysics(),
                scrollBehavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false, overscroll: false),
                viewportBuilder: (context, offset) => ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) => DiffPaneViewport(
                    offset: offset,
                    side: _m.side,
                    document: _c.document,
                    geometry: _geometry,
                    lines: _c.lines,
                    resources: _c.resources,
                    horizontalOffset: _c.horizontal,
                    unified: _m.unified,
                    textSelection: _c.textSelection,
                    onPaint: (side, pixels) =>
                        _c.onPanePaint?.call(side, pixels),
                    children: [
                      for (final spec in _c.inlays)
                        if (_m.inlaySlot(spec) case final slot?)
                          DiffInlaySlot(
                            key: ValueKey(spec.id),
                            slot: slot,
                            child: RepaintBoundary(
                              child: widget.inlayBuilder(context, spec),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _OverlayPainter(model: _m, hoverRow: _hoverRow),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Drag { none, lines, text }

/// Paints the line selection band and the hover '+' affordance above the
/// rows, on its own layer so pointer moves never repaint text.
class _OverlayPainter extends CustomPainter {
  new({required this.model, required this.hoverRow})
    : super(
        repaint: Listenable.merge([
          model.scroll,
          model.controller.selectionChanges,
          model.controller.geometryChanges,
          hoverRow,
        ]),
      );

  final PaneModel model;
  final ValueNotifier<int?> hoverRow;
  final Paint _selection = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final s = model.scroll;
    if (!s.hasClients) return;
    final pixels = s.position.pixels;
    final g = model.geometry;
    final res = model.controller.resources;
    final lh = g.lineHeight;
    final span = model.selectedRows;
    if (span != null) {
      final paint = _selection
        ..color = model.selectionOverCap
            ? res.theme.selectionOverCap
            : res.theme.selection;
      final first = math.max(span.start, g.index.hit(pixels).slot);
      final last = math.min(
        span.end - 1,
        g.index.hit(pixels + size.height).slot,
      );
      for (
        var r = g.nextVisibleRow(first);
        r <= last && r < g.rowCount;
        r = g.nextVisibleRow(r + 1)
      ) {
        final y = g.topOfRow(r) - pixels;
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, lh), paint);
      }
    }
    final hover = hoverRow.value;
    if (hover != null && hover < g.rowCount && g.isRowVisible(hover)) {
      final y = g.topOfRow(hover) - pixels;
      canvas.drawParagraph(
        res.hoverMarker,
        Offset(model.gutter.markerX, y + res.textTop),
      );
    }
    model.didPaintSelection();
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) => oldDelegate.model != model;
}
