import 'dart:typed_data';

import 'package:diff_view/src/model/line_coords.dart';
import 'package:meta/meta.dart';

/// How a line relates to the other side.
enum LineKind {
  /// Outside every block.
  unchanged,

  /// New side of an inserted block.
  added,

  /// Old side of a deleted block.
  deleted,

  /// Either side of a modified block.
  modified,
}

/// How a line ends in its file (copying whole lines restores the
/// terminator).
enum LineEnding {
  /// `\n`.
  lf('\n'),

  /// `\r\n`.
  crlf('\r\n'),

  /// The file's last line, without a terminator ("No newline at end of
  /// file").
  none('');

  new(this.terminator);

  /// What follows the line's text in the file.
  final String terminator;
}

/// Bit in an inner span's kind that marks changed text.
const int innerChanged = 1;

/// One line of one side, decoded once per row page.
@immutable
final class DiffLine {
  /// Creates a line. [inner] and [syntax] hold `(start, length, kind)`
  /// triples in UTF-16 code units, sorted and non-overlapping.
  new({
    required this.line,
    required this.text,
    this.kind = LineKind.unchanged,
    this.block = -1,
    this.ending = LineEnding.lf,
    Uint32List? inner,
    Uint32List? syntax,
  }) : inner = inner ?? _none,
       syntax = syntax ?? _none,
       assert((inner?.length ?? 0) % 3 == 0, 'inner holds triples'),
       assert((syntax?.length ?? 0) % 3 == 0, 'syntax holds triples');

  static final Uint32List _none = Uint32List(0);

  /// Model line on its side (convention 1).
  final int line;

  /// Text without the line terminator.
  final String text;

  /// Change kind.
  final LineKind kind;

  /// Index of the block the line belongs to, or -1.
  final int block;

  /// The line's terminator in its file.
  final LineEnding ending;

  /// Inner (word/char) spans: `(start, length, kind)` triples; [innerChanged]
  /// marks changed text.
  final Uint32List inner;

  /// Syntax spans: `(start, length, captureId)` triples.
  final Uint32List syntax;

  /// The line number shown in the gutter (convention 2).
  int get displayLine => displayLineOf(line);

  /// Whether [other] lays out the same: same text and syntax spans. The
  /// painter's paragraph cache keeps a layout only while this holds for
  /// the line it was built from (tokens that arrive later, or a re-fetched
  /// row, give a different line).
  bool sameLayoutAs(DiffLine other) {
    if (identical(this, other)) return true;
    if (text != other.text) return false;
    final a = syntax;
    final b = other.syntax;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
