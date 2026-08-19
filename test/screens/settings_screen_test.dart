import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/settings_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renders the Voice and Speech Recognition switches at the '
      'given initial values', (tester) async {
    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          voiceEnabled: true,
          voicePreparing: false,
          recognitionEnabled: false,
          onVoiceChanged: (_) {},
          onRecognitionChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Speech Recognition'), findsOneWidget);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].value, isTrue);
    expect(switches[1].value, isFalse);
  });

  testWidgets('shows "Preparing voice…" only when voicePreparing is true', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          voiceEnabled: true,
          voicePreparing: true,
          recognitionEnabled: true,
          onVoiceChanged: (_) {},
          onRecognitionChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Preparing voice…'), findsOneWidget);
  });

  testWidgets('does not show "Preparing voice…" when voicePreparing is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          voiceEnabled: true,
          voicePreparing: false,
          recognitionEnabled: true,
          onVoiceChanged: (_) {},
          onRecognitionChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Preparing voice…'), findsNothing);
  });

  testWidgets('toggling Voice updates the switch and reports the new value', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      wrap(
        SettingsScreen(
          voiceEnabled: true,
          voicePreparing: false,
          recognitionEnabled: true,
          onVoiceChanged: changes.add,
          onRecognitionChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(Switch).at(0));
    await tester.pump();

    expect(changes, [false]);
    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isFalse);
  });

  testWidgets(
    'toggling Speech Recognition updates the switch and reports the new '
    'value',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        wrap(
          SettingsScreen(
            voiceEnabled: true,
            voicePreparing: false,
            recognitionEnabled: true,
            onVoiceChanged: (_) {},
            onRecognitionChanged: changes.add,
          ),
        ),
      );

      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();

      expect(changes, [false]);
      expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);
    },
  );
}
