import 'package:meta/meta.dart';
import 'package:side_by_side_diff/src/model/line_coords.dart';

/// Kind of a change block.
enum BlockKind {
  /// Lines changed on both sides.
  modified,

  /// Lines only on the new side.
  inserted,

  /// Lines only on the old side.
  deleted,
}

/// One change block: a pair of model spans, one per side.
@immutable
final class DiffBlock {
  /// Creates a block. [old] or [neu] is empty for a pure insertion or
  /// deletion.
  const new({
    required this.index,
    required this.kind,
    required this.old,
    required this.neu,
  });

  /// Position in [DiffDocument.blocks].
  final int index;

  /// Kind of change.
  final BlockKind kind;

  /// Lines on the old side (convention 1).
  final ModelSpan old;

  /// Lines on the new side (convention 1).
  final ModelSpan neu;

  /// The span on [side].
  ModelSpan span(PaneSide side) => side == PaneSide.old ? old : neu;

  @override
  String toString() => 'DiffBlock#$index(${kind.name} old $old new $neu)';
}

/// An unchanged region between blocks. Lengths are equal on
/// both sides unless whitespace policy made them differ.
@immutable
final class DiffGap {
  /// Creates a gap.
  const new({required this.index, required this.old, required this.neu});

  /// Position in [DiffDocument.gaps].
  final int index;

  /// Lines on the old side (convention 1).
  final ModelSpan old;

  /// Lines on the new side (convention 1).
  final ModelSpan neu;

  /// The span on [side].
  ModelSpan span(PaneSide side) => side == PaneSide.old ? old : neu;

  /// The gap starts the file, so no context is kept above it.
  bool get isLeading => old.start == 0 && neu.start == 0;
}

/// The header of one file diff: line counts, blocks and gaps (the parts of
/// 04 `OpenFileResponse` the painter needs). Rows are fetched separately
/// through a `DiffLineSource`.
@immutable
final class DiffDocument {
  /// Creates a document and checks its invariants: blocks and gaps are
  /// sorted, do not overlap, and stay within the line counts.
  factory({
    required int oldLineCount,
    required int newLineCount,
    required List<DiffBlock> blocks,
    required List<DiffGap> gaps,
    String path = '',
  }) {
    _checkSorted(blocks.map((b) => (b.old, b.neu)), oldLineCount, newLineCount);
    _checkSorted(gaps.map((g) => (g.old, g.neu)), oldLineCount, newLineCount);
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].index != i) {
        throw ArgumentError('block $i has index ${blocks[i].index}');
      }
    }
    for (var i = 0; i < gaps.length; i++) {
      if (gaps[i].index != i) {
        throw ArgumentError('gap $i has index ${gaps[i].index}');
      }
    }
    final pairs = <(int, int)>[
      (0, 0),
      for (final b in blocks) ...[
        (b.old.start, b.neu.start),
        (b.old.end, b.neu.end),
      ],
      (oldLineCount, newLineCount),
    ];
    return DiffDocument._(
      oldLineCount,
      newLineCount,
      List.unmodifiable(blocks),
      List.unmodifiable(gaps),
      List.unmodifiable(pairs),
      path,
    );
  }

  const new _(
    this.oldLineCount,
    this.newLineCount,
    this.blocks,
    this.gaps,
    this.syncPairs,
    this.path,
  );

  /// Lines on the old side.
  final int oldLineCount;

  /// Lines on the new side.
  final int newLineCount;

  /// Change blocks in file order.
  final List<DiffBlock> blocks;

  /// Unchanged regions in file order.
  final List<DiffGap> gaps;

  /// File path, for labels.
  final String path;

  /// Lines on [side].
  int lineCount(PaneSide side) =>
      side == PaneSide.old ? oldLineCount : newLineCount;

  /// IntelliJ's boundary pairs: `(0, 0)`, each block's starts and
  /// ends, then the line counts. Model lines, convention 1; non-decreasing
  /// on both sides.
  final List<(int, int)> syncPairs;

  /// Index of the block whose span on [side] contains [line], or -1.
  int blockAt(PaneSide side, int line) {
    var lo = 0;
    var hi = blocks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final span = blocks[mid].span(side);
      if (span.end <= line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo < blocks.length && blocks[lo].span(side).contains(line)) return lo;
    return -1;
  }

  /// Index of the first block whose span on [side] ends after [line] (or is
  /// an empty span at or after it); `blocks.length` if none.
  int firstBlockEndingAfter(PaneSide side, int line) {
    var lo = 0;
    var hi = blocks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final span = blocks[mid].span(side);
      final end = span.isEmpty ? span.start + 1 : span.end;
      if (end <= line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Maps [line] on [from] to the other side the way IntelliJ's
  /// `transferLine` does: inside a block it tracks 1:1 and then
  /// stops at the block's last line; in an equal region it keeps the offset
  /// of the last boundary pair at or before [line].
  int transferLine(int line, PaneSide from) {
    final to = from.other;
    final k = blockAt(from, line);
    if (k >= 0) {
      final b = blocks[k];
      final f = b.span(from);
      final t = b.span(to);
      final last = t.end - 1 < t.start ? t.start : t.end - 1;
      final mapped = t.start + (line - f.start);
      return mapped < last ? mapped : last;
    }
    int fromOf((int, int) p) => from == PaneSide.old ? p.$1 : p.$2;
    // Last boundary pair whose `from` line is at or before [line].
    var lo = 0;
    var hi = syncPairs.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (fromOf(syncPairs[mid]) <= line) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final p = syncPairs[lo == 0 ? 0 : lo - 1];
    final pTo = from == PaneSide.old ? p.$2 : p.$1;
    return pTo + (line - fromOf(p));
  }

  static void _checkSorted(
    Iterable<(ModelSpan, ModelSpan)> spans,
    int oldLines,
    int newLines,
  ) {
    var oldEnd = 0;
    var newEnd = 0;
    for (final (o, n) in spans) {
      if (o.start < oldEnd || n.start < newEnd) {
        throw ArgumentError('spans overlap or are unsorted at old $o new $n');
      }
      if (o.end > oldLines || n.end > newLines) {
        throw ArgumentError('span old $o new $n exceeds the line counts');
      }
      oldEnd = o.end;
      newEnd = n.end;
    }
  }
}
