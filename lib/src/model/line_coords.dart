/// Line and column conventions of the diff viewer.
///
/// Three conventions, each with one owner:
/// 1. Diff-model ranges and lines ([ModelSpan], block and gap spans, fold
///    spans, sync pairs) are 0-based and half-open.
/// 2. Displayed line numbers are 1-based.
/// 3. Anchors and every review request use [LineRange], 1-based inclusive.
///
/// Columns are UTF-16 code units. Every `± 1` conversion between the three
/// lives in this file.
library;

import 'package:meta/meta.dart';

/// The two panes of a side-by-side diff. `new` is reserved in Dart, so the
/// new side is [neu]; it maps to the spine's `Side` `old | new`.
enum PaneSide {
  /// The left pane (the old version).
  old,

  /// The right pane (the new version).
  neu;

  /// The other side.
  PaneSide get other => this == old ? neu : old;
}

/// A 0-based, half-open range of model lines (convention 1).
@immutable
final class ModelSpan {
  /// Creates the span `[start, end)`.
  const new(this.start, this.end)
    : assert(start >= 0, 'start must not be negative'),
      assert(end >= start, 'end must not be before start');

  /// The empty span at [line].
  const new empty(int line) : this(line, line);

  /// First line in the span.
  final int start;

  /// One past the last line in the span.
  final int end;

  /// Whether the span holds no line.
  bool get isEmpty => start == end;

  /// Number of lines in the span.
  int get length => end - start;

  /// Whether [line] lies in the span.
  bool contains(int line) => line >= start && line < end;

  /// Whether the two spans share at least one line.
  bool overlaps(ModelSpan other) => start < other.end && other.start < end;

  @override
  bool operator ==(Object other) =>
      other is ModelSpan && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '[$start, $end)';
}

/// A 1-based, inclusive line range (convention 3; mirror of the spine's
/// `LineRange`).
@immutable
final class LineRange {
  /// Creates the range `start..end`, both 1-based and inclusive.
  const new(this.start, this.end)
    : assert(start >= 1, 'LineRange is 1-based'),
      assert(end >= start, 'end must not be before start');

  /// First line, 1-based.
  final int start;

  /// Last line, 1-based, inclusive.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is LineRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'L$start–$end';
}

/// Convention 2 → 1: a displayed line number (1-based, 0 = absent) to its
/// model line, or null when absent.
int? modelLineOf(int displayLine) => displayLine == 0 ? null : displayLine - 1;

/// Convention 1 → 2: a model line to the number shown in the gutter.
int displayLineOf(int modelLine) => modelLine + 1;

/// Convention 1 → 3: a non-empty selection span to the [LineRange] sent in
/// review requests. Throws [ArgumentError] on an empty span.
LineRange spanToLineRange(ModelSpan span) {
  if (span.isEmpty) throw ArgumentError.value(span, 'span', 'empty selection');
  return LineRange(span.start + 1, span.end);
}

/// Convention 3 → 1: a [LineRange] to the model span it covers.
ModelSpan lineRangeToModelSpan(LineRange range) =>
    ModelSpan(range.start - 1, range.end);
