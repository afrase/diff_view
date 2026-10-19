import 'dart:async';
import 'dart:math' as math;

import 'package:diff_view/src/model/inlays.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/pane_geometry.dart';
import 'package:diff_view/src/render/render_diff_pane.dart';
import 'package:diff_view/src/widgets/diff_view_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Builds the widget of an inlay.
typedef InlayBuilder = Widget Function(BuildContext context, InlaySpec spec);

/// Autoscroll speed while a gutter drag is past the viewport edge: a base
/// speed plus a gain per pixel of overshoot, capped.
@immutable
final class AutoscrollSpeed {
  /// Creates the speed curve.
  const new({this.base = 300, this.gainPerPixel = 20, this.max = 4000});

  /// Speed at the edge, px/s.
  final double base;

  /// Added speed per pixel past the edge, px/s.
  final double gainPerPixel;

  /// Cap, px/s.
  final double max;

  /// Signed speed for [overshoot] px past the edge (negative: above).
  double speedFor(double overshoot) {
    if (overshoot == 0) return 0;
    final v = math.min(max, base + overshoot.abs() * gainPerPixel);
    return overshoot.sign * v;
  }
}

/// One pane of a side-by-side diff: the scrollable [DiffPaneViewport], the
/// selection/hover overlay, gutter drag-select with autoscroll, Shift+click
/// and Shift+↑/↓ extension, fold placeholder clicks, horizontal scrolling
/// and copy.
class DiffPane extends StatefulWidget {
  /// Creates the pane of [side].
  const new({
    required this.controller,
    required this.side,
    required this.inlayBuilder,
    this.autoscroll = const AutoscrollSpeed(),
    this.focusNode,
    super.key,
  });

  /// The file view.
  final DiffViewController controller;

  /// Which pane.
  final PaneSide side;

  /// Builds inlay widgets.
  final InlayBuilder inlayBuilder;

  /// Autoscroll speed of gutter drags.
  final AutoscrollSpeed autoscroll;

  /// Focus node for keyboard input; one is created if null.
  final FocusNode? focusNode;

  @override
  State<DiffPane> createState() => _DiffPaneState();
}

class _DiffPaneState extends State<DiffPane>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_autoscrollTick);
  final ValueNotifier<int?> _hoverRow = ValueNotifier(null);
  FocusNode? _ownFocus;
  bool _dragging = false;
  double _pointerY = 0;
  Duration _lastTick = Duration.zero;

  DiffViewController get _c => widget.controller;
  PaneSide get _side => widget.side;
  PaneGeometry get _geometry => _c.geometry(_side);
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void dispose() {
    _ticker.dispose();
    _hoverRow.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  ScrollPosition? get _position {
    final s = _c.scroll(_side);
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

  bool _inGutter(Offset local) => local.dx < _c.resources.gutter.gutterWidth;

  void _onPointerDown(PointerDownEvent e) {
    _c.master = _side;
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
    final region = _c.foldRegionAtSlot(_side, hit.slot);
    final y = p.pixels + local.dy;
    if (region >= 0 &&
        y >= placeholderTop &&
        y < placeholderTop + _geometry.placeholderHeight) {
      _c.toggleFold(region, all: HardwareKeyboard.instance.isAltPressed);
      return;
    }
    if (!_inGutter(local)) return;
    final row = _rowAt(local.dy, downward: true);
    if (HardwareKeyboard.instance.isShiftPressed) {
      _c.selection.shiftClick(_side, row);
    } else {
      _c.selection.start(_side, row);
    }
    _dragging = true;
    _pointerY = local.dy;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_dragging) return;
    _pointerY = e.localPosition.dy;
    _updateDragFocus();
    final overshoot = _overshoot();
    if (overshoot != 0 && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (overshoot == 0 && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onPointerUp(PointerEvent e) {
    if (!_dragging) return;
    _dragging = false;
    if (_ticker.isActive) _ticker.stop();
  }

  void _onPointerHover(PointerHoverEvent e) {
    _hoverRow.value = _inGutter(e.localPosition)
        ? _rowAt(e.localPosition.dy, downward: true)
        : null;
  }

  void _onPointerSignal(PointerSignalEvent e) {
    _c.master = _side;
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
    return math.max(0, w - _c.resources.gutter.codeX);
  }

  double _overshoot() {
    final h = _position?.viewportDimension ?? 0;
    if (_pointerY < 0) return _pointerY;
    if (_pointerY > h) return _pointerY - h;
    return 0;
  }

  void _updateDragFocus() {
    final sel = _c.selection.value;
    final h = _position?.viewportDimension ?? 0;
    if (sel == null || h <= 0) return;
    final y = _pointerY.clamp(0.0, h - 0.01);
    final downward =
        _pointerY >= 0 && (_overshoot() > 0 || sel.focus >= sel.anchor);
    _c.selection.extendTo(_rowAt(y, downward: downward));
  }

  void _autoscrollTick(Duration elapsed) {
    final p = _position;
    if (p == null || !_dragging) {
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
    _c.master = _side;
    final target = (p.pixels + v * dt).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (target != p.pixels) p.jumpTo(target);
    _updateDragFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    final key = e.logicalKey;
    if (keys.isShiftPressed &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      final sel = _c.selection.value;
      if (sel == null) return KeyEventResult.ignored;
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      final focus = _c.geometry(sel.side).stepVisible(sel.focus, step);
      _c.selection.extendTo(focus);
      _c.ensureLineVisible(sel.side, focus);
      return KeyEventResult.handled;
    }
    if ((keys.isMetaPressed || keys.isControlPressed) &&
        key == LogicalKeyboardKey.keyC) {
      // Without a line selection the shortcut is not ours: an ancestor's
      // copy (a code-area text selection) must still see it.
      if (_c.selection.value == null) return KeyEventResult.ignored;
      unawaited(_c.copySelection());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _c.selection.value != null) {
      _c.selection.clear();
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
        onPointerPanZoomStart: (_) => _c.master = _side,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: MouseRegion(
          onExit: (_) => _hoverRow.value = null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Scrollable(
                controller: _c.scroll(_side),
                physics: const ClampingScrollPhysics(),
                scrollBehavior: ScrollConfiguration.of(context)
                    .copyWith(scrollbars: false, overscroll: false),
                viewportBuilder: (context, offset) => ListenableBuilder(
                  listenable: _c,
                  builder: (context, _) => DiffPaneViewport(
                    offset: offset,
                    side: _side,
                    document: _c.document,
                    geometry: _geometry,
                    lines: _c.lines,
                    resources: _c.resources,
                    horizontalOffset: _c.horizontal,
                    onPaint: (side, pixels) =>
                        _c.onPanePaint?.call(side, pixels),
                    children: [
                      for (final spec in _c.inlays)
                        if (spec.side == _side)
                          DiffInlaySlot(
                            key: ValueKey(spec.id),
                            slot: spec.slot,
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
                    painter: _OverlayPainter(
                      controller: _c,
                      side: _side,
                      hoverRow: _hoverRow,
                    ),
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

/// Paints the line selection band and the hover '+' affordance above the
/// rows, on its own layer so pointer moves never repaint text.
class _OverlayPainter extends CustomPainter {
  new({required this.controller, required this.side, required this.hoverRow})
    : super(
        repaint: Listenable.merge([
          controller.scroll(side),
          controller.selectionChanges,
          controller.geometryChanges,
          hoverRow,
        ]),
      );

  final DiffViewController controller;
  final PaneSide side;
  final ValueNotifier<int?> hoverRow;
  final Paint _selection = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final c = controller;
    final s = c.scroll(side);
    final sel = c.selection.value;
    if (!s.hasClients) return;
    final pixels = s.position.pixels;
    final g = c.geometry(side);
    final res = c.resources;
    final lh = g.lineHeight;
    if (sel != null && sel.side == side) {
      final paint = _selection
        ..color = c.selection.isOverCap
            ? res.theme.selectionOverCap
            : res.theme.selection;
      final span = sel.span;
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
        Offset(res.gutter.markerX, y + res.textTop),
      );
    }
    c.onSelectionPaint?.call(side, sel);
  }

  @override
  bool shouldRepaint(_OverlayPainter oldDelegate) =>
      oldDelegate.controller != controller || oldDelegate.side != side;
}
