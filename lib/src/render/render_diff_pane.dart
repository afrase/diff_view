import 'dart:math' as math;

import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/diff_line.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/line_source.dart';
import 'package:diff_view/src/model/pane_geometry.dart';
import 'package:diff_view/src/render/paint_resources.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Called after a pane painted, with its scroll offset (tests and probes).
typedef PanePaintObserver = void Function(PaneSide side, double pixels);

/// Parent data of an inlay child: the slot it sits in.
final class DiffInlayParentData extends ContainerBoxParentData<RenderBox> {
  /// Geometry slot (the row after the inlay's line).
  int slot = 0;

  /// Offset within the slot (inlays sharing a slot stack in child order).
  double dyInSlot = 0;
}

/// Puts an inlay widget into [slot] of a [DiffPaneViewport].
class DiffInlaySlot extends ParentDataWidget<DiffInlayParentData> {
  /// Creates the slot wrapper.
  const new({required this.slot, required super.child, super.key});

  /// Geometry slot.
  final int slot;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as DiffInlayParentData;
    if (data.slot != slot) {
      data.slot = slot;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => DiffPaneViewport;
}

/// The viewport of one diff pane: paints every visible row itself
/// and hosts inlay widgets as children. Used as a `Scrollable`'s viewport.
class DiffPaneViewport extends MultiChildRenderObjectWidget {
  /// Creates the viewport. [children] are inlays wrapped in [DiffInlaySlot].
  const new({
    required this.offset,
    required this.side,
    required this.document,
    required this.geometry,
    required this.lines,
    required this.resources,
    required this.horizontalOffset,
    this.anchorFraction = 1 / 3,
    this.onPaint,
    super.children,
    super.key,
  });

  /// Vertical scroll offset.
  final ViewportOffset offset;

  /// The pane's side.
  final PaneSide side;

  /// The file's header.
  final DiffDocument document;

  /// Vertical layout of the pane.
  final PaneGeometry geometry;

  /// Row source.
  final DiffLineSource lines;

  /// Shared paint resources.
  final DiffPaintResources resources;

  /// Horizontal scroll offset of the code (shared by both panes).
  final ValueListenable<double> horizontalOffset;

  /// Where the scroll anchor sits, as a fraction of the viewport height.
  final double anchorFraction;

  /// Paint probe.
  final PanePaintObserver? onPaint;

  @override
  RenderDiffPane createRenderObject(BuildContext context) => RenderDiffPane(
    offset: offset,
    side: side,
    document: document,
    geometry: geometry,
    lines: lines,
    resources: resources,
    horizontalOffset: horizontalOffset,
    anchorFraction: anchorFraction,
    onPaint: onPaint,
  );

  @override
  void updateRenderObject(BuildContext context, RenderDiffPane renderObject) {
    renderObject
      ..offset = offset
      ..side = side
      ..document = document
      ..geometry = geometry
      ..lines = lines
      ..resources = resources
      ..horizontalOffset = horizontalOffset
      ..anchorFraction = anchorFraction
      ..onPaint = onPaint;
  }
}

/// Render object of [DiffPaneViewport].
///
/// Layout keeps an anchor still: before the pane's geometry
/// changes (an inlay inserted, measured or removed, a fold toggled), what
/// is drawn at [anchorFraction] of the viewport (or the geometry's anchor
/// hint) is recorded, and layout corrects the scroll offset by how far it
/// moved, in the same frame. What is under the point is held still: a row,
/// a fold placeholder or one inlay of a slot (with the inlays after it, the
/// placeholder and the row as fallbacks, in that order, when the change
/// removes it), so a height change anywhere above it is compensated, also
/// one earlier in the same slot.
///
/// Scrolling only repaints. Paint draws, per visible row, its change tint,
/// inner (word) highlights and cached paragraph, then the gutter, the fold
/// placeholders and the inlay children.
class RenderDiffPane extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, DiffInlayParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, DiffInlayParentData> {
  /// Creates the render object.
  new({
    required this._offset,
    required this._side,
    required this._document,
    required this._geometry,
    required this._lines,
    required this._resources,
    required ValueListenable<double> horizontalOffset,
    this.anchorFraction = 1 / 3,
    this.onPaint,
  }) : _horizontal = horizontalOffset;

  ViewportOffset _offset;
  PaneSide _side;
  DiffDocument _document;
  PaneGeometry _geometry;
  DiffLineSource _lines;
  DiffPaintResources _resources;
  ValueListenable<double> _horizontal;

  /// Paint probe.
  PanePaintObserver? onPaint;

  // What the anchor holds still, best first; the first target still drawn
  // after the change counts. Null when nothing is recorded.
  List<_AnchorTarget>? _anchor;
  int _anchorEpoch = 0;
  // The inlays as the last layout placed them, taken before a layout
  // re-measures them (the anchor is recorded against the old placement).
  List<_Placement> _placed = const [];
  bool _inLayout = false;

  // Paint objects reused by every frame (their colour is set per use).
  final Paint _fill = Paint();
  final Paint _tint = Paint();
  final Paint _word = Paint();

  /// Vertical scroll offset.
  ViewportOffset get offset => _offset;
  set offset(ViewportOffset value) {
    if (identical(value, _offset)) return;
    if (attached) _offset.removeListener(markNeedsPaint);
    _offset = value;
    if (attached) _offset.addListener(markNeedsPaint);
    markNeedsLayout();
  }

  /// The pane's side.
  PaneSide get side => _side;
  set side(PaneSide value) {
    if (value == _side) return;
    _side = value;
    markNeedsPaint();
  }

  /// The file's header.
  DiffDocument get document => _document;
  set document(DiffDocument value) {
    if (identical(value, _document)) return;
    _document = value;
    markNeedsPaint();
  }

  /// Vertical layout.
  PaneGeometry get geometry => _geometry;
  set geometry(PaneGeometry value) {
    if (identical(value, _geometry)) return;
    if (attached) _detachGeometry();
    _geometry = value;
    _anchor = null;
    if (attached) _attachGeometry();
    markNeedsLayout();
  }

  /// Row source.
  DiffLineSource get lines => _lines;
  set lines(DiffLineSource value) {
    if (identical(value, _lines)) return;
    if (attached) _lines.removeListener(markNeedsPaint);
    _lines = value;
    if (attached) _lines.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// Paint resources.
  DiffPaintResources get resources => _resources;
  set resources(DiffPaintResources value) {
    if (identical(value, _resources)) return;
    _resources = value;
    markNeedsLayout();
  }

  /// Horizontal code offset.
  ValueListenable<double> get horizontalOffset => _horizontal;
  set horizontalOffset(ValueListenable<double> value) {
    if (identical(value, _horizontal)) return;
    if (attached) _horizontal.removeListener(markNeedsPaint);
    _horizontal = value;
    if (attached) _horizontal.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  /// Anchor position as a fraction of the viewport height.
  double anchorFraction;

  /// Width available to inlays.
  double get inlayWidth => math.max(
    0,
    math.min(
      size.width - _resources.gutter.gutterWidth - 12,
      _resources.theme.inlayMaxWidth,
    ),
  );

  @override
  bool get isRepaintBoundary => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! DiffInlayParentData) {
      child.parentData = DiffInlayParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(markNeedsPaint);
    _horizontal.addListener(markNeedsPaint);
    _lines.addListener(markNeedsPaint);
    _attachGeometry();
  }

  @override
  void detach() {
    _offset.removeListener(markNeedsPaint);
    _horizontal.removeListener(markNeedsPaint);
    _lines.removeListener(markNeedsPaint);
    _detachGeometry();
    super.detach();
  }

  void _attachGeometry() {
    _geometry
      ..onWillChange = _captureAnchor
      ..addListener(_geometryChanged);
  }

  void _detachGeometry() {
    if (_geometry.onWillChange == _captureAnchor) _geometry.onWillChange = null;
    _geometry.removeListener(_geometryChanged);
  }

  void _geometryChanged() {
    if (!_inLayout) markNeedsLayout();
  }

  /// Records the anchor against the geometry as it is now. Only
  /// the first change before a layout counts, unless the geometry dropped
  /// that anchor since ([PaneGeometry.dropAnchor]).
  void _captureAnchor() {
    if (!hasSize) return;
    if (_anchor != null && _anchorEpoch == _geometry.anchorEpoch) return;
    _anchorEpoch = _geometry.anchorEpoch;
    final hint = _geometry.takeAnchorHint();
    if (hint != null) {
      _anchor = [
        (
          kind: hint.part == AnchorPart.slotTop
              ? _AnchorKind.slotTop
              : _AnchorKind.row,
          slot: hint.slot,
          inlay: null,
          y: _geometry.anchorY(hint),
        ),
      ];
      return;
    }
    _anchor = _targetsAt(_offset.pixels + size.height * anchorFraction);
  }

  // What is drawn at content [y], with its fallbacks.
  List<_AnchorTarget> _targetsAt(double y) {
    final g = _geometry;
    final hit = g.index.hit(y);
    final slot = hit.slot;
    final top = g.topOfSlot(slot);
    final targets = <_AnchorTarget>[];
    final onRow =
        slot < g.rowCount &&
        g.isRowVisible(slot) &&
        hit.dy >= g.index.extraAbove(slot);
    if (!onRow) {
      final inlays = g.shownInlayHeight(slot);
      if (hit.dy < inlays) {
        // The inlay under the point, then the ones stacked after it.
        for (final p in _inLayout ? _placed : _placements()) {
          if (p.slot == slot && p.dy + p.height > hit.dy) {
            targets.add((
              kind: _AnchorKind.inlay,
              slot: slot,
              inlay: p.child,
              y: top + p.dy,
            ));
          }
        }
      }
      if (g.placeholderAt(slot) > 0) {
        targets.add((
          kind: _AnchorKind.placeholder,
          slot: slot,
          inlay: null,
          y: top + inlays,
        ));
      }
    }
    targets.add((
      kind: _AnchorKind.row,
      slot: slot,
      inlay: null,
      y: g.topOfRow(slot),
    ));
    return targets;
  }

  // Where each laid-out inlay is now, in child (stacking) order.
  List<_Placement> _placements() {
    final out = <_Placement>[];
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as DiffInlayParentData;
      if (child.hasSize) {
        out.add((
          child: child,
          slot: data.slot,
          dy: data.dyInSlot,
          height: child.size.height,
        ));
      }
      child = data.nextSibling;
    }
    return out;
  }

  // The content y of [t] in the geometry as it is now, or null if [t] is
  // no longer drawn.
  double? _targetY(_AnchorTarget t) {
    final g = _geometry;
    switch (t.kind) {
      case _AnchorKind.slotTop:
        return g.topOfSlot(t.slot);
      case _AnchorKind.row:
        return g.topOfRow(t.slot);
      case _AnchorKind.placeholder:
        return g.placeholderAt(t.slot) > 0
            ? g.topOfSlot(t.slot) + g.shownInlayHeight(t.slot)
            : null;
      case _AnchorKind.inlay:
        final child = t.inlay!;
        if (!identical(child.parent, this)) return null;
        final data = child.parentData! as DiffInlayParentData;
        if (data.slot != t.slot || !_inlayShown(t.slot)) return null;
        return g.topOfSlot(t.slot) + data.dyInSlot;
    }
  }

  @override
  void performLayout() {
    _inLayout = true;
    try {
      _offset.applyViewportDimension(size.height);
      _layoutInlays();
      final anchor = _anchor;
      if (anchor != null) {
        _anchor = null;
        if (_anchorEpoch == _geometry.anchorEpoch) {
          for (final t in anchor) {
            final y = _targetY(t);
            if (y == null) continue;
            final delta = y - t.y;
            if (delta.abs() > 1e-9) _offset.correctBy(delta);
            break;
          }
        }
      }
      final maxExtent = math.max(0, _geometry.contentHeight - size.height);
      for (var i = 0; i < 10; i++) {
        if (_offset.applyContentDimensions(0, maxExtent.toDouble())) break;
      }
    } finally {
      _inLayout = false;
    }
  }

  void _layoutInlays() {
    _placed = _placements();
    final heights = <int, double>{};
    final width = inlayWidth;
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as DiffInlayParentData;
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      final before = heights[data.slot] ?? 0;
      data.dyInSlot = before;
      heights[data.slot] = before + child.size.height;
      child = data.nextSibling;
    }
    _geometry.setInlayHeights(heights);
    _placed = const [];
  }

  bool _inlayShown(int slot) =>
      slot == 0 ||
      (slot - 1 < _geometry.rowCount && _geometry.isRowVisible(slot - 1));

  Offset _childOffset(RenderBox child) {
    final data = child.parentData! as DiffInlayParentData;
    return Offset(
      _resources.gutter.gutterWidth + 4,
      _geometry.topOfSlot(data.slot) + data.dyInSlot - _offset.pixels,
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as DiffInlayParentData;
      if (_inlayShown(data.slot)) {
        final hit = result.addWithPaintOffset(
          offset: _childOffset(child),
          position: position,
          hitTest: (r, transformed) => child!.hitTest(r, position: transformed),
        );
        if (hit) return true;
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final o = _childOffset(child);
    transform.translateByDouble(o.dx, o.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      _paintContents,
    );
    onPaint?.call(_side, _offset.pixels);
  }

  void _paintContents(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final res = _resources;
    final theme = res.theme;
    final g = res.gutter;
    final pixels = _offset.pixels;
    final lineHeight = _geometry.lineHeight;
    final rowCount = _geometry.rowCount;
    final h = _horizontal.value;

    canvas.drawRect(offset & size, _fill..color = theme.background);

    final first = _geometry.index.hit(pixels).slot;
    final last = _geometry.index.hit(pixels + size.height).slot;
    if (rowCount > 0) {
      final margin = math.max(1, last - first);
      _lines.prefetch(
        _side,
        ModelSpan(
          math.max(0, first - margin),
          math.min(rowCount, last + margin + 1),
        ),
      );
    }

    // Pass 1: code area (clipped right of the gutter).
    canvas
      ..save()
      ..clipRect(
        Rect.fromLTWH(
          offset.dx + g.gutterWidth,
          offset.dy,
          math.max(0, size.width - g.gutterWidth),
          size.height,
        ),
      );
    final tintPaint = _tint;
    final wordPaint = _word;
    final codeLeft = offset.dx + g.gutterWidth;
    final textX = offset.dx + g.codeX - h;
    for (
      var r = _geometry.nextVisibleRow(first);
      r <= last && r < rowCount;
      r = _geometry.nextVisibleRow(r + 1)
    ) {
      final y = offset.dy + _geometry.topOfRow(r) - pixels;
      final line = _lines.lineAt(_side, r);
      final kind = line?.kind ?? _kindFromDocument(r);
      final tint = _lineTint(kind);
      if (tint != null) {
        canvas.drawRect(
          Rect.fromLTWH(codeLeft, y, size.width - g.gutterWidth, lineHeight),
          tintPaint..color = tint,
        );
      }
      if (line == null) {
        _paintLoadingBars(canvas, textX, y);
        continue;
      }
      final layout = res.lines.getOrBuild(
        _side.index | (r << 1),
        line,
        () => res.layouts.build(line),
      );
      final inner = line.inner;
      if (inner.isNotEmpty) {
        wordPaint.color = _wordTint(kind) ?? theme.modifiedWord;
        for (var i = 0; i + 2 < inner.length; i += 3) {
          if (inner[i + 2] & innerChanged == 0) continue;
          final start = inner[i];
          final end = start + inner[i + 1];
          if (layout.isMonospaceSafe) {
            final (x0, x1) = layout.xRange(start, end, res.advance);
            _paintWord(canvas, textX + x0, textX + x1, y, wordPaint);
          } else {
            // One rect per visual run: an RTL run can split the range.
            for (final (x0, x1) in layout.xSpans(start, end, res.advance)) {
              _paintWord(canvas, textX + x0, textX + x1, y, wordPaint);
            }
          }
        }
      }
      canvas.drawParagraph(layout.paragraph, Offset(textX, y + res.textTop));
    }
    canvas
      ..restore()
      // Pass 2: gutter.
      ..drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, g.gutterWidth, size.height),
        _fill..color = theme.gutterBackground,
      );
    for (
      var r = _geometry.nextVisibleRow(first);
      r <= last && r < rowCount;
      r = _geometry.nextVisibleRow(r + 1)
    ) {
      final y = offset.dy + _geometry.topOfRow(r) - pixels;
      final kind = _lines.lineAt(_side, r)?.kind ?? _kindFromDocument(r);
      final changed = kind != LineKind.unchanged;
      if (changed) {
        // The line's tint runs through the gutter, as in JetBrains IDEs.
        canvas.drawRect(
          Rect.fromLTWH(offset.dx, y, g.gutterWidth, lineHeight),
          tintPaint..color = _lineTint(kind)!,
        );
        final glyph = res.marker(kind);
        canvas.drawParagraph(
          glyph,
          Offset(offset.dx + g.markerX, y + res.textTop),
        );
      }
      final number = res.number(displayLineOf(r), changed: changed);
      canvas.drawParagraph(
        number,
        Offset(
          offset.dx + g.numberRight - number.maxIntrinsicWidth,
          y + res.textTop,
        ),
      );
    }

    // Insertions and deletions have no lines on this side: a line across
    // the pane marks where the other side's lines go, and meets the ribbon.
    final blocks = _document.blocks;
    for (
      var i = _document.firstBlockEndingAfter(_side, first);
      i < blocks.length;
      i++
    ) {
      final span = blocks[i].span(_side);
      if (span.start > last + 1) break;
      if (!span.isEmpty) continue;
      final y = offset.dy + _geometry.topOfSlot(span.start) - pixels;
      canvas.drawRect(
        Rect.fromLTWH(offset.dx, y - 1, size.width, 2),
        tintPaint
          ..color = blocks[i].kind == BlockKind.inserted
              ? theme.ribbonInserted
              : theme.ribbonDeleted,
      );
    }
    // Fold placeholders.
    final spans = _geometry.hiddenSpans;
    for (var i = _firstSpanFrom(spans, first); i < spans.length; i++) {
      final s = spans[i];
      if (s.start > last) break;
      final y =
          offset.dy +
          _geometry.topOfSlot(s.start) +
          _geometry.shownInlayHeight(s.start) -
          pixels;
      _paintPlaceholder(
        canvas,
        Rect.fromLTWH(offset.dx, y, size.width, _geometry.placeholderHeight),
        s,
      );
    }

    // Inlays.
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as DiffInlayParentData;
      if (_inlayShown(data.slot)) {
        final o = _childOffset(child);
        if (o.dy < size.height && o.dy + child.size.height > 0) {
          context.paintChild(child, offset + o);
        }
      }
      child = data.nextSibling;
    }
  }

  void _paintWord(Canvas canvas, double x0, double x1, double y, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(x0, y + 1, x1, y + _geometry.lineHeight - 1),
        const Radius.circular(2),
      ),
      p,
    );
  }

  void _paintLoadingBars(Canvas canvas, double x, double y) {
    final res = _resources;
    final paint = _fill..color = res.theme.loadingBar;
    final barH = math.max(2, res.lineHeight * 0.35).toDouble();
    final top = y + (res.lineHeight - barH) / 2;
    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, res.advance * 12, barH),
          Radius.circular(barH / 2),
        ),
        paint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x + res.advance * 14, top, res.advance * 20, barH),
          Radius.circular(barH / 2),
        ),
        paint,
      );
  }

  void _paintPlaceholder(Canvas canvas, Rect rect, ModelSpan span) {
    final res = _resources;
    final theme = res.theme;
    canvas.drawRect(rect, _fill..color = theme.foldPlaceholderBackground);
    final label = res.foldLabel(span.length);
    canvas.drawParagraph(
      label,
      Offset(
        rect.left + res.gutter.codeX,
        rect.top + (rect.height - res.layouts.textHeight) / 2,
      ),
    );
  }

  LineKind _kindFromDocument(int row) {
    final b = _document.blockAt(_side, row);
    if (b < 0) return LineKind.unchanged;
    return switch (_document.blocks[b].kind) {
      BlockKind.modified => LineKind.modified,
      BlockKind.inserted => LineKind.added,
      BlockKind.deleted => LineKind.deleted,
    };
  }

  Color? _lineTint(LineKind kind) {
    final t = _resources.theme;
    return switch (kind) {
      LineKind.unchanged => null,
      LineKind.added => t.insertedLine,
      LineKind.deleted => t.deletedLine,
      LineKind.modified => t.modifiedLine,
    };
  }

  Color? _wordTint(LineKind kind) {
    final t = _resources.theme;
    return switch (kind) {
      LineKind.unchanged => null,
      LineKind.added => t.insertedWord,
      LineKind.deleted => t.deletedWord,
      LineKind.modified => t.modifiedWord,
    };
  }

  static int _firstSpanFrom(List<ModelSpan> spans, int slot) {
    var lo = 0;
    var hi = spans.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (spans[mid].start < slot) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(EnumProperty<PaneSide>('side', _side))
      ..add(DoubleProperty('pixels', _offset.pixels))
      ..add(DoubleProperty('contentHeight', _geometry.contentHeight));
  }
}

enum _AnchorKind { slotTop, row, placeholder, inlay }

// A thing the anchor can hold still, and its content y when recorded.
typedef _AnchorTarget = ({
  _AnchorKind kind,
  int slot,
  RenderBox? inlay,
  double y,
});

// An inlay child as a layout placed it.
typedef _Placement = ({RenderBox child, int slot, double dy, double height});
