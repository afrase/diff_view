import 'dart:typed_data';

import 'package:diff_view/src/diff/myers.dart';
import 'package:diff_view/src/model/diff_document.dart';
import 'package:diff_view/src/model/diff_line.dart';
import 'package:diff_view/src/model/line_coords.dart';
import 'package:diff_view/src/model/line_source.dart';
import 'package:meta/meta.dart';

/// Returns syntax spans for one line: `(start, length, captureId)` triples
/// in UTF-16 code units, sorted and non-overlapping, where `captureId`
/// indexes the controller's `captureNames`. Return null for none.
typedef SyntaxSpans = Uint32List? Function(PaneSide side, String line);

/// A line diff of two texts, with word highlights inside changed lines,
/// ready for a `DiffViewController`.
///
/// Lines are compared exactly (no whitespace policy). Changed lines are
/// paired in order inside each modified block, and each pair gets a word
/// diff.
@immutable
final class TextDiff {
  /// Diffs [oldText] against [newText]. [syntax] adds syntax highlighting.
  factory compute(
    String oldText,
    String newText, {
    String path = '',
    SyntaxSpans? syntax,
  }) {
    final (oldLines, oldEnds) = _split(oldText);
    final (newLines, newEnds) = _split(newText);
    final ids = <String, int>{};
    int id(String s) => ids.putIfAbsent(s, () => ids.length);
    final ops = myersDiff(
      [for (final l in oldLines) id(l)],
      [for (final l in newLines) id(l)],
    );

    final blocks = <DiffBlock>[];
    final gaps = <DiffGap>[];
    final oldKind = List.filled(oldLines.length, LineKind.unchanged);
    final newKind = List.filled(newLines.length, LineKind.unchanged);
    final oldBlock = List.filled(oldLines.length, -1);
    final newBlock = List.filled(newLines.length, -1);
    var o = 0;
    var n = 0;
    var i = 0;
    while (i < ops.length) {
      final o0 = o;
      final n0 = n;
      if (ops[i] == EditOp.equal) {
        while (i < ops.length && ops[i] == EditOp.equal) {
          o++;
          n++;
          i++;
        }
        gaps.add(
          DiffGap(
            index: gaps.length,
            old: ModelSpan(o0, o),
            neu: ModelSpan(n0, n),
          ),
        );
        continue;
      }
      while (i < ops.length && ops[i] != EditOp.equal) {
        if (ops[i] == EditOp.delete) {
          o++;
        } else {
          n++;
        }
        i++;
      }
      final kind = o == o0
          ? BlockKind.inserted
          : n == n0
          ? BlockKind.deleted
          : BlockKind.modified;
      final b = blocks.length;
      blocks.add(
        DiffBlock(
          index: b,
          kind: kind,
          old: ModelSpan(o0, o),
          neu: ModelSpan(n0, n),
        ),
      );
      final lineKind = switch (kind) {
        BlockKind.inserted => LineKind.added,
        BlockKind.deleted => LineKind.deleted,
        BlockKind.modified => LineKind.modified,
      };
      for (var k = o0; k < o; k++) {
        oldKind[k] = lineKind;
        oldBlock[k] = b;
      }
      for (var k = n0; k < n; k++) {
        newKind[k] = lineKind;
        newBlock[k] = b;
      }
    }

    final oldInner = List<Uint32List?>.filled(oldLines.length, null);
    final newInner = List<Uint32List?>.filled(newLines.length, null);
    for (final b in blocks) {
      if (b.kind != BlockKind.modified) continue;
      final pairs = b.old.end - b.old.start < b.neu.end - b.neu.start
          ? b.old.end - b.old.start
          : b.neu.end - b.neu.start;
      for (var k = 0; k < pairs; k++) {
        final (oi, ni) = _wordDiff(
          oldLines[b.old.start + k],
          newLines[b.neu.start + k],
        );
        oldInner[b.old.start + k] = oi;
        newInner[b.neu.start + k] = ni;
      }
    }

    List<DiffLine> build(
      PaneSide side,
      List<String> lines,
      List<LineEnding> ends,
      List<LineKind> kinds,
      List<int> blockOf,
      List<Uint32List?> inner,
    ) => [
      for (var k = 0; k < lines.length; k++)
        DiffLine(
          line: k,
          text: lines[k],
          kind: kinds[k],
          block: blockOf[k],
          ending: ends[k],
          inner: inner[k],
          syntax: syntax?.call(side, lines[k]),
        ),
    ];

    return TextDiff._(
      DiffDocument(
        oldLineCount: oldLines.length,
        newLineCount: newLines.length,
        blocks: blocks,
        gaps: gaps,
        path: path,
      ),
      MemoryLineSource(
        old: build(
          PaneSide.old,
          oldLines,
          oldEnds,
          oldKind,
          oldBlock,
          oldInner,
        ),
        neu: build(
          PaneSide.neu,
          newLines,
          newEnds,
          newKind,
          newBlock,
          newInner,
        ),
      ),
    );
  }

  const new _(this.document, this.lines);

  /// Blocks, gaps and line counts.
  final DiffDocument document;

  /// Both sides' lines.
  final MemoryLineSource lines;
}

/// Splits [text] into lines and their terminators. A final line without a
/// terminator gets [LineEnding.none]; an empty text has no lines.
(List<String>, List<LineEnding>) _split(String text) {
  final lines = <String>[];
  final ends = <LineEnding>[];
  var start = 0;
  while (start < text.length) {
    final nl = text.indexOf('\n', start);
    if (nl < 0) {
      lines.add(text.substring(start));
      ends.add(LineEnding.none);
      break;
    }
    final crlf = nl > start && text.codeUnitAt(nl - 1) == 0x0D;
    lines.add(text.substring(start, crlf ? nl - 1 : nl));
    ends.add(crlf ? LineEnding.crlf : LineEnding.lf);
    start = nl + 1;
  }
  return (lines, ends);
}

final RegExp _token = RegExp(r'\w+|\s+|[^\w\s]', unicode: true);

/// Word diff of two lines: the changed spans of each as inner triples, or
/// null for a side whose text is all changed or not changed at all (the
/// line's own background says enough).
(Uint32List?, Uint32List?) _wordDiff(String a, String b) {
  final ta = _token.allMatches(a).toList();
  final tb = _token.allMatches(b).toList();
  final ids = <String, int>{};
  int id(Match m) => ids.putIfAbsent(m[0]!, () => ids.length);
  final ops = myersDiff(
    [for (final m in ta) id(m)],
    [for (final m in tb) id(m)],
  );
  final ca = <int>[];
  final cb = <int>[];
  var i = 0;
  var j = 0;
  for (final op in ops) {
    switch (op) {
      case EditOp.equal:
        i++;
        j++;
      case EditOp.delete:
        _addSpan(ca, ta[i].start, ta[i].end);
        i++;
      case EditOp.insert:
        _addSpan(cb, tb[j].start, tb[j].end);
        j++;
    }
  }
  return (_triples(ca, a.length), _triples(cb, b.length));
}

/// Appends `[start, end)` to [spans] (flat start/end pairs), merging it
/// with the previous span when they touch.
void _addSpan(List<int> spans, int start, int end) {
  if (spans.isNotEmpty && spans.last == start) {
    spans.last = end;
  } else {
    spans
      ..add(start)
      ..add(end);
  }
}

Uint32List? _triples(List<int> spans, int length) {
  if (spans.isEmpty) return null;
  if (spans.length == 2 && spans[0] == 0 && spans[1] == length) return null;
  final out = Uint32List(spans.length ~/ 2 * 3);
  for (var k = 0; k < spans.length ~/ 2; k++) {
    out[k * 3] = spans[k * 2];
    out[k * 3 + 1] = spans[k * 2 + 1] - spans[k * 2];
    out[k * 3 + 2] = innerChanged;
  }
  return out;
}
