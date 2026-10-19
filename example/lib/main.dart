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
  Widget build(BuildContext context) => const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(body: DiffScreen()),
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
  Widget build(BuildContext context) => SideBySideDiff(
    controller: _controller!,
    theme: _theme!,
    inlayBuilder: (context, spec) => const SizedBox.shrink(),
  );
}
