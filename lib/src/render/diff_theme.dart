import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Style of one syntax capture.
@immutable
final class SyntaxStyle {
  /// Creates a style.
  const new(this.color, {this.bold = false, this.italic = false});

  /// Text color.
  final Color color;

  /// Bold weight.
  final bool bold;

  /// Italic slant.
  final bool italic;
}

/// Colors and metrics of the diff viewer. Light and dark defaults
/// approximate IntelliJ Light and Darcula.
@immutable
final class DiffThemeData {
  /// Creates a theme.
  const new({
    required this.brightness,
    required this.background,
    required this.text,
    required this.gutterBackground,
    required this.gutterText,
    required this.gutterTextChanged,
    required this.insertedLine,
    required this.insertedWord,
    required this.deletedLine,
    required this.deletedWord,
    required this.modifiedLine,
    required this.modifiedWord,
    required this.ribbonInserted,
    required this.ribbonDeleted,
    required this.ribbonModified,
    required this.dividerBackground,
    required this.selection,
    required this.selectionOverCap,
    required this.foldPlaceholderBackground,
    required this.foldPlaceholderText,
    required this.loadingBar,
    required this.hoverAffordance,
    required this.syntax,
    this.ribbonBorder,
    this.fontFamily = 'JetBrains Mono',
    this.fontFamilyFallback = const ['Menlo', 'monospace'],
    this.fontSize = 13,
    this.lineHeightFactor = 1.45,
    this.placeholderHeightFactor = 1.5,
    this.tabSize = 4,
    this.dividerWidth = 24,
    this.inlayMaxWidth = 820,
  });

  /// IntelliJ Light-like defaults.
  factory light() => const DiffThemeData(
    brightness: ui.Brightness.light,
    background: Color(0xFFFFFFFF),
    text: Color(0xFF080808),
    gutterBackground: Color(0xFFF7F8FA),
    gutterText: Color(0xFF8C8C8C),
    gutterTextChanged: Color(0xFF4A4A4A),
    insertedLine: Color(0xFFE3F5E3),
    insertedWord: Color(0xFFB8E6B8),
    deletedLine: Color(0xFFEDEDED),
    deletedWord: Color(0xFFD6D6D6),
    modifiedLine: Color(0xFFE6EEFC),
    modifiedWord: Color(0xFFC2D6FA),
    ribbonInserted: Color(0xFFD2EFD2),
    ribbonDeleted: Color(0xFFE2E2E2),
    ribbonModified: Color(0xFFD6E3FA),
    dividerBackground: Color(0xFFF7F8FA),
    selection: Color(0x553D7EFF),
    selectionOverCap: Color(0x55E8A33D),
    foldPlaceholderBackground: Color(0xFFF0F2F5),
    foldPlaceholderText: Color(0xFF6F737A),
    loadingBar: Color(0xFFE6E8EB),
    hoverAffordance: Color(0xFF3574F0),
    syntax: {
      'keyword': SyntaxStyle(Color(0xFF0033B3), bold: true),
      'type': SyntaxStyle(Color(0xFF00627A)),
      'function': SyntaxStyle(Color(0xFF00627A)),
      'builtin': SyntaxStyle(Color(0xFF0033B3)),
      'string': SyntaxStyle(Color(0xFF067D17)),
      'number': SyntaxStyle(Color(0xFF1750EB)),
      'comment': SyntaxStyle(Color(0xFF8C8C8C), italic: true),
      'operator': SyntaxStyle(Color(0xFF080808)),
      'punctuation': SyntaxStyle(Color(0xFF080808)),
      'constant': SyntaxStyle(Color(0xFF871094)),
    },
  );

  /// Darcula-like defaults.
  factory dark() => const DiffThemeData(
    brightness: ui.Brightness.dark,
    background: Color(0xFF1E1F22),
    text: Color(0xFFBCBEC4),
    gutterBackground: Color(0xFF1E1F22),
    gutterText: Color(0xFF6F737A),
    gutterTextChanged: Color(0xFFA1A3AB),
    insertedLine: Color(0xFF2A3A2C),
    insertedWord: Color(0xFF3B5B3E),
    deletedLine: Color(0xFF34363B),
    deletedWord: Color(0xFF4A4D55),
    modifiedLine: Color(0xFF26324A),
    modifiedWord: Color(0xFF34486E),
    ribbonInserted: Color(0xFF2E4632),
    ribbonDeleted: Color(0xFF3C3F45),
    ribbonModified: Color(0xFF2C3B57),
    dividerBackground: Color(0xFF1E1F22),
    selection: Color(0x663D7EFF),
    selectionOverCap: Color(0x66E8A33D),
    foldPlaceholderBackground: Color(0xFF2B2D30),
    foldPlaceholderText: Color(0xFF8C8F96),
    loadingBar: Color(0xFF2B2D30),
    hoverAffordance: Color(0xFF548AF7),
    syntax: {
      'keyword': SyntaxStyle(Color(0xFFCF8E6D)),
      'type': SyntaxStyle(Color(0xFF2FBAA3)),
      'function': SyntaxStyle(Color(0xFF56A8F5)),
      'builtin': SyntaxStyle(Color(0xFFCF8E6D)),
      'string': SyntaxStyle(Color(0xFF6AAB73)),
      'number': SyntaxStyle(Color(0xFF2AACB8)),
      'comment': SyntaxStyle(Color(0xFF7A7E85), italic: true),
      'operator': SyntaxStyle(Color(0xFFBCBEC4)),
      'punctuation': SyntaxStyle(Color(0xFFBCBEC4)),
      'constant': SyntaxStyle(Color(0xFFC77DBB)),
    },
  );

  /// Light or dark.
  final ui.Brightness brightness;

  /// Code area background.
  final Color background;

  /// Default text color.
  final Color text;

  /// Gutter background.
  final Color gutterBackground;

  /// Line numbers of unchanged lines.
  final Color gutterText;

  /// Line numbers of changed lines.
  final Color gutterTextChanged;

  /// Inserted line tint.
  final Color insertedLine;

  /// Inserted word tint.
  final Color insertedWord;

  /// Deleted line tint.
  final Color deletedLine;

  /// Deleted word tint.
  final Color deletedWord;

  /// Modified line tint.
  final Color modifiedLine;

  /// Modified word tint.
  final Color modifiedWord;

  /// Ribbon fill of inserted blocks.
  final Color ribbonInserted;

  /// Ribbon fill of deleted blocks.
  final Color ribbonDeleted;

  /// Ribbon fill of modified blocks.
  final Color ribbonModified;

  /// Ribbon edge curves; null (the default) draws the ribbons without
  /// an outline.
  final Color? ribbonBorder;

  /// Divider background.
  final Color dividerBackground;

  /// Line selection band.
  final Color selection;

  /// Line selection band beyond the range cap.
  final Color selectionOverCap;

  /// Fold placeholder background.
  final Color foldPlaceholderBackground;

  /// Fold placeholder label.
  final Color foldPlaceholderText;

  /// Bars painted for rows that are not loaded yet.
  final Color loadingBar;

  /// The gutter '+' affordance.
  final Color hoverAffordance;

  /// Capture name → style. Unlisted captures use [text].
  final Map<String, SyntaxStyle> syntax;

  /// Code font family (bundled JetBrains Mono).
  final String fontFamily;

  /// Fallback families.
  final List<String> fontFamilyFallback;

  /// Code font size, logical px.
  final double fontSize;

  /// Line height as a multiple of [fontSize].
  final double lineHeightFactor;

  /// Fold placeholder height as a multiple of the line height.
  final double placeholderHeightFactor;

  /// Tab stop width in columns.
  final int tabSize;

  /// Width of the ribbon divider (IntelliJ `diff.divider.width`).
  final double dividerWidth;

  /// Widest an inlay gets.
  final double inlayMaxWidth;

  /// Line height snapped to physical pixels:
  /// `round(fontSize × factor × dpr) / dpr`.
  double lineHeightFor(double devicePixelRatio) =>
      (fontSize * lineHeightFactor * devicePixelRatio).roundToDouble() /
      devicePixelRatio;

  /// Placeholder height snapped to physical pixels.
  double placeholderHeightFor(double devicePixelRatio) =>
      (lineHeightFor(devicePixelRatio) *
              placeholderHeightFactor *
              devicePixelRatio)
          .roundToDouble() /
      devicePixelRatio;

  /// The paragraph style of a code line: one line, no ligatures so column
  /// math stays exact.
  ui.ParagraphStyle paragraphStyle() => ui.ParagraphStyle(
    maxLines: 1,
    fontFamily: fontFamily,
    fontSize: fontSize,
    textHeightBehavior: const ui.TextHeightBehavior(
      applyHeightToFirstAscent: false,
      applyHeightToLastDescent: false,
    ),
  );

  /// The base text style of code.
  ui.TextStyle baseTextStyle({Color? color}) => ui.TextStyle(
    color: color ?? text,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: fontSize,
    fontFeatures: const [
      ui.FontFeature.disable('liga'),
      ui.FontFeature.disable('calt'),
    ],
  );

  /// Text styles indexed by capture id for [captureNames]: a dotted name
  /// falls back to its parents
  /// (`keyword.control.return` → `keyword.control` → `keyword`).
  List<ui.TextStyle> resolveCaptures(List<String> captureNames) => [
    for (final name in captureNames) _captureStyle(name),
  ];

  ui.TextStyle _captureStyle(String name) {
    var n = name;
    while (n.isNotEmpty) {
      final s = syntax[n];
      if (s != null) {
        return ui.TextStyle(
          color: s.color,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
          fontSize: fontSize,
          fontWeight: s.bold ? FontWeight.w700 : null,
          fontStyle: s.italic ? FontStyle.italic : null,
          fontFeatures: const [
            ui.FontFeature.disable('liga'),
            ui.FontFeature.disable('calt'),
          ],
        );
      }
      final dot = n.lastIndexOf('.');
      n = dot < 0 ? '' : n.substring(0, dot);
    }
    return baseTextStyle();
  }
}
