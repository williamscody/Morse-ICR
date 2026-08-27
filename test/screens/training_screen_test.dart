import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/turn_player.dart';
import 'package:morse_icr/morse/morse_event.dart';
import 'package:morse_icr/screens/settings_screen.dart';
import 'package:morse_icr/screens/training_screen.dart';
import 'package:morse_icr/speech/answer_speaker.dart';
import 'package:morse_icr/speech/response_listener.dart';
import 'package:morse_icr/training/countdown_timer_config.dart';
import 'package:morse_icr/training/countdown_timer_store.dart';
import 'package:morse_icr/training/problem_character_store.dart';
import 'package:morse_icr/training/training_engine.dart';
import 'package:morse_icr/training/training_log_store.dart';
import 'package:morse_icr/training/training_session_record.dart';

/// Locates the [SettingsScreen] pushed by tapping the app bar's
/// settings icon. Flutter's default byType finder skips "offstage"
/// widgets, and a just-pushed [MaterialPageRoute]'s content stays
/// flagged offstage well past its own transition finishing -- an SDK
/// quirk in this Flutter version, not anything about this app -- so
/// this needs skipOffstage disabled. Callers drive the screen by
/// invoking its callbacks directly and popping via [Navigator] rather
/// than tapping through it, since taps on that same offstage-flagged
/// content don't hit-test correctly either.
Finder _pushedSettingsScreen() =>
    find.byType(SettingsScreen, skipOffstage: false);

/// A no-op player so Start/Stop tests never touch the real
/// [TurnAudioEngine] platform plugin, which has no channel mock
/// registered under `flutter test` and hangs indefinitely if invoked.
/// Reports real Morse-derived timing (no cached answer) so
/// submitResponse's "beat the computer" window behaves the same as it
/// would against real audio.
class _FakeTurnPlayer extends TurnPlayer {
  @override
  Future<TurnTiming> playTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) async {
    final seconds = morseElementsForCharacter(
      character,
      wpm,
    ).fold<double>(0, (sum, e) => sum + e.durationSeconds);
    final morseEnd = Duration(microseconds: (seconds * 1e6).round());
    final answerStart = morseEnd + recognitionTime;
    return TurnTiming(
      morseEnd: morseEnd,
      answerStart: answerStart,
      totalDuration: answerStart,
      hasAnswer: false,
    );
  }
}

/// A recording speaker so tests can verify the recognition-timeout ->
/// speech wiring without touching real text-to-speech.
class _FakeSpeaker extends AnswerSpeaker {
  final List<String> spoken = [];

  @override
  Future<void> speak(String character) async {
    spoken.add(character);
  }
}

/// A no-op listener so Start/Stop tests never touch the real
/// `VoiceResponseListener` platform plugins, which -- like
/// [_FakeTurnPlayer]'s real counterpart -- have no channel mock
/// registered under `flutter test` and hang indefinitely if invoked.
/// Also records the callback so tests can simulate a recognized
/// response.
class _FakeResponseListener implements ResponseListener {
  final List<String> startListeningCalls = [];
  final List<String> restartCalls = [];
  final List<String> stopListeningCalls = [];
  ResponseCallback? onRecognized;

  @override
  Future<void> startListening(ResponseCallback onRecognized) async {
    this.onRecognized = onRecognized;
    startListeningCalls.add('start');
  }

  @override
  Future<void> restart() async {
    restartCalls.add('restart');
  }

  @override
  Future<void> stopListening() async {
    onRecognized = null;
    stopListeningCalls.add('stop');
  }
}

/// An in-memory store so Focus-button tests never touch the real
/// [FileProblemCharacterStore]'s platform-backed `path_provider` calls.
class _FakeProblemCharacterStore implements ProblemCharacterStore {
  List<String>? saved;
  Set<String> savedAutoFlagged = const {};
  Map<String, int> savedScores = const {};
  Map<String, int> savedAttempts = const {};

  @override
  Future<List<String>?> load() async => saved;

  @override
  Future<void> save(List<String> characters) async {
    saved = characters;
  }

  @override
  Future<Set<String>> loadAutoFlagged() async => savedAutoFlagged;

  @override
  Future<void> saveAutoFlagged(Set<String> characters) async {
    savedAutoFlagged = characters;
  }

  @override
  Future<Map<String, int>> loadScores() async => savedScores;

  @override
  Future<void> saveScores(Map<String, int> scores) async {
    savedScores = scores;
  }

  @override
  Future<Map<String, int>> loadAttempts() async => savedAttempts;

  @override
  Future<void> saveAttempts(Map<String, int> attempts) async {
    savedAttempts = attempts;
  }
}

/// An in-memory store so Timer-row tests never touch the real
/// [FileCountdownTimerStore]'s platform-backed `path_provider` calls.
class _FakeCountdownTimerStore implements CountdownTimerStore {
  _FakeCountdownTimerStore([this.saved = const CountdownTimerConfig()]);

  CountdownTimerConfig saved;

  @override
  Future<CountdownTimerConfig> load() async => saved;

  @override
  Future<void> save(CountdownTimerConfig config) async {
    saved = config;
  }
}

/// An in-memory store so every Stop -- which now awaits
/// [TrainingLogStore] as part of recording the completed session --
/// never touches the real [FileTrainingLogStore]'s platform-backed
/// `path_provider`/`dart:io` calls, which (unlike the fire-and-forget
/// loads other stores do in `initState`) are on the critical Stop path
/// and don't resolve within a single `tester.pump()` against real disk
/// I/O.
class _FakeTrainingLogStore implements TrainingLogStore {
  List<TrainingSessionRecord> saved = [];

  @override
  Future<List<TrainingSessionRecord>> load() async => saved;

  @override
  Future<void> save(List<TrainingSessionRecord> records) async {
    saved = records;
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  // A fresh TrainingEngine/screen backed by [_FakeTurnPlayer], for any
  // test that starts training.
  Widget wrapTraining({
    AnswerSpeaker? answerSpeaker,
    ResponseListener? responseListener,
    ProblemCharacterStore? problemCharacterStore,
    CountdownTimerStore? countdownTimerStore,
    TrainingLogStore? trainingLogStore,
  }) => wrap(
    TrainingScreen(
      trainingEngine: TrainingEngine(turnPlayer: _FakeTurnPlayer()),
      answerSpeaker: answerSpeaker ?? _FakeSpeaker(),
      responseListener: responseListener ?? _FakeResponseListener(),
      problemCharacterStore:
          problemCharacterStore ?? _FakeProblemCharacterStore(),
      countdownTimerStore: countdownTimerStore ?? _FakeCountdownTimerStore(),
      trainingLogStore: trainingLogStore ?? _FakeTrainingLogStore(),
      headphonesConnectedCheck: () async => true,
      reconfigureAudioSessionOnStart: () async {},
      activateAudioSessionOnStart: () async {},
      deactivateAudioSessionOnStop: () async {},
    ),
  );

  testWidgets('shows default speed, recognition time, and idle status', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

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
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    final addButtons = find.byIcon(Icons.add_circle_outline);
    await tester.tap(addButtons.first); // WPM control is first on screen
    await tester.pump();

    expect(find.text('Character Speed: 91 WPM'), findsOneWidget);
  });

  testWidgets('typing a WPM value and submitting updates the speed', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

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
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    final wpmField = find.byType(TextField).first;
    await tester.tap(wpmField);
    await tester.pump();
    await tester.enterText(wpmField, '999');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Character Speed: 120 WPM'), findsOneWidget);
  });

  testWidgets('character set chips are multi-selectable', (tester) async {
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    await tester.ensureVisible(find.text('0-9'));
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
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'A-Z'),
    );
    expect(chip.showCheckmark, isFalse);
  });

  testWidgets('all four character set chips fit on one line', (tester) async {
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    final labels = ['A-Z', '0-9', 'Punct', 'Word'];
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
    'a second tap landing while Start is still completing its async setup '
    'is ignored, instead of desyncing the button label from whether '
    'training is actually running',
    (tester) async {
      final gate = Completer<void>();
      final engine = TrainingEngine(turnPlayer: _FakeTurnPlayer());
      await tester.pumpWidget(
        wrap(
          TrainingScreen(
            trainingEngine: engine,
            answerSpeaker: _FakeSpeaker(),
            responseListener: _FakeResponseListener(),
            trainingLogStore: _FakeTrainingLogStore(),
            headphonesConnectedCheck: () async => true,
            // Simulates a slow real platform call landing between the
            // button optimistically flipping to "Stop" and the engine
            // actually starting.
            reconfigureAudioSessionOnStart: () => gate.future,
            activateAudioSessionOnStart: () async {},
            deactivateAudioSessionOnStop: () async {},
          ),
        ),
      );

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('Stop'), findsOneWidget);
      expect(engine.isRunning, isFalse);

      // Lands while the first call is still awaiting the gate -- must
      // be a no-op rather than acting on the not-yet-settled state.
      await tester.tap(find.text('Stop'));
      await tester.pump();

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(engine.isRunning, isTrue);
      expect(find.text('Stop'), findsOneWidget);

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
      await tester.ensureVisible(addButtons.first);
      await tester.tap(addButtons.first); // Character Speed is first
      await tester.pump();
      await tester.ensureVisible(addButtons.at(1));
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

  testWidgets('starts and stops listening for the learner\'s spoken response '
      'alongside Start/Stop', (tester) async {
    final listener = _FakeResponseListener();
    await tester.pumpWidget(wrapTraining(responseListener: listener));

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(listener.startListeningCalls, ['start']);
    expect(listener.stopListeningCalls, isEmpty);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(listener.stopListeningCalls, ['stop']);
  });

  testWidgets('opens Settings from the app bar icon, and turning Speech '
      'Recognition off there before Start skips startListening', (
    tester,
  ) async {
    final listener = _FakeResponseListener();
    await tester.pumpWidget(wrapTraining(responseListener: listener));

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    final settingsFinder = _pushedSettingsScreen();
    tester.widget<SettingsScreen>(settingsFinder).onRecognitionChanged(false);
    Navigator.of(tester.element(settingsFinder)).pop();
    await tester.pump();

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();

    expect(listener.startListeningCalls, isEmpty);
  });

  testWidgets('toggling Speech Recognition off in Settings mid-session stops '
      'listening immediately, back on starts it again', (tester) async {
    final listener = _FakeResponseListener();
    await tester.pumpWidget(wrapTraining(responseListener: listener));

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(listener.startListeningCalls, ['start']);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();
    final settingsFinder = _pushedSettingsScreen();
    final settings = tester.widget<SettingsScreen>(settingsFinder);
    settings.onRecognitionChanged(false);
    await tester.pump();
    expect(listener.stopListeningCalls, ['stop']);

    settings.onRecognitionChanged(true);
    await tester.pump();
    expect(listener.startListeningCalls, ['start', 'start']);

    Navigator.of(tester.element(settingsFinder)).pop();
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets(
    'forwards a recognized character to TrainingEngine.submitResponse',
    (tester) async {
      final listener = _FakeResponseListener();
      final engine = TrainingEngine(turnPlayer: _FakeTurnPlayer());
      await tester.pumpWidget(
        wrap(
          TrainingScreen(
            trainingEngine: engine,
            answerSpeaker: _FakeSpeaker(),
            responseListener: listener,
            trainingLogStore: _FakeTrainingLogStore(),
            headphonesConnectedCheck: () async => true,
            reconfigureAudioSessionOnStart: () async {},
            activateAudioSessionOnStart: () async {},
            deactivateAudioSessionOnStop: () async {},
          ),
        ),
      );
      final correct = <String>[];
      engine.onCorrectResponse = correct.add;

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      // Default character speed (90 WPM) comfortably covers even the
      // longest letter's playback within 250ms, so the first
      // character's recognition timer is running by then, well before
      // its 500ms deadline. Which letter was actually generated is
      // deliberately never surfaced (morse_icr_spec.md section 24
      // forbids displaying it), so every letter is "recognized" --
      // submitResponse no-ops for the ones that don't match whatever
      // was actually generated.
      await tester.pump(const Duration(milliseconds: 250));
      for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
        listener.onRecognized?.call(letter);
      }
      await tester.pump(const Duration(milliseconds: 10));

      expect(correct, isNotEmpty);

      await tester.tap(find.text('Stop'));
      await tester.pump();
    },
  );

  testWidgets('shows a green dot for a correct response, cleared on the next '
      'character', (tester) async {
    final listener = _FakeResponseListener();
    final engine = TrainingEngine(turnPlayer: _FakeTurnPlayer());
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          trainingEngine: engine,
          answerSpeaker: _FakeSpeaker(),
          responseListener: listener,
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    bool hasDot() =>
        tester
            .widget<SizedBox>(find.byKey(const Key('correctResponseIndicator')))
            .child !=
        null;

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(hasDot(), isFalse);

    // Section 24: the generated character is never surfaced, so
    // every letter is fed to the listener callback and
    // submitResponse no-ops for the ones that don't match whatever
    // was actually generated.
    await tester.pump(const Duration(milliseconds: 250));
    for (final letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) {
      listener.onRecognized?.call(letter);
    }
    await tester.pump(const Duration(milliseconds: 10));
    expect(hasDot(), isTrue);

    // Advances past the rest of the recognition window (default
    // 500ms) into the next character, which should clear the dot
    // even though nothing was said for it.
    await tester.pump(const Duration(milliseconds: 400));
    expect(hasDot(), isFalse);

    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets(
    'a session with recognition on and at least one miss auto-flags the '
    'missed characters for review, without adding them to the active '
    'Focus selection itself',
    (tester) async {
      final store = _FakeProblemCharacterStore()..saved = ['K'];
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      // Default character speed (90 WPM) plus default recognition time
      // (500 ms) comfortably closes the first character's window with
      // no response ever submitted for it -- a guaranteed miss.
      await tester.pump(const Duration(milliseconds: 900));

      await tester.tap(find.text('Stop'));
      await tester.pump();

      // The persisted Focus selection itself is untouched -- still
      // exactly what it was before this session (2026-08-26: an earlier
      // version merged missed characters in here too, which silently
      // grew the active training set -- and ProblemCharacterKeyboard's
      // own "Focus (n active)" count -- with characters the learner
      // never chose).
      expect(store.saved, ['K']);
      expect(store.savedAutoFlagged, isNotEmpty);
    },
  );

  testWidgets(
    'auto-flagging a newly-missed character preserves an already-flagged '
    'one from an earlier session, rather than replacing the whole set',
    (tester) async {
      final store = _FakeProblemCharacterStore()
        ..saved = ['K']
        ..savedAutoFlagged = {'Z'};
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.text('Stop'));
      await tester.pump();

      // 'Z' was flagged before this session even started (never
      // reviewed) -- it must still be flagged afterward, alongside
      // whatever this session's own guaranteed miss added.
      expect(store.savedAutoFlagged, contains('Z'));
    },
  );

  testWidgets(
    'a character missed once but answered correctly on a later attempt in '
    'the same session is not flagged (majority-miss, not any-miss)',
    (tester) async {
      final listener = _FakeResponseListener();
      final engine = TrainingEngine(turnPlayer: _FakeTurnPlayer());
      final store = _FakeProblemCharacterStore()..saved = ['K'];
      await tester.pumpWidget(
        wrap(
          TrainingScreen(
            trainingEngine: engine,
            answerSpeaker: _FakeSpeaker(),
            responseListener: listener,
            problemCharacterStore: store,
            trainingLogStore: _FakeTrainingLogStore(),
            headphonesConnectedCheck: () async => true,
            reconfigureAudioSessionOnStart: () async {},
            activateAudioSessionOnStart: () async {},
            deactivateAudioSessionOnStop: () async {},
          ),
        ),
      );
      // The store's single saved character ('K') comes up auto-active as
      // the Focus set from cold launch, so every turn this session
      // generates is guaranteed to be 'K' -- letting this test control
      // exactly which attempt gets a response.
      await tester.pump();

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      // First 'K': its window closes with no response at all -- a
      // guaranteed miss, same margin as the "at least one miss" test
      // above. This comfortably carries the session into the second
      // 'K' turn's own still-open response window too (its total
      // duration is dominated by the same 500ms recognition time).
      await tester.pump(const Duration(milliseconds: 900));

      // Second 'K': respond correctly while its window is still open.
      listener.onRecognized?.call('K');
      await tester.pump(const Duration(milliseconds: 10));

      await tester.tap(find.text('Stop'));
      await tester.pump();

      // One miss, one hit for 'K' -- not missed *more often than not* --
      // so it must not be auto-flagged, and the store (already holding
      // exactly 'K') must be left completely untouched.
      expect(store.saved, ['K']);
      expect(store.savedAutoFlagged, isEmpty);
      // The one hit still counts toward 'K''s all-time win score,
      // independent of the majority-miss auto-flagging logic above.
      expect(store.savedScores, {'K': 1});
    },
  );

  testWidgets(
    'a character that is always missed, never once answered correctly, '
    'still gets a 0 score entry -- not left with no entry at all, which '
    'would be indistinguishable from a character that was never trained',
    (tester) async {
      final listener = _FakeResponseListener();
      final engine = TrainingEngine(turnPlayer: _FakeTurnPlayer());
      final store = _FakeProblemCharacterStore()..saved = ['K'];
      await tester.pumpWidget(
        wrap(
          TrainingScreen(
            trainingEngine: engine,
            answerSpeaker: _FakeSpeaker(),
            responseListener: listener,
            problemCharacterStore: store,
            trainingLogStore: _FakeTrainingLogStore(),
            headphonesConnectedCheck: () async => true,
            reconfigureAudioSessionOnStart: () async {},
            activateAudioSessionOnStart: () async {},
            deactivateAudioSessionOnStop: () async {},
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      // 'K' (the only active character) never gets a response at all --
      // a guaranteed miss, same margin used elsewhere in this file.
      await tester.pump(const Duration(milliseconds: 900));

      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(store.savedScores, {'K': 0});
    },
  );

  testWidgets(
    'a session with recognition off never touches the problem-character '
    'store, even though every character goes unanswered',
    (tester) async {
      final store = _FakeProblemCharacterStore();
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      final settingsFinder = _pushedSettingsScreen();
      tester.widget<SettingsScreen>(settingsFinder).onRecognitionChanged(false);
      Navigator.of(tester.element(settingsFinder)).pop();
      await tester.pump();

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));

      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(store.saved, isNull);
      expect(store.savedAutoFlagged, isEmpty);
      expect(store.savedScores, isEmpty);
    },
  );

  testWidgets(
    'a session stopped before any response window closes never writes to '
    'the problem-character store',
    (tester) async {
      final store = _FakeProblemCharacterStore();
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(store.saved, isNull);
      expect(store.savedAutoFlagged, isEmpty);
      expect(store.savedScores, isEmpty);
    },
  );

  testWidgets('Start is disabled when no character set is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        TrainingScreen(
          answerSpeaker: _FakeSpeaker(),
          trainingLogStore: _FakeTrainingLogStore(),
          headphonesConnectedCheck: () async => true,
          reconfigureAudioSessionOnStart: () async {},
          activateAudioSessionOnStart: () async {},
          deactivateAudioSessionOnStop: () async {},
        ),
      ),
    );

    await tester.ensureVisible(find.text('A-Z'));
    await tester.tap(find.text('A-Z')); // deselect the only active set
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('announces the character via AnswerSpeaker once its recognition '
      'deadline lapses', (tester) async {
    final speaker = _FakeSpeaker();
    await tester.pumpWidget(wrapTraining(answerSpeaker: speaker));

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();

    // Default character speed (90 WPM) plus default recognition time
    // (500 ms) comfortably fit within this window for any letter.
    await tester.pump(const Duration(milliseconds: 900));

    expect(speaker.spoken, isNotEmpty);
    expect(speaker.spoken, everyElement(matches(RegExp(r'^[A-Z]$'))));

    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets(
    'passes voicePreparing through to Settings while the real TTS voice '
    'is being prepared',
    (tester) async {
      await tester.pumpWidget(wrap(const TrainingScreen()));

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();

      expect(
        find.text('Preparing voice…', skipOffstage: false),
        findsOneWidget,
      );
    },
  );

  testWidgets('does not show "Preparing voice…" in Settings for a non-TTS '
      'AnswerSpeaker', (tester) async {
    await tester.pumpWidget(wrapTraining());

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump();

    expect(find.text('Preparing voice…', skipOffstage: false), findsNothing);
  });

  testWidgets(
    'opens Settings from the app bar icon, and turning Voice off there '
    'suppresses the computer announcement',
    (tester) async {
      final speaker = _FakeSpeaker();
      await tester.pumpWidget(wrapTraining(answerSpeaker: speaker));

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();
      final settingsFinder = _pushedSettingsScreen();
      tester.widget<SettingsScreen>(settingsFinder).onVoiceChanged(false);
      Navigator.of(tester.element(settingsFinder)).pop();
      await tester.pump();

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 900));

      expect(speaker.spoken, isEmpty);

      await tester.tap(find.text('Stop'));
      await tester.pump();
    },
  );

  testWidgets(
    'opens the Problem Character keyboard from the Focus button, and the '
    'set entered there becomes the active training set',
    (tester) async {
      await tester.pumpWidget(wrapTraining());

      expect(find.text('Focus (none)'), findsOneWidget);
      await tester.ensureVisible(find.text('Focus (none)'));
      await tester.tap(find.text('Focus (none)'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.tap(find.widgetWithText(FilterChip, 'R'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Focus (2 active)'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting a character-set chip clears an active problem-character set',
    (tester) async {
      final store = _FakeProblemCharacterStore()..saved = ['K', 'R'];
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));

      await tester.ensureVisible(find.text('Focus (none)'));
      await tester.tap(find.text('Focus (none)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Focus (2 active)'), findsOneWidget);

      // The Focus button sits below the character-set chips, so
      // ensureVisible-ing it earlier can scroll far enough that the
      // chips themselves end up behind the AppBar -- ensure A-Z is back
      // in view before tapping it, rather than relying on incidental
      // scroll position.
      await tester.ensureVisible(find.text('A-Z'));
      await tester.tap(find.text('A-Z')); // deselect the only active chip
      await tester.pump();
      await tester.ensureVisible(find.text('A-Z'));
      await tester.tap(find.text('A-Z')); // reselect it
      await tester.pump();

      expect(find.text('Focus (none)'), findsOneWidget);
      expect(find.text('Focus (2 active)'), findsNothing);
    },
  );

  testWidgets(
    'Clear-then-Done in the Problem Character keyboard deactivates the '
    'problem-character set entirely, not just within that keyboard',
    (tester) async {
      final store = _FakeProblemCharacterStore()..saved = ['K', 'R'];
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));
      await tester.pump(); // let cold-launch activation settle
      expect(find.text('Focus (2 active)'), findsOneWidget);

      await tester.ensureVisible(find.text('Focus (2 active)'));
      await tester.tap(find.text('Focus (2 active)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('Focus (none)'), findsOneWidget);
      expect(find.text('Focus (2 active)'), findsNothing);
      expect(store.saved, isEmpty);
    },
  );

  testWidgets(
    'a previously-saved problem-character set is active from cold launch, '
    'not just for the rest of the session it was entered in',
    (tester) async {
      final store = _FakeProblemCharacterStore()..saved = ['K', 'R', 'F'];
      await tester.pumpWidget(wrapTraining(problemCharacterStore: store));
      await tester.pump();

      expect(find.text('Focus (3 active)'), findsOneWidget);
    },
  );

  testWidgets('Focus button is disabled while training', (tester) async {
    await tester.pumpWidget(wrapTraining());

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Focus (none)'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets('the Timer row shows "Off" when no memory is selected', (
    tester,
  ) async {
    await tester.pumpWidget(wrapTraining());
    await tester.pump();

    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets(
    'the Timer row shows the active memory\'s stored duration from cold '
    'launch',
    (tester) async {
      final store = _FakeCountdownTimerStore(
        const CountdownTimerConfig(
          slotSeconds: [300, null, null],
          selectedSlot: 0,
        ),
      );
      await tester.pumpWidget(wrapTraining(countdownTimerStore: store));
      await tester.pump();

      expect(find.text('05:00'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping the Timer row opens Countdown Timer Settings, and a memory '
    'selected there updates the main-screen display',
    (tester) async {
      final store = _FakeCountdownTimerStore();
      await tester.pumpWidget(wrapTraining(countdownTimerStore: store));
      await tester.pump();

      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '2');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Memory 1'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('02:00'), findsOneWidget);
      expect(store.saved.selectedSlot, 0);
    },
  );

  testWidgets('the Timer row is disabled while training', (tester) async {
    await tester.pumpWidget(wrapTraining());

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();

    final inkWell = tester.widget<InkWell>(
      find.ancestor(of: find.text('Timer'), matching: find.byType(InkWell)),
    );
    expect(inkWell.onTap, isNull);

    await tester.tap(find.text('Stop'));
    await tester.pump();
  });

  testWidgets(
    'a running countdown counts down by the second, stops training when '
    'it reaches zero, and restores the display to the configured duration',
    (tester) async {
      final store = _FakeCountdownTimerStore(
        const CountdownTimerConfig(
          slotSeconds: [3, null, null],
          selectedSlot: 0,
        ),
      );
      await tester.pumpWidget(wrapTraining(countdownTimerStore: store));
      await tester.pump();
      expect(find.text('00:03'), findsOneWidget);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.text('Training…'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:02'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:01'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(); // let the auto-stop's async work settle

      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
      // Restored to the configured duration, not stuck at 00:00.
      expect(find.text('00:03'), findsOneWidget);
    },
  );

  testWidgets(
    'manually stopping before a running countdown expires still restores '
    'the display to the configured duration, not the mid-countdown value',
    (tester) async {
      final store = _FakeCountdownTimerStore(
        const CountdownTimerConfig(
          slotSeconds: [300, null, null],
          selectedSlot: 0,
        ),
      );
      await tester.pumpWidget(wrapTraining(countdownTimerStore: store));
      await tester.pump();

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('04:58'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(find.text('05:00'), findsOneWidget);
    },
  );

  testWidgets('manually stopping records a training-log entry with the active '
      'character set as its focus summary', (tester) async {
    final logStore = _FakeTrainingLogStore();
    await tester.pumpWidget(wrapTraining(trainingLogStore: logStore));

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(logStore.saved, hasLength(1));
    final record = logStore.saved.single;
    expect(record.focusSummary, 'A-Z');
    // Default Character Speed/Recognition Time/Extra Gap
    // (training_screen.dart's own initial field values).
    expect(record.wpm, 90);
    expect(record.recognitionTimeMs, 500);
    expect(record.extraGapMs, 0);
    // A manual stop's recorded duration is real wall-clock elapsed
    // time (morse_icr_spec.md section 22), not a virtualized Timer --
    // `tester.pump(duration)` only advances scheduled Timers/frames,
    // not `DateTime.now()`, so this only asserts it's a real,
    // non-negative measurement rather than a specific value.
    expect(record.duration, greaterThanOrEqualTo(Duration.zero));
  });

  testWidgets(
    'the log records the speed/recognition-time/gap settings in effect '
    'when Start was tapped, not just the defaults',
    (tester) async {
      final logStore = _FakeTrainingLogStore();
      await tester.pumpWidget(wrapTraining(trainingLogStore: logStore));

      final addButtons = find.byIcon(Icons.add_circle_outline);
      await tester.ensureVisible(addButtons.first);
      await tester.tap(addButtons.first); // Character Speed: 90 -> 91
      await tester.pump();
      await tester.ensureVisible(addButtons.at(1));
      await tester.tap(addButtons.at(1)); // Recognition Time: 500 -> 501
      await tester.pump();
      await tester.ensureVisible(addButtons.at(2));
      await tester.tap(addButtons.at(2)); // Extra Gap: 0 -> 1
      await tester.pump();

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();

      final record = logStore.saved.single;
      expect(record.wpm, 91);
      expect(record.recognitionTimeMs, 501);
      expect(record.extraGapMs, 1);
    },
  );

  testWidgets('a problem-character set active at Stop is recorded as the focus '
      'summary instead of the character-set chips', (tester) async {
    final logStore = _FakeTrainingLogStore();
    final problemStore = _FakeProblemCharacterStore()..saved = ['K', 'R'];
    await tester.pumpWidget(
      wrapTraining(
        trainingLogStore: logStore,
        problemCharacterStore: problemStore,
      ),
    );
    await tester.pump(); // let cold-launch problem-set activation settle

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(logStore.saved.single.focusSummary, 'K R');
  });

  testWidgets('the countdown timer reaching zero records the timer\'s full '
      'configured duration, not a wall-clock elapsed time a shade short '
      'of it', (tester) async {
    final logStore = _FakeTrainingLogStore();
    final timerStore = _FakeCountdownTimerStore(
      const CountdownTimerConfig(slotSeconds: [3, null, null], selectedSlot: 0),
    );
    await tester.pumpWidget(
      wrapTraining(trainingLogStore: logStore, countdownTimerStore: timerStore),
    );
    await tester.pump();

    await tester.ensureVisible(find.text('Start'));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(); // let the auto-stop's async work settle

    expect(logStore.saved.single.duration, const Duration(seconds: 3));
  });
}
