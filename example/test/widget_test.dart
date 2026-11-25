import 'package:diff_view/diff_view.dart';
import 'package:diff_view_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the switch moves between split and unified', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.byType(SideBySideDiff), findsOneWidget);
    expect(find.byType(UnifiedDiff), findsNothing);

    await tester.tap(find.text('Unified'));
    await tester.pumpAndSettle();
    expect(find.byType(UnifiedDiff), findsOneWidget);
    expect(find.byType(SideBySideDiff), findsNothing);

    await tester.tap(find.text('Split'));
    await tester.pumpAndSettle();
    expect(find.byType(SideBySideDiff), findsOneWidget);
  });

  testWidgets('a text selection shows in the bar and Copy copies it', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(const ExampleApp());
    final copy = find.widgetWithText(TextButton, 'Copy');
    expect(tester.widget<TextButton>(copy).onPressed, isNull);

    final view = tester.widget<SideBySideDiff>(find.byType(SideBySideDiff));
    view.controller.textSelection.select(
      const CodeSelection(
        side: PaneSide.neu,
        anchor: CodePosition(0, 0),
        focus: CodePosition(0, 6),
      ),
    );
    await tester.pump();
    expect(find.text('New 1:1 to 1:7'), findsOneWidget);
    await tester.tap(copy);
    await tester.pump();
    expect(clipboard, 'import');
  });
}
