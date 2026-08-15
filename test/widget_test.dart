// Milestone 1 smoke test: verifies the app shell builds and renders.
// Replaced/extended once the real training screen exists.

import 'package:flutter_test/flutter_test.dart';

import 'package:morse_icr/app.dart';

void main() {
  testWidgets('MorseIcrApp builds and shows placeholder title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MorseIcrApp());

    expect(find.text('Morse ICR'), findsOneWidget);
  });
}
