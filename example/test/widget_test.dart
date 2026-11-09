import 'package:diff_view/diff_view.dart';
import 'package:diff_view_example/main.dart';
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
}
