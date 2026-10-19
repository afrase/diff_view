import 'package:diff_view/src/model/line_coords.dart';
import 'package:meta/meta.dart';

/// An inline widget between rows of one pane: a comment thread or
/// a composer. The painter places it below [afterLine]; what it shows is up
/// to the inlay builder.
@immutable
final class InlaySpec {
  /// Creates an inlay below model line [afterLine] of [side] (`-1` = above
  /// the first line).
  const new({required this.id, required this.side, required this.afterLine})
    : assert(afterLine >= -1, 'afterLine is a model line or -1');

  /// Places an inlay below the last line of [range] (below
  /// `span.end - 1`).
  factory belowRange({
    required String id,
    required PaneSide side,
    required LineRange range,
  }) => InlaySpec(
    id: id,
    side: side,
    afterLine: lineRangeToModelSpan(range).end - 1,
  );

  /// Stable identity (keys the inlay's widget).
  final String id;

  /// The pane it is drawn in.
  final PaneSide side;

  /// The model line it follows.
  final int afterLine;

  /// The geometry slot it occupies: the slot of the row after [afterLine].
  int get slot => afterLine + 1;

  @override
  bool operator ==(Object other) =>
      other is InlaySpec &&
      other.id == id &&
      other.side == side &&
      other.afterLine == afterLine;

  @override
  int get hashCode => Object.hash(id, side, afterLine);
}
