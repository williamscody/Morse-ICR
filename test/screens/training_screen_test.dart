import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/morse_character_player.dart';
import 'package:morse_icr/screens/training_screen.dart';
import 'package:morse_icr/training/training_engine.dart';

/// A no-op player so Start/Stop tests never touch the real
/// [MorseAudioEngine] platform plugin, which has no channel mock
/// registered under `flutter test` and hangs indefinitely if invoked.
class _FakePlayer implements MorseCharacterPlayer {
  @override
  Future<void> playCharacter(String character, double wpm) async {}
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  // A fresh TrainingEngine/screen backed by [_FakePlayer], for any test
  // that starts training.
  Widget wrapTraining() => wrap(
    TrainingScreen(
      trainingEngine: TrainingEngine(audioPlayer: _FakePlayer()),
    ),
  );

  testWidgets('shows default speed, recognition time, and idle status', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    expect(find.text('Character Speed: 90 WPM'), findsOneWidget);
    expect(find.text('Recognition Time: 500 ms'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    final lettersChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'A-Z'),
    );
    expect(lettersChip.selected, isTrue);
  });

  testWidgets('tapping + next to WPM slider increases speed by 1', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    final addButtons = find.byIcon(Icons.add_circle_outline);
    await tester.tap(addButtons.first); // WPM control is first on screen
    await tester.pump();

    expect(find.text('Character Speed: 91 WPM'), findsOneWidget);
  });

  testWidgets('typing a WPM value and submitting updates the speed', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    final wpmField = find.byType(TextField).first;
    await tester.tap(wpmField);
    await tester.pump();
    await tester.enterText(wpmField, '120');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Character Speed: 120 WPM'), findsOneWidget);
  });

  testWidgets('typing a WPM value above max clamps to max', (tester) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    final wpmField = find.byType(TextField).first;
    await tester.tap(wpmField);
    await tester.pump();
    await tester.enterText(wpmField, '999');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Character Speed: 150 WPM'), findsOneWidget);
  });

  testWidgets('character set chips are multi-selectable', (tester) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    await tester.tap(find.text('0-9'));
    await tester.pump();

    final lettersChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'A-Z'),
    );
    final numbersChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, '0-9'),
    );
    expect(lettersChip.selected, isTrue);
    expect(numbersChip.selected, isTrue);
  });

  testWidgets('character set chips do not show a checkmark', (tester) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'A-Z'),
    );
    expect(chip.showCheckmark, isFalse);
  });

  testWidgets('all four character set chips fit on one line', (tester) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    final labels = ['A-Z', '0-9', 'Pun', 'Word'];
    final tops = <double>[];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
      tops.add(tester.getTopLeft(find.text(label)).dy);
    }
    expect(tops.toSet(), hasLength(1));
  });

  testWidgets(
    'tapping Start toggles to Training state and disables character-set '
    'selection',
    (tester) async {
      await tester.pumpWidget(wrapTraining());

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(find.text('Training…'), findsOneWidget);
      expect(find.text('Stop'), findsOneWidget);

      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'A-Z'),
      );
      expect(chip.onSelected, isNull);

      // Stop before the test ends so the training loop's timer doesn't
      // outlive the test.
      await tester.tap(find.text('Stop'));
      await tester.pump();
    },
  );

  testWidgets(
    'Character Speed and Recognition Time stay adjustable while training',
    (tester) async {
      await tester.pumpWidget(wrapTraining());

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      final addButtons = find.byIcon(Icons.add_circle_outline);
      await tester.tap(addButtons.first); // Character Speed is first
      await tester.pump();
      await tester.tap(addButtons.at(1)); // Recognition Time is second
      await tester.pump();

      expect(find.text('Character Speed: 91 WPM'), findsOneWidget);
      expect(find.text('Recognition Time: 501 ms'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();
    },
  );

  testWidgets('tapping Stop returns to Idle and re-enables controls', (
    tester,
  ) async {
    await tester.pumpWidget(wrapTraining());

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(find.text('Idle'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'A-Z'),
    );
    expect(chip.onSelected, isNotNull);
  });

  testWidgets('Start is disabled when no character set is selected', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const TrainingScreen()));

    await tester.tap(find.text('A-Z')); // deselect the only active set
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('shows a running characters-played counter while training', (
    tester,
  ) async {
    await tester.pumpWidget(wrapTraining());

    expect(find.textContaining('Characters played'), findsNothing);

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(find.textContaining('Characters played:'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
  });
}
