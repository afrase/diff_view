import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:side_by_side_diff/src/model/diff_line.dart';
import 'package:side_by_side_diff/src/render/diff_theme.dart';
import 'package:side_by_side_diff/src/render/line_layout.dart';

/// Horizontal layout of a pane: gutter (line numbers, change marker) then
/// code.
@immutable
final class GutterMetrics {
  /// Computes the metrics for line numbers of up to [digits] digits.
  factory({required int digits, required double advance}) {
    const pad = 8.0;
    final numberRight = pad + digits * advance;
    final markerX = numberRight + 6;
    final gutterWidth = markerX + advance + 6;
    return GutterMetrics._(numberRight, markerX, gutterWidth, gutterWidth + 6);
  }

  const new _(this.numberRight, this.markerX, this.gutterWidth, this.codeX);

  /// Right edge of the line numbers.
  final double numberRight;

  /// Left edge of the change marker / '+' affordance column.
  final double markerX;

  /// Width of the gutter; the code area starts here.
  final double gutterWidth;

  /// X where code text starts (at horizontal offset 0).
  final double codeX;
}

/// Everything the panes of one file view share for painting: the theme,
/// paragraph builders and caches, and the metrics snapped to the device
/// pixel ratio. One per file view; [dispose] it when the view closes.
final class DiffPaintResources {
  /// Creates resources for [theme], the file's capture table and the
  /// screen's [devicePixelRatio]. [maxLineCount] sizes the gutter.
  new({
    required this.theme,
    required List<String> captureNames,
    required this.devicePixelRatio,
    required int maxLineCount,
    int maxCachedLines = defaultMaxCachedLines,
  }) : layouts = LineLayoutBuilder(theme, captureNames),
       lines = ParagraphCache(maxEntries: maxCachedLines),
       lineHeight = theme.lineHeightFor(devicePixelRatio),
       placeholderHeight = theme.placeholderHeightFor(devicePixelRatio),
       _digits = maxLineCount.toString().length < 3
           ? 3
           : maxLineCount.toString().length;

  /// The theme.
  final DiffThemeData theme;

  /// The screen's device pixel ratio the metrics are snapped to.
  final double devicePixelRatio;

  /// Builds line layouts.
  final LineLayoutBuilder layouts;

  /// Default capacity of [lines]. A laid-out line
  /// costs about 35 KB of native memory on macOS (measured), so
  /// 6,000 would cost over 200 MB. 1,500 lines is about 15
  /// viewports of both panes.
  static const defaultMaxCachedLines = 1500;

  /// Laid-out code lines.
  final ParagraphCache lines;

  /// Height of a code row.
  final double lineHeight;

  /// Height of a fold placeholder.
  final double placeholderHeight;

  final int _digits;

  /// Horizontal layout of the panes.
  late final GutterMetrics gutter = GutterMetrics(
    digits: _digits,
    advance: layouts.advance,
  );

  static const _maxNumbers = 1024;
  static const _maxLabels = 128;
  final LinkedHashMap<int, ui.Paragraph> _numbers = LinkedHashMap();
  final LinkedHashMap<int, ui.Paragraph> _foldLabels = LinkedHashMap();
  final Map<LineKind, ui.Paragraph> _markers = {};

  /// Width of one code column.
  double get advance => layouts.advance;

  /// Y offset of text within a row, centring the text line.
  double get textTop =>
      ((lineHeight - layouts.textHeight) / 2).clamp(0.0, lineHeight);

  /// The gutter paragraph of [displayLine] (digit-string cache).
  /// Eviction is first-in first-out: a plain lookup on a hit, so the ~70
  /// visible rows of each pane cost no map churn per frame. The cache holds
  /// many viewports, so FIFO evicts only rows long off screen.
  ui.Paragraph number(int displayLine, {required bool changed}) {
    final key = displayLine * 2 + (changed ? 1 : 0);
    final hit = _numbers[key];
    if (hit != null) return hit;
    final p = _paragraph(
      displayLine.toString(),
      changed ? theme.gutterTextChanged : theme.gutterText,
    );
    _numbers[key] = p;
    if (_numbers.length > _maxNumbers) {
      _numbers.remove(_numbers.keys.first)?.dispose();
    }
    return p;
  }

  /// The `+` drawn in the gutter of the hovered row, cached in a
  /// field: it is drawn on every overlay paint while the pointer hovers.
  ui.Paragraph get hoverMarker =>
      _hoverMarker ??= _paragraph('+', theme.hoverAffordance);
  ui.Paragraph? _hoverMarker;

  /// The change marker glyph of [kind] (`+`, `−`, `~`) in the gutter.
  ui.Paragraph marker(LineKind kind) =>
      _markers[kind] ??= _paragraph(switch (kind) {
        LineKind.added => '+',
        LineKind.deleted => '−',
        LineKind.modified => '~',
        LineKind.unchanged => ' ',
      }, theme.gutterTextChanged);

  /// The label of a fold placeholder hiding [lines] lines, cached by count.
  ui.Paragraph foldLabel(int lines) {
    final hit = _foldLabels[lines];
    if (hit != null) return hit;
    final p = _paragraph(
      '⋯  $lines unchanged lines',
      theme.foldPlaceholderText,
    );
    _foldLabels[lines] = p;
    if (_foldLabels.length > _maxLabels) {
      _foldLabels.remove(_foldLabels.keys.first)?.dispose();
    }
    return p;
  }

  ui.Paragraph _paragraph(String text, Color color) {
    final b = ui.ParagraphBuilder(theme.paragraphStyle())
      ..pushStyle(theme.baseTextStyle(color: color))
      ..addText(text);
    return b.build()..layout(const ui.ParagraphConstraints(width: 1000000));
  }

  /// Releases every cached paragraph.
  void dispose() {
    lines.clear();
    for (final p in _numbers.values) {
      p.dispose();
    }
    for (final p in _foldLabels.values) {
      p.dispose();
    }
    for (final p in _markers.values) {
      p.dispose();
    }
    _hoverMarker?.dispose();
    _hoverMarker = null;
    _numbers.clear();
    _foldLabels.clear();
    _markers.clear();
  }
}
