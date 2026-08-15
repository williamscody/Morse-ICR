// App-level smoke test: verifies the app entry point wires up to the
// training screen. See test/screens/training_screen_test.dart for
// screen-level behavior.

import 'package:flutter_test/flutter_test.dart';

import 'package:morse_icr/app.dart';

void main() {
  testWidgets('MorseIcrApp builds and shows the app title', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MorseIcrApp());

    expect(find.text('Morse ICR'), findsOneWidget);
  });
}
