import 'dart:math' as math;

import 'package:diff_view/src/model/inlays.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/widgets/diff_view_controller.dart';
import 'package:diff_view/src/widgets/pane_view.dart';
import 'package:flutter/widgets.dart';

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

/// One pane of a side-by-side diff: the scrollable `DiffPaneViewport`, the
/// selection/hover overlay, gutter drag-select with autoscroll, Shift+click
/// and Shift+↑/↓ extension, fold placeholder clicks, horizontal scrolling
/// and copy.
class DiffPane extends StatelessWidget {
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
  Widget build(BuildContext context) => PaneView(
    model: SidePaneModel(controller, side),
    inlayBuilder: inlayBuilder,
    autoscroll: autoscroll,
    focusNode: focusNode,
  );
}
