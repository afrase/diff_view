import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:side_by_side_diff/src/model/diff_document.dart';
import 'package:side_by_side_diff/src/model/line_coords.dart';
import 'package:side_by_side_diff/src/model/pane_geometry.dart';
import 'package:side_by_side_diff/src/render/diff_theme.dart';

/// The y extent of one block on one pane, in viewport coordinates.
typedef RibbonEdge = ({double top, double bottom});

/// Paints the divider between the panes: one curved band per change block
/// joining its rows on both sides (IntelliJ's divider).
class RibbonPainter extends CustomPainter {
  /// Creates the painter. [oldPixels] and [newPixels] read each pane's
  /// scroll offset (null while the pane is not laid out); [repaint] fires
  /// when either pane scrolls or its geometry changes.
  new({
    required this.document,
    required this.oldGeometry,
    required this.newGeometry,
    required this.oldPixels,
    required this.newPixels,
    required this.theme,
    super.repaint,
  });

  /// The file's header.
  final DiffDocument document;

  /// Old pane geometry.
  final PaneGeometry oldGeometry;

  /// New pane geometry.
  final PaneGeometry newGeometry;

  /// Old pane scroll offset.
  final double? Function() oldPixels;

  /// New pane scroll offset.
  final double? Function() newPixels;

  /// Colors.
  final DiffThemeData theme;

  /// The extent of [block] on [side]'s pane scrolled to [pixels]. An empty
  /// side becomes a 1 px line at the boundary where the other side's lines
  /// would go.
  static RibbonEdge edge(
    DiffBlock block,
    PaneSide side,
    PaneGeometry g,
    double pixels,
  ) {
    final span = block.span(side);
    if (span.isEmpty) {
      final y = g.topOfSlot(span.start) - pixels;
      return (top: y - 0.5, bottom: y + 0.5);
    }
    return (
      top: g.topOfRow(span.start) - pixels,
      bottom: g.topOfRow(span.end - 1) + g.lineHeight - pixels,
    );
  }

  /// The band's outline from [left] (old) to [right] (new) across [width]:
  /// cubic curves as in IntelliJ's `DiffDividerDrawUtil`.
  static Path band(RibbonEdge left, RibbonEdge right, double width) =>
      _bandInto(Path(), left, right, width);

  static Path _bandInto(
    Path path,
    RibbonEdge left,
    RibbonEdge right,
    double w,
  ) => path
    ..reset()
    ..moveTo(0, left.top)
    ..cubicTo(0.3 * w, left.top, 0.7 * w, right.top, w, right.top)
    ..lineTo(w, right.bottom)
    ..cubicTo(0.7 * w, right.bottom, 0.3 * w, left.bottom, 0, left.bottom)
    ..close();

  // One edge curve from the old side's y [l] to the new side's y [r].
  static Path _edgeInto(Path path, double l, double r, double w) => path
    ..reset()
    ..moveTo(0, l)
    ..cubicTo(0.3 * w, l, 0.7 * w, r, w, r);

  // Reused by every paint; colours are set per use.
  final Paint _background = Paint();
  final Paint _fill = Paint()..isAntiAlias = true;
  final Paint _border = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..isAntiAlias = true;
  // Paths reused by every block of every paint (reset before each use).
  final Path _bandPath = Path();
  final Path _topPath = Path();
  final Path _bottomPath = Path();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      _background..color = theme.dividerBackground,
    );
    final op = oldPixels();
    final np = newPixels();
    if (op == null || np == null || document.blocks.isEmpty) return;
    final firstOld = oldGeometry.index.hit(op).slot;
    final lastOld = oldGeometry.index.hit(op + size.height).slot;
    final firstNew = newGeometry.index.hit(np).slot;
    final lastNew = newGeometry.index.hit(np + size.height).slot;
    final start = math.min(
      document.firstBlockEndingAfter(PaneSide.old, firstOld),
      document.firstBlockEndingAfter(PaneSide.neu, firstNew),
    );
    final fill = _fill;
    final borderColor = theme.ribbonBorder;
    final border = borderColor == null ? null : (_border..color = borderColor);
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (var i = start; i < document.blocks.length; i++) {
      final b = document.blocks[i];
      if (b.old.start > lastOld && b.neu.start > lastNew) break;
      final l = edge(b, PaneSide.old, oldGeometry, op);
      final r = edge(b, PaneSide.neu, newGeometry, np);
      if (l.bottom < 0 && r.bottom < 0) continue;
      if (l.top > size.height && r.top > size.height) continue;
      fill.color = switch (b.kind) {
        BlockKind.modified => theme.ribbonModified,
        BlockKind.inserted => theme.ribbonInserted,
        BlockKind.deleted => theme.ribbonDeleted,
      };
      final w = size.width;
      canvas.drawPath(_bandInto(_bandPath, l, r, w), fill);
      if (border != null) {
        canvas
          ..drawPath(_edgeInto(_topPath, l.top, r.top, w), border)
          ..drawPath(_edgeInto(_bottomPath, l.bottom, r.bottom, w), border);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RibbonPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.oldGeometry != oldGeometry ||
      oldDelegate.newGeometry != newGeometry ||
      oldDelegate.theme != theme;
}
