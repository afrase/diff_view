import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:diff_view/diff_view.dart';

void main() => runApp(const ExampleApp());

const _captures = ['', 'keyword', 'string', 'comment', 'number'];

final _syntaxPattern = RegExp(
  r'(//.*$)|(\x27[^\x27]*\x27)|\b(\d+)\b|\b(import|class|final|const|void|return|if|else|for|var|int|String|extends|override)\b',
);

/// A tiny regex highlighter for the demo; use a real tokenizer in an app.
Uint32List? _highlight(PaneSide side, String line) {
  final out = <int>[];
  for (final m in _syntaxPattern.allMatches(line)) {
    final capture = m[1] != null
        ? 3
        : m[2] != null
        ? 2
        : m[3] != null
        ? 4
        : 1;
    out.addAll([m.start, m.end - m.start, capture]);
  }
  return out.isEmpty ? null : Uint32List.fromList(out);
}

const _old = r'''
import 'dart:math';

/// A counter.
class Counter {
  int value = 0;

  void increment() {
    value = value + 1;
  }

  // Adds one; see reset() to start over.
  void reset() {
    value = 0;
  }

  bool get isZero => value == 0;

  bool get isEven => value % 2 == 0;

  int doubled() {
    return value * 2;
  }

  int squared() {
    return value * value;
  }

  String describe() {
    if (isZero) {
      return 'zero';
    }
    return isEven ? 'even' : 'odd';
  }

  @override
  String toString() => 'Counter($value)';
}

void main() {
  final c = Counter();
  for (var i = 0; i < 3; i++) {
    c.increment();
  }
  print(c.value);
}
''';

const _new = r'''
import 'dart:math';

/// A counter with a step.
class Counter {
  Counter({this.step = 1});

  final int step;
  int value = 0;

  void increment() {
    value += step;
  }

  void reset() {
    value = 0;
  }

  bool get isZero => value == 0;

  bool get isEven => value % 2 == 0;

  int doubled() {
    return value * 2;
  }

  int squared() {
    return value * value;
  }

  String describe() {
    if (isZero) {
      return 'zero';
    }
    return isEven ? 'even' : 'odd';
  }

  @override
  String toString() => 'Counter($value)';
}

void main() {
  final c = Counter(step: 2);
  for (var i = 0; i < 5; i++) {
    c.increment();
  }
  print('value: ${c.value}');
}
''';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(brightness: Brightness.light),
    darkTheme: ThemeData(brightness: Brightness.dark),
    home: const Scaffold(body: DiffScreen()),
  );
}

class DiffScreen extends StatefulWidget {
  const DiffScreen({super.key});

  @override
  State<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends State<DiffScreen> {
  final _diff = TextDiff.compute(
    _old,
    _new,
    path: 'counter.dart',
    syntax: _highlight,
  );
  DiffViewController? _controller;
  DiffThemeData? _theme;
  bool _unified = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final theme = dark ? DiffThemeData.dark() : DiffThemeData.light();
    if (theme.brightness == _theme?.brightness) return;
    _controller?.dispose();
    _theme = theme;
    _controller = DiffViewController(
      document: _diff.document,
      lines: _diff.lines,
      theme: theme,
      captureNames: _captures,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final theme = _theme!;
    Widget inlay(BuildContext context, InlaySpec spec) =>
        const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: theme.gutterBackground,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  _diff.document.path,
                  style: TextStyle(color: theme.text, fontSize: 13),
                ),
                const Spacer(),
                // Select text in the code with the mouse (drag, double or
                // triple click), or lines in the gutter; Cmd/Ctrl+C or
                // this button copies it.
                ListenableBuilder(
                  listenable: controller.selectionChanges,
                  builder: (context, _) {
                    final label = _selectionLabel(controller);
                    return Row(
                      children: [
                        if (label != null)
                          Text(
                            label,
                            style: TextStyle(
                              color: theme.gutterText,
                              fontSize: 12,
                            ),
                          ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: label == null
                              ? null
                              : controller.copySelection,
                          child: const Text('Copy'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Split')),
                    ButtonSegment(value: true, label: Text('Unified')),
                  ],
                  selected: {_unified},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _unified = s.first),
                ),
              ],
            ),
          ),
        ),
        // Both views take the same controller; the new one opens at the
        // line the old one showed.
        Expanded(
          child: _unified
              ? UnifiedDiff(
                  controller: controller,
                  theme: theme,
                  inlayBuilder: inlay,
                )
              : SideBySideDiff(
                  controller: controller,
                  theme: theme,
                  inlayBuilder: inlay,
                ),
        ),
      ],
    );
  }
}

/// What is selected, as the bar shows it (1-based), or null.
String? _selectionLabel(DiffViewController c) {
  final text = c.textSelection.value;
  if (text != null) {
    final where = switch (text.side) {
      PaneSide.old => 'Old',
      PaneSide.neu => 'New',
      null => 'Unified',
    };
    final s = text.start;
    final e = text.end;
    return '$where ${s.line + 1}:${s.column + 1} to ${e.line + 1}:${e.column + 1}';
  }
  final lines = c.selection.value?.span ?? c.unifiedSelection.value?.span;
  if (lines == null) return null;
  return 'Lines ${lines.start + 1} to ${lines.end}';
}
