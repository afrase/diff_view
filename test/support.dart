import 'dart:typed_data';

import 'package:diff_view/diff_view.dart';

/// One segment of a synthetic diff.
sealed class Seg {
  const new();
}

/// [n] unchanged lines.
final class Eq extends Seg {
  const new(this.n);
  final int n;
}

/// A modified block of [o] old and [n] new lines.
final class Mod extends Seg {
  const new(this.o, this.n);
  final int o;
  final int n;
}

/// An inserted block of [n] lines.
final class Ins extends Seg {
  const new(this.n);
  final int n;
}

/// A deleted block of [n] lines.
final class Del extends Seg {
  const new(this.n);
  final int n;
}

/// Capture names used by [SyntheticDiff]: id 1 keyword, 2 string.
const testCaptures = ['', 'keyword', 'string'];

/// A synthetic diff: the document, both sides' lines and texts.
final class SyntheticDiff {
  /// Builds a diff from [segs]. Lines look like `\tfunc o12("old 12")` so
  /// they carry a tab, a keyword and a string; modified lines get an inner
  /// highlight on their number.
  factory(List<Seg> segs) {
    final old = <DiffLine>[];
    final neu = <DiffLine>[];
    final blocks = <DiffBlock>[];
    final gaps = <DiffGap>[];
    for (final s in segs) {
      final o0 = old.length;
      final n0 = neu.length;
      switch (s) {
        case Eq(:final n):
          for (var i = 0; i < n; i++) {
            old.add(
              _line(old.length, 'same ${o0 + i}', LineKind.unchanged, -1),
            );
            neu.add(
              _line(neu.length, 'same ${o0 + i}', LineKind.unchanged, -1),
            );
          }
          gaps.add(
            DiffGap(
              index: gaps.length,
              old: ModelSpan(o0, old.length),
              neu: ModelSpan(n0, neu.length),
            ),
          );
        case Mod(:final o, :final n):
          final b = blocks.length;
          for (var i = 0; i < o; i++) {
            old.add(_line(old.length, 'old ${o0 + i}', LineKind.modified, b));
          }
          for (var i = 0; i < n; i++) {
            neu.add(_line(neu.length, 'new ${n0 + i}', LineKind.modified, b));
          }
          blocks.add(
            DiffBlock(
              index: b,
              kind: BlockKind.modified,
              old: ModelSpan(o0, old.length),
              neu: ModelSpan(n0, neu.length),
            ),
          );
        case Ins(:final n):
          final b = blocks.length;
          for (var i = 0; i < n; i++) {
            neu.add(_line(neu.length, 'add ${n0 + i}', LineKind.added, b));
          }
          blocks.add(
            DiffBlock(
              index: b,
              kind: BlockKind.inserted,
              old: ModelSpan(o0, o0),
              neu: ModelSpan(n0, neu.length),
            ),
          );
        case Del(:final n):
          final b = blocks.length;
          for (var i = 0; i < n; i++) {
            old.add(_line(old.length, 'del ${o0 + i}', LineKind.deleted, b));
          }
          blocks.add(
            DiffBlock(
              index: b,
              kind: BlockKind.deleted,
              old: ModelSpan(o0, old.length),
              neu: ModelSpan(n0, n0),
            ),
          );
      }
    }
    return SyntheticDiff._(
      DiffDocument(
        oldLineCount: old.length,
        newLineCount: neu.length,
        blocks: blocks,
        gaps: gaps,
        path: 'synthetic.go',
      ),
      old,
      neu,
    );
  }
  new _(this.document, this.old, this.neu);

  final DiffDocument document;
  final List<DiffLine> old;
  final List<DiffLine> neu;

  MemoryLineSource get source => MemoryLineSource(old: old, neu: neu);

  static DiffLine _line(int line, String body, LineKind kind, int block) {
    // "\tfunc f("<body>")": tab at 0, keyword at 1..5, string after "f(".
    final text = '\tfunc f("$body")';
    final strStart = text.indexOf('"');
    final strLen = text.length - 1 - strStart;
    final numStart = text.lastIndexOf(' ') + 1;
    final numLen = text.length - 2 - numStart;
    return DiffLine(
      line: line,
      text: text,
      kind: kind,
      block: block,
      syntax: Uint32List.fromList([1, 4, 1, strStart, strLen, 2]),
      inner: kind == LineKind.modified
          ? Uint32List.fromList([numStart, numLen, innerChanged])
          : null,
    );
  }
}
