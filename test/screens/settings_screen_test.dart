import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/settings_screen.dart';
import 'package:morse_icr/speech/tts_voice_option.dart';

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
    bool randomCharacterOrder = true,
    List<TtsVoiceOption> voiceOptions = const [],
    String selectedVoiceName = '',
    String selectedVoiceLocale = '',
    ValueChanged<bool>? onVoiceChanged,
    ValueChanged<bool>? onRecognitionChanged,
    VoidCallback? onOpenVoiceSetup,
    ValueChanged<bool>? onSpeakPeriodAsDotChanged,
    ValueChanged<bool>? onSpeakSlashAsStrokeChanged,
    ValueChanged<int>? onMorsePitchChanged,
    ValueChanged<int>? onMorseVolumeChanged,
    ValueChanged<int>? onVoiceVolumeChanged,
    ValueChanged<bool>? onRandomCharacterOrderChanged,
    void Function(String name, String locale)? onSpeechVoiceChanged,
  }) => SettingsScreen(
    voiceEnabled: voiceEnabled,
    voicePreparing: voicePreparing,
    recognitionEnabled: recognitionEnabled,
    speakPeriodAsDot: speakPeriodAsDot,
    speakSlashAsStroke: speakSlashAsStroke,
    morsePitchHz: morsePitchHz,
    morseVolumePercent: morseVolumePercent,
    voiceVolumePercent: voiceVolumePercent,
    randomCharacterOrder: randomCharacterOrder,
    voiceOptions: voiceOptions,
    selectedVoiceName: selectedVoiceName,
    selectedVoiceLocale: selectedVoiceLocale,
    onVoiceChanged: onVoiceChanged ?? (_) {},
    onRecognitionChanged: onRecognitionChanged ?? (_) {},
    onOpenVoiceSetup: onOpenVoiceSetup ?? () {},
    onSpeakPeriodAsDotChanged: onSpeakPeriodAsDotChanged ?? (_) {},
    onSpeakSlashAsStrokeChanged: onSpeakSlashAsStrokeChanged ?? (_) {},
    onMorsePitchChanged: onMorsePitchChanged ?? (_) {},
    onMorseVolumeChanged: onMorseVolumeChanged ?? (_) {},
    onVoiceVolumeChanged: onVoiceVolumeChanged ?? (_) {},
    onRandomCharacterOrderChanged: onRandomCharacterOrderChanged ?? (_) {},
    onSpeechVoiceChanged: onSpeechVoiceChanged ?? (_, _) {},
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

  testWidgets('the Voice/Speech Recognition/Random Character Order toggle rows '
      "don't overflow at an iPhone mini/SE-class width -- regression: "
      '"Random Character Order" (the longest of the three labels) used to '
      'overflow past its Switch at 390 logical pixels wide, before the '
      "label got wrapped in an Expanded so it can wrap instead", (
    tester,
  ) async {
    addTearDown(() => tester.view.resetPhysicalSize());
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(wrap(buildScreen(voicePreparing: true)));
    await tester.pump();

    expect(tester.takeException(), isNull);
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

  testWidgets('shows "Auto" selected by default, with every given voice '
      'option listed by name and quality', (tester) async {
    await tester.pumpWidget(
      wrap(
        buildScreen(
          voiceOptions: const [
            TtsVoiceOption(
              name: 'Samantha',
              locale: 'en-US',
              quality: 'enhanced',
            ),
            TtsVoiceOption(
              name: 'Nathan',
              locale: 'en-US',
              quality: 'enhanced',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Auto'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Samantha (Enhanced)'), findsOneWidget);
    expect(find.text('Nathan (Enhanced)'), findsOneWidget);
  });

  testWidgets('does not double the quality suffix for a voice whose own name '
      'already includes it -- regression: some installed voices report '
      'their name as literally "Nathan (Enhanced)", not just "Nathan", '
      'while quality is *also* separately "enhanced"; appending '
      'unconditionally produced "Nathan (Enhanced) (Enhanced)", long '
      'enough to wrap and to crush the "Speech Voice" label next to it '
      "down to almost no width (Bill, on-device: label text rendering "
      'one letter per line)', (tester) async {
    await tester.pumpWidget(
      wrap(
        buildScreen(
          voiceOptions: const [
            TtsVoiceOption(
              name: 'Nathan (Enhanced)',
              locale: 'en-US',
              quality: 'enhanced',
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Nathan (Enhanced)'), findsOneWidget);
    expect(find.text('Nathan (Enhanced) (Enhanced)'), findsNothing);
  });

  testWidgets(
    'the "Speech Voice" label stays on one line even with a very long '
    'voice name selected -- regression: an unconstrained [DropdownButton] '
    'sizes itself to its *widest* item regardless of how little row '
    "width is left over, and a long enough item crushed this label down "
    'to almost no width, wrapping it one letter per line (Bill, '
    'on-device)',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          buildScreen(
            voiceOptions: const [
              TtsVoiceOption(
                name: 'A Very Long Example Installed Voice Name Indeed',
                locale: 'en-US',
                quality: 'enhanced',
              ),
            ],
            selectedVoiceName:
                'A Very Long Example Installed Voice Name Indeed',
            selectedVoiceLocale: 'en-US',
          ),
        ),
      );

      // "Voice" (the toggle label above) renders on one line at the
      // same [titleMedium] style -- "Speech Voice" should match its
      // height if it's also one line, versus many times taller if
      // crushed into a one-letter-per-line wrap.
      final speechVoiceHeight = tester
          .getSize(find.text('Speech Voice'))
          .height;
      final voiceHeight = tester.getSize(find.text('Voice')).height;
      expect(speechVoiceHeight, closeTo(voiceHeight, 1));
    },
  );

  testWidgets(
    'shows the given selected voice, not "Auto", when one is already set',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          buildScreen(
            voiceOptions: const [
              TtsVoiceOption(
                name: 'Nathan',
                locale: 'en-US',
                quality: 'enhanced',
              ),
            ],
            selectedVoiceName: 'Nathan',
            selectedVoiceLocale: 'en-US',
          ),
        ),
      );

      expect(find.text('Nathan (Enhanced)'), findsOneWidget);
    },
  );

  testWidgets(
    'falls back to showing "Auto" when the selected voice name/locale '
    "doesn't match any currently available option -- e.g. a preference "
    "persisted on a different device that doesn't have it installed",
    (tester) async {
      await tester.pumpWidget(
        wrap(
          buildScreen(
            voiceOptions: const [
              TtsVoiceOption(
                name: 'Nathan',
                locale: 'en-US',
                quality: 'enhanced',
              ),
            ],
            selectedVoiceName: 'Some Other Voice',
            selectedVoiceLocale: 'en-GB',
          ),
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
    },
  );

  testWidgets('selecting a voice option reports its name and locale via '
      'onSpeechVoiceChanged', (tester) async {
    final changes = <(String, String)>[];
    await tester.pumpWidget(
      wrap(
        buildScreen(
          voiceOptions: const [
            TtsVoiceOption(
              name: 'Nathan',
              locale: 'en-US',
              quality: 'enhanced',
            ),
          ],
          onSpeechVoiceChanged: (name, locale) => changes.add((name, locale)),
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nathan (Enhanced)').last);
    await tester.pumpAndSettle();

    expect(changes, [('Nathan', 'en-US')]);
    expect(find.text('Nathan (Enhanced)'), findsOneWidget);
  });

  testWidgets(
    'selecting "Auto" after a specific voice was selected reports empty '
    'name and locale',
    (tester) async {
      final changes = <(String, String)>[];
      await tester.pumpWidget(
        wrap(
          buildScreen(
            voiceOptions: const [
              TtsVoiceOption(
                name: 'Nathan',
                locale: 'en-US',
                quality: 'enhanced',
              ),
            ],
            selectedVoiceName: 'Nathan',
            selectedVoiceLocale: 'en-US',
            onSpeechVoiceChanged: (name, locale) => changes.add((name, locale)),
          ),
        ),
      );

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Auto').last);
      await tester.pumpAndSettle();

      expect(changes, [('', '')]);
      expect(find.text('Auto'), findsOneWidget);
    },
  );

  testWidgets(
    '"Personalize Recognition" is hidden -- production Speech Recognition '
    '(package:speech_to_text) needs no per-learner enrollment',
    (tester) async {
      await tester.pumpWidget(wrap(buildScreen()));

      expect(find.text('Personalize Recognition'), findsNothing);
    },
  );

  testWidgets('renders the Period/Dot and Slash/Stroke choices at the given '
      'initial values', (tester) async {
    await tester.pumpWidget(
      wrap(buildScreen(speakPeriodAsDot: true, speakSlashAsStroke: false)),
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
        buildScreen(morseVolumePercent: 60, onMorseVolumeChanged: changes.add),
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
      wrap(
        buildScreen(voiceVolumePercent: 90, onVoiceVolumeChanged: changes.add),
      ),
    );

    final addButton = find.byIcon(Icons.add_circle_outline).at(2);
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pump();

    expect(changes, [95]);
  });

  testWidgets(
    'renders the Random Character Order switch at the given initial value',
    (tester) async {
      await tester.pumpWidget(wrap(buildScreen(randomCharacterOrder: false)));

      expect(find.text('Random Character Order'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    },
  );

  testWidgets(
    'toggling Random Character Order updates the switch and reports the '
    'new value',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        wrap(
          buildScreen(
            randomCharacterOrder: true,
            onRandomCharacterOrderChanged: changes.add,
          ),
        ),
      );

      final toggle = find.byType(Switch).last;
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pump();

      expect(changes, [false]);
      expect(tester.widget<Switch>(toggle).value, isFalse);
    },
  );
}
