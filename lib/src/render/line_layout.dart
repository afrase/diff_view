import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:diff_view/src/model/diff_line.dart';
import 'package:diff_view/src/render/diff_theme.dart';

/// A code line laid out for painting.
final class LineLayout {
  new _(this.paragraph, this._columns, this.isMonospaceSafe);

  /// The laid-out paragraph (tabs expanded).
  final ui.Paragraph paragraph;

  // Original UTF-16 offset → expanded column; null when the line has no tab.
  final Int32List? _columns;

  /// Whether every character is one advance wide (printable ASCII and
  /// Latin-1), so a column's x is `column × advance`.
  final bool isMonospaceSafe;

  // x spans measured through the paragraph (lines that are not
  // monospace-safe), by `start << 32 | end` in expanded columns, so a word
  // highlight is measured once, not on every frame.
  Map<int, List<(double, double)>>? _measured;

  /// Width of the laid-out text.
  double get width => paragraph.longestLine;

  /// The expanded column of original UTF-16 offset [offset].
  int columnOf(int offset) {
    final c = _columns;
    if (c == null) return offset;
    if (offset <= 0) return 0;
    return c[offset < c.length ? offset : c.length - 1];
  }

  /// The x extent of original UTF-16 offsets `[start, end)`: from the
  /// leftmost to the rightmost glyph of the range. In mixed-direction text
  /// the range may be drawn in pieces with other text between them; paint
  /// [xSpans] to cover only the range.
  (double, double) xRange(int start, int end, double advance) {
    if (isMonospaceSafe) {
      return (columnOf(start) * advance, columnOf(end) * advance);
    }
    final spans = xSpans(start, end, advance);
    return (spans.first.$1, spans.last.$2);
  }

  /// The x spans, left to right and disjoint, that draw original UTF-16
  /// offsets `[start, end)`: one on a monospace-safe line, one per visual
  /// run where an RTL run splits the range (bidi reordering). Measured once
  /// per range and cached.
  List<(double, double)> xSpans(int start, int end, double advance) {
    final s = columnOf(start);
    final e = columnOf(end);
    if (isMonospaceSafe) return [(s * advance, e * advance)];
    final measured = _measured ??= {};
    return measured[(s << 32) | e] ??= _measure(s, e, advance);
  }

  List<(double, double)> _measure(int s, int e, double advance) {
    final boxes = paragraph.getBoxesForRange(s, e)
      ..sort((a, b) => a.left.compareTo(b.left));
    if (boxes.isEmpty) return [(s * advance, s * advance)];
    final spans = <(double, double)>[];
    var left = boxes.first.left;
    var right = boxes.first.right;
    for (final b in boxes.skip(1)) {
      // Boxes of one visual run touch (sub-pixel gaps from rounding).
      if (b.left <= right + 0.5) {
        if (b.right > right) right = b.right;
      } else {
        spans.add((left, right));
        left = b.left;
        right = b.right;
      }
    }
    spans.add((left, right));
    return List.unmodifiable(spans);
  }

  /// Releases the paragraph.
  void dispose() => paragraph.dispose();
}

/// Builds [LineLayout]s with syntax styles from a theme and capture table.
final class LineLayoutBuilder {
  /// Creates a builder for [theme] and the capture names of the file
  /// (`captureNames[id]` names capture `id`).
  new(this.theme, List<String> captureNames)
    : _styles = theme.resolveCaptures(captureNames),
      _base = theme.baseTextStyle(),
      _paragraphStyle = theme.paragraphStyle();

  /// The theme the layouts use.
  final DiffThemeData theme;
  final List<ui.TextStyle> _styles;
  final ui.TextStyle _base;
  final ui.ParagraphStyle _paragraphStyle;
  double? _advance;
  double? _textHeight;

  /// Width of one column (measured once per font).
  double get advance => _advance ??= _measure().$1;

  /// Height of a laid-out line of text.
  double get textHeight => _textHeight ??= _measure().$2;

  (double, double) _measure() {
    const sample = 'MMMMMMMMMMMMMMMMMMMM';
    final b = ui.ParagraphBuilder(_paragraphStyle)
      ..pushStyle(_base)
      ..addText(sample);
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 1000000));
    final result = (p.maxIntrinsicWidth / sample.length, p.height);
    p.dispose();
    _advance = result.$1;
    _textHeight = result.$2;
    return result;
  }

  /// Lays out [line]: tabs expanded to the theme's tab stops, syntax spans
  /// styled by capture id, one line, no width limit.
  LineLayout build(DiffLine line) {
    final (expanded, columns) = expandTabs(line.text, theme.tabSize);
    final b = ui.ParagraphBuilder(_paragraphStyle)..pushStyle(_base);
    var cursor = 0;
    syntaxRuns(line.text.length, line.syntax, columns, (es, ee, capture) {
      if (es > cursor) b.addText(expanded.substring(cursor, es));
      if (capture < _styles.length) {
        b
          ..pushStyle(_styles[capture])
          ..addText(expanded.substring(es, ee))
          ..pop();
      } else {
        b.addText(expanded.substring(es, ee));
      }
      cursor = ee;
    });
    if (cursor < expanded.length) b.addText(expanded.substring(cursor));
    final p = b.build()..layout(const ui.ParagraphConstraints(width: 10000000));
    return LineLayout._(p, columns, _isMonospaceSafe(expanded));
  }

  // Printable ASCII and Latin-1 only. Controls (C0, DEL, C1) and the soft
  // hyphen U+00AD are excluded: the paragraph may draw them zero-width (a
  // soft hyphen is invisible mid-line), so `column × advance` would place
  // everything after them too far right. Tabs are already expanded here.
  static bool _isMonospaceSafe(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x20 || (c >= 0x7F && c <= 0x9F) || c == 0xAD || c > 0xFF) {
        return false;
      }
    }
    return true;
  }
}

/// Calls [run] with `(start, end, capture)` in expanded columns for each
/// styled span of [syntax] (`start, length, capture` triples in original
/// UTF-16 offsets of a line [length] long), in order. Spans are clamped to
/// the line; an empty one, or one that starts before the previous one ended
/// (overlap), is skipped. [columns] is the map from [expandTabs] (null: no
/// tab).
void syntaxRuns(
  int length,
  List<int> syntax,
  Int32List? columns,
  void Function(int start, int end, int capture) run,
) {
  // Overlap is judged on original offsets: expanded columns run ahead of
  // them after a tab.
  var rawEnd = 0;
  for (var i = 0; i + 2 < syntax.length; i += 3) {
    final start = syntax[i] > length ? length : syntax[i];
    final sum = syntax[i] + syntax[i + 1];
    final end = sum > length ? length : sum;
    if (start < rawEnd || end <= start) continue;
    run(
      columns == null ? start : columns[start],
      columns == null ? end : columns[end],
      syntax[i + 2],
    );
    rawEnd = end;
  }
}

/// Expands tabs to stops every [tabSize] columns. Returns the expanded text
/// and, when the text had a tab, the column of every original UTF-16 offset
/// (`text.length + 1` entries); null otherwise.
(String, Int32List?) expandTabs(String text, int tabSize) {
  if (!text.contains('\t')) return (text, null);
  final out = StringBuffer();
  final columns = Int32List(text.length + 1);
  var col = 0;
  for (var i = 0; i < text.length; i++) {
    columns[i] = col;
    final c = text.codeUnitAt(i);
    if (c == 0x09) {
      final n = tabSize - col % tabSize;
      for (var k = 0; k < n; k++) {
        out.writeCharCode(0x20);
      }
      col += n;
    } else {
      out.writeCharCode(c);
      col++;
    }
  }
  columns[text.length] = col;
  return (out.toString(), columns);
}

/// A cache of [LineLayout]s keyed by an int (side and line), disposing what
/// it evicts. Eviction approximates least
/// recently used with a second chance (CLOCK): a hit only sets the entry's
/// used bit, so the rows painted every frame cost a lookup, not a map
/// reinsert. When full, the oldest entry is evicted unless its bit is set;
/// then it is cleared and the entry moves to the back.
///
/// Each entry remembers the [DiffLine] it was built from. A lookup with a
/// line that does not lay out the same ([DiffLine.sameLayoutAs]: different
/// text or syntax, as when tokens arrive after the rows or a row is
/// fetched again) rebuilds the entry, so a stale layout is never painted.
/// The check is an identity test in the common case.
final class ParagraphCache {
  /// Creates a cache of at most [maxEntries] layouts.
  new({this.maxEntries = 6000})
    : assert(maxEntries > 0, 'maxEntries must be positive');

  /// Capacity.
  final int maxEntries;

  final LinkedHashMap<int, _CacheEntry> _map = LinkedHashMap();
  int _invalidated = 0;

  /// Layouts held.
  int get length => _map.length;

  /// Entries rebuilt because their line changed (diagnostics).
  int get invalidated => _invalidated;

  /// The layout of [line] under [key], built with [build] if missing or if
  /// the cached one was built from a line that lays out differently. Marks
  /// it as used.
  LineLayout getOrBuild(int key, DiffLine line, LineLayout Function() build) {
    final hit = _map[key];
    if (hit != null) {
      hit.used = true;
      if (identical(hit.line, line) || hit.line.sameLayoutAs(line)) {
        hit.line = line;
        return hit.layout;
      }
      _invalidated++;
      hit.layout.dispose();
      hit
        ..line = line
        ..layout = build();
      return hit.layout;
    }
    final built = build();
    _map[key] = _CacheEntry(line, built);
    if (_map.length > maxEntries) _evict(key);
    return built;
  }

  // Evicts one entry other than [keep] (the one just added). Ends within
  // two passes: each pass clears the bits it finds set.
  void _evict(int keep) {
    while (true) {
      final key = _map.keys.first;
      final e = _map.remove(key)!;
      if (key == keep || e.used) {
        e.used = false;
        _map[key] = e;
        continue;
      }
      e.layout.dispose();
      return;
    }
  }

  /// Whether [key] is cached (does not touch recency).
  bool contains(int key) => _map.containsKey(key);

  /// Drops [key].
  void remove(int key) => _map.remove(key)?.layout.dispose();

  /// Drops everything.
  void clear() {
    for (final e in _map.values) {
      e.layout.dispose();
    }
    _map.clear();
  }
}

final class _CacheEntry {
  new(this.line, this.layout);

  DiffLine line;
  LineLayout layout;
  bool used = false;
}
