import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/settings_screen.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  SettingsScreen buildScreen({
    bool voiceEnabled = true,
    bool voicePreparing = false,
    bool recognitionEnabled = true,
    bool speakPeriodAsDot = true,
    bool speakSlashAsStroke = false,
    int morsePitchHz = 600,
    int morseVolumePercent = 60,
    int voiceVolumePercent = 100,
    ValueChanged<bool>? onVoiceChanged,
    ValueChanged<bool>? onRecognitionChanged,
    ValueChanged<bool>? onSpeakPeriodAsDotChanged,
    ValueChanged<bool>? onSpeakSlashAsStrokeChanged,
    ValueChanged<int>? onMorsePitchChanged,
    ValueChanged<int>? onMorseVolumeChanged,
    ValueChanged<int>? onVoiceVolumeChanged,
  }) => SettingsScreen(
    voiceEnabled: voiceEnabled,
    voicePreparing: voicePreparing,
    recognitionEnabled: recognitionEnabled,
    speakPeriodAsDot: speakPeriodAsDot,
    speakSlashAsStroke: speakSlashAsStroke,
    morsePitchHz: morsePitchHz,
    morseVolumePercent: morseVolumePercent,
    voiceVolumePercent: voiceVolumePercent,
    onVoiceChanged: onVoiceChanged ?? (_) {},
    onRecognitionChanged: onRecognitionChanged ?? (_) {},
    onSpeakPeriodAsDotChanged: onSpeakPeriodAsDotChanged ?? (_) {},
    onSpeakSlashAsStrokeChanged: onSpeakSlashAsStrokeChanged ?? (_) {},
    onMorsePitchChanged: onMorsePitchChanged ?? (_) {},
    onMorseVolumeChanged: onMorseVolumeChanged ?? (_) {},
    onVoiceVolumeChanged: onVoiceVolumeChanged ?? (_) {},
  );

  testWidgets('renders the Voice and Speech Recognition switches at the '
      'given initial values', (tester) async {
    await tester.pumpWidget(
      wrap(buildScreen(voiceEnabled: true, recognitionEnabled: false)),
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
    await tester.pumpWidget(wrap(buildScreen(voicePreparing: true)));

    expect(find.text('Preparing voice…'), findsOneWidget);
  });

  testWidgets('does not show "Preparing voice…" when voicePreparing is false', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(buildScreen(voicePreparing: false)));

    expect(find.text('Preparing voice…'), findsNothing);
  });

  testWidgets('toggling Voice updates the switch and reports the new value', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      wrap(buildScreen(voiceEnabled: true, onVoiceChanged: changes.add)),
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
          buildScreen(
            recognitionEnabled: true,
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

  testWidgets('renders the Period/Dot and Slash/Stroke choices at the given '
      'initial values', (tester) async {
    await tester.pumpWidget(
      wrap(
        buildScreen(speakPeriodAsDot: true, speakSlashAsStroke: false),
      ),
    );

    final periodDot = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>).first,
    );
    final slashStroke = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>).last,
    );
    expect(periodDot.selected, {true});
    expect(slashStroke.selected, {false});
  });

  testWidgets('selecting "Period" reports speakPeriodAsDot as false', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      wrap(
        buildScreen(
          speakPeriodAsDot: true,
          onSpeakPeriodAsDotChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.text('Period'));
    await tester.pump();

    expect(changes, [false]);
  });

  testWidgets('selecting "Stroke" reports speakSlashAsStroke as true', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      wrap(
        buildScreen(
          speakSlashAsStroke: false,
          onSpeakSlashAsStrokeChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.text('Stroke'));
    await tester.pump();

    expect(changes, [true]);
  });

  testWidgets('shows the given Morse Pitch/Volume and Voice Volume values', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        buildScreen(
          morsePitchHz: 700,
          morseVolumePercent: 45,
          voiceVolumePercent: 80,
        ),
      ),
    );

    expect(find.text('Morse Pitch: 700 Hz'), findsOneWidget);
    expect(find.text('Morse Volume: 45 %'), findsOneWidget);
    expect(find.text('Voice Volume: 80 %'), findsOneWidget);
  });

  testWidgets('tapping + next to Morse Pitch increases it by the step', (
    tester,
  ) async {
    final changes = <int>[];
    await tester.pumpWidget(
      wrap(buildScreen(morsePitchHz: 600, onMorsePitchChanged: changes.add)),
    );

    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pump();

    expect(changes, [610]);
    expect(find.text('Morse Pitch: 610 Hz'), findsOneWidget);
  });

  testWidgets('tapping + next to Morse Volume increases it by the step', (
    tester,
  ) async {
    final changes = <int>[];
    await tester.pumpWidget(
      wrap(
        buildScreen(
          morseVolumePercent: 60,
          onMorseVolumeChanged: changes.add,
        ),
      ),
    );

    final addButton = find.byIcon(Icons.add_circle_outline).at(1);
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();

    expect(changes, [65]);
  });

  testWidgets('tapping + next to Voice Volume increases it by the step', (
    tester,
  ) async {
    final changes = <int>[];
    // Starts below 100%/max -- the + button is disabled at max.
    await tester.pumpWidget(
      wrap(buildScreen(voiceVolumePercent: 90, onVoiceVolumeChanged: changes.add)),
    );

    final addButton = find.byIcon(Icons.add_circle_outline).at(2);
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();

    expect(changes, [95]);
  });
}
