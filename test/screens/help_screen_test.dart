import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/help_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('shows every section\'s Contents entry and header when the '
      'search field is empty', (tester) async {
    await tester.pumpWidget(wrap(const HelpScreen()));

    expect(find.text('Timer'), findsNWidgets(2));
    expect(find.text('Missing Fast'), findsNWidgets(2));
    expect(find.text('Voice Quality'), findsNWidgets(2));
  });

  testWidgets('typing a query filters the Contents list and body to only '
      'matching sections', (tester) async {
    await tester.pumpWidget(wrap(const HelpScreen()));

    await tester.enterText(find.byType(TextField), 'timer');
    await tester.pump();

    expect(find.text('Timer'), findsNWidgets(2));
    expect(find.text('Missing Fast'), findsNothing);
    expect(find.text('Voice Quality'), findsNothing);
  });

  testWidgets('matches on body text, not just the section title', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const HelpScreen()));

    // "QSO" only appears in the Missing Fast section's body, not its
    // title or any other section's.
    await tester.enterText(find.byType(TextField), 'QSO');
    await tester.pump();

    expect(find.text('Missing Fast'), findsNWidgets(2));
    expect(find.text('Timer'), findsNothing);
  });

  testWidgets('search is case-insensitive', (tester) async {
    await tester.pumpWidget(wrap(const HelpScreen()));

    await tester.enterText(find.byType(TextField), 'TIMER');
    await tester.pump();

    expect(find.text('Timer'), findsNWidgets(2));
  });

  testWidgets('shows a no-results message for a query that matches '
      'nothing, hiding Contents entirely', (tester) async {
    await tester.pumpWidget(wrap(const HelpScreen()));

    await tester.enterText(find.byType(TextField), 'zzzznotarealterm');
    await tester.pump();

    expect(find.text('No results for "zzzznotarealterm".'), findsOneWidget);
    expect(find.text('Contents'), findsNothing);
    expect(find.text('Timer'), findsNothing);
  });

  testWidgets('the clear button restores every section', (tester) async {
    await tester.pumpWidget(wrap(const HelpScreen()));

    await tester.enterText(find.byType(TextField), 'timer');
    await tester.pump();
    expect(find.text('Missing Fast'), findsNothing);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    expect(find.text('Timer'), findsNWidgets(2));
    expect(find.text('Missing Fast'), findsNWidgets(2));
  });
}
