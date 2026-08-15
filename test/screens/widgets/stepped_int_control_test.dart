import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/widgets/stepped_int_control.dart';

void main() {
  Widget buildControl({required int initialValue, ValueChanged<int>? onChanged}) {
    int value = initialValue;
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SteppedIntControl(
            label: 'Character Speed',
            value: value,
            min: 40,
            max: 150,
            step: 1,
            suffix: 'WPM',
            onChanged: (v) {
              setState(() => value = v);
              onChanged?.call(v);
            },
          ),
        ),
      ),
    );
  }

  testWidgets('submitting text updates value via onChanged', (tester) async {
    int value = 90;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SteppedIntControl(
              label: 'Character Speed',
              value: value,
              min: 40,
              max: 150,
              step: 1,
              suffix: 'WPM',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '120');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(value, 120);
    expect(find.text('Character Speed: 120 WPM'), findsOneWidget);
  });

  testWidgets('Done/Cancel buttons only appear while the field has focus', (
    tester,
  ) async {
    await tester.pumpWidget(buildControl(initialValue: 90));

    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.cancel), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
  });

  testWidgets('tapping Done commits the typed value and dismisses focus', (
    tester,
  ) async {
    int? committed;
    await tester.pumpWidget(
      buildControl(initialValue: 90, onChanged: (v) => committed = v),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '120');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.check_circle));
    await tester.pump();

    expect(committed, 120);
    expect(find.text('Character Speed: 120 WPM'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('tapping Cancel discards the typed value and dismisses focus', (
    tester,
  ) async {
    int? committed;
    await tester.pumpWidget(
      buildControl(initialValue: 90, onChanged: (v) => committed = v),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '120');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.cancel));
    await tester.pump();

    expect(committed, isNull);
    expect(find.text('Character Speed: 90 WPM'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsNothing);

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.text, '90');
  });
}
