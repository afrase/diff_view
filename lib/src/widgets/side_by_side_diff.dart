import 'package:flutter/widgets.dart';
import 'package:side_by_side_diff/src/model/line_coords.dart';
import 'package:side_by_side_diff/src/render/diff_theme.dart';
import 'package:side_by_side_diff/src/render/ribbon_painter.dart';
import 'package:side_by_side_diff/src/widgets/diff_pane.dart';
import 'package:side_by_side_diff/src/widgets/diff_view_controller.dart';

/// Side-by-side diff: the old pane, the ribbon divider and the new
/// pane, scrolled together through the controller's sync map.
class SideBySideDiff extends StatefulWidget {
  /// Creates the view of [controller] in [theme].
  const new({
    required this.controller,
    required this.theme,
    required this.inlayBuilder,
    super.key,
  });

  /// The file view.
  final DiffViewController controller;

  /// Colors and metrics.
  final DiffThemeData theme;

  /// Builds inlay widgets.
  final InlayBuilder inlayBuilder;

  @override
  State<SideBySideDiff> createState() => _SideBySideDiffState();
}

class _SideBySideDiffState extends State<SideBySideDiff> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(SideBySideDiff oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() => widget.controller.configure(
    theme: widget.theme,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  double? _pixels(PaneSide side) {
    final s = widget.controller.scroll(side);
    return s.hasClients && s.position.hasPixels ? s.position.pixels : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: DiffPane(
            controller: c,
            side: PaneSide.old,
            inlayBuilder: widget.inlayBuilder,
          ),
        ),
        SizedBox(
          width: widget.theme.dividerWidth,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: RibbonPainter(
                document: c.document,
                oldGeometry: c.geometry(PaneSide.old),
                newGeometry: c.geometry(PaneSide.neu),
                oldPixels: () => _pixels(PaneSide.old),
                newPixels: () => _pixels(PaneSide.neu),
                theme: widget.theme,
                repaint: Listenable.merge([
                  c.scroll(PaneSide.old),
                  c.scroll(PaneSide.neu),
                  c.geometryChanges,
                ]),
              ),
            ),
          ),
        ),
        Expanded(
          child: DiffPane(
            controller: c,
            side: PaneSide.neu,
            inlayBuilder: widget.inlayBuilder,
          ),
        ),
      ],
    );
  }
}
