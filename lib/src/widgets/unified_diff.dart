import 'package:diff_view/src/render/diff_theme.dart';
import 'package:diff_view/src/widgets/diff_pane.dart';
import 'package:diff_view/src/widgets/diff_view_controller.dart';
import 'package:diff_view/src/widgets/pane_view.dart';
import 'package:flutter/widgets.dart';

/// Unified diff: one column with the old and new line numbers in the
/// gutter, unchanged lines once and each block's deleted lines above its
/// inserted ones. It shares the controller's folds, inlays, theme and
/// caches with `SideBySideDiff`, so an app can switch between the two;
/// the new view opens at the line the old one showed.
class UnifiedDiff extends StatefulWidget {
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

  /// Builds inlay widgets. An inlay of either side is drawn below the row
  /// of its line.
  final InlayBuilder inlayBuilder;

  @override
  State<UnifiedDiff> createState() => _UnifiedDiffState();
}

class _UnifiedDiffState extends State<UnifiedDiff> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(UnifiedDiff oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  @override
  void deactivate() {
    widget.controller.keepPosition(unified: true);
    super.deactivate();
  }

  void _configure() => widget.controller.configure(
    theme: widget.theme,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );

  @override
  Widget build(BuildContext context) => PaneView(
    model: UnifiedPaneModel(widget.controller),
    inlayBuilder: widget.inlayBuilder,
  );
}
