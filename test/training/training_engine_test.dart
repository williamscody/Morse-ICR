import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/turn_player.dart';
import 'package:morse_icr/morse/morse_event.dart';
import 'package:morse_icr/training/training_engine.dart';

const _recognitionTime = Duration(milliseconds: 20);

Duration _characterDuration(String character, double wpm) {
  final seconds = morseElementsForCharacter(
    character,
    wpm,
  ).fold<double>(0, (sum, e) => sum + e.durationSeconds);
  return Duration(microseconds: (seconds * 1e6).round());
}

/// The [TurnTiming] a real [TurnAudioEngine] would produce for
/// [character] at [wpm] with [recognitionTime] of silence, [extraGap] of
/// leading silence, and no cached answer -- fakes below use this so
/// submitResponse's "beat the computer" window and the loop's own pacing
/// behave exactly as they would against real Morse timing, without
/// needing real audio.
TurnTiming _timingFor(
  String character,
  double wpm,
  Duration recognitionTime, {
  Duration extraGap = Duration.zero,
}) {
  final morseEnd = extraGap + _characterDuration(character, wpm);
  final answerStart = morseEnd + recognitionTime;
  return TurnTiming(
    morseEnd: morseEnd,
    answerStart: answerStart,
    totalDuration: answerStart,
    hasAnswer: false,
  );
}

void main() {
  group('TrainingEngine', () {
    test('throws when starting with an empty character set', () {
      final engine = TrainingEngine(turnPlayer: _RecordingPlayer());
      expect(
        () => engine.start(
          characters: const [],
          wpm: 90,
          recognitionTime: _recognitionTime,
        ),
        throwsArgumentError,
      );
      expect(engine.isRunning, isFalse);
    });

    test(
      'generates and plays characters from the active set while running',
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(turnPlayer: player);

        engine.start(
          characters: const ['E'],
          wpm: 150,
          recognitionTime: _recognitionTime,
        );
        expect(engine.isRunning, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 150));
        await engine.stop();

        expect(engine.isRunning, isFalse);
        expect(player.played, isNotEmpty);
        expect(player.played, everyElement('E'));
      },
    );

    test('stop halts further character generation', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      final countAfterStop = player.played.length;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(player.played.length, countAfterStop);
    });

    test('onCharacterGenerated fires for each generated character', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final generated = <String>[];
      engine.onCharacterGenerated = generated.add;

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      expect(generated, isNotEmpty);
      expect(generated.length, player.played.length);
    });

    test('a playback failure does not stop the training loop', () async {
      final player = _ThrowingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      expect(player.callCount, greaterThan(1));
    });

    test('calling start while already running has no effect', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      engine.start(
        characters: const ['A', 'B'],
        wpm: 40,
        recognitionTime: _recognitionTime,
      ); // ignored

      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      expect(player.played, everyElement('E'));
    });

    test('selects only from the provided character set', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      const characters = ['A', 'B', 'C'];

      engine.start(
        characters: characters,
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await engine.stop();

      expect(player.played, isNotEmpty);
      for (final character in player.played) {
        expect(characters, contains(character));
      }
    });

    test(
      'updateSettings changes the wpm used for characters generated afterward',
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(turnPlayer: player);

        engine.start(
          characters: const ['E'],
          wpm: 40,
          recognitionTime: _recognitionTime,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        engine.updateSettings(wpm: 150);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await engine.stop();

        expect(player.wpms, contains(40));
        expect(player.wpms, contains(150));
      },
    );

    test('updateSettings changes recognitionTime for the gap between '
        'characters generated afterward', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final fastCount = player.played.length;

      engine.updateSettings(recognitionTime: const Duration(milliseconds: 200));
      player.played.clear();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await engine.stop();

      expect(fastCount, greaterThan(player.played.length));
    });

    test('updateSettings changes extraGap for the gap between characters '
        'generated afterward, same as recognitionTime', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final noGapCount = player.played.length;

      engine.updateSettings(extraGap: const Duration(milliseconds: 200));
      player.played.clear();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await engine.stop();

      expect(noGapCount, greaterThan(player.played.length));
    });

    test('onRecognitionTimeout fires once per character once its recognition '
        'deadline expires', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final timedOut = <String>[];
      engine.onRecognitionTimeout = (c) async => timedOut.add(c);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      expect(timedOut, isNotEmpty);
      expect(timedOut, everyElement('E'));
      // stop() can land mid-turn-wait for the most recently played
      // character, cancelling its timer before it expires, so timedOut
      // may trail played by at most one.
      expect(timedOut.length, greaterThanOrEqualTo(player.played.length - 1));
      expect(timedOut.length, lessThanOrEqualTo(player.played.length));
    });

    test('onRecognitionTimeout only fires after that character has finished '
        'playing (morse_icr_spec.md section 29)', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final events = <String>[];
      engine.onCharacterGenerated = (c) => events.add('generated:$c');
      engine.onRecognitionTimeout = (c) async => events.add('timeout:$c');

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      // Each timeout must be preceded by a generation of the same
      // character, and playback (awaited synchronously in the fake
      // player before generation of the *next* character) always
      // completes before the turn's own total-duration wait -- and
      // therefore its timeout -- can elapse.
      expect(events.first, startsWith('generated:'));
      for (var i = 0; i < events.length; i++) {
        if (events[i].startsWith('timeout:')) {
          expect(events[i - 1], 'generated:${events[i].split(':')[1]}');
        }
      }
    });

    test('stopping mid-recognition-wait does not fire onRecognitionTimeout '
        'for the in-progress character', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final timedOut = <String>[];
      engine.onRecognitionTimeout = (c) async => timedOut.add(c);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 200),
      );
      // Stop well within the recognition window so the pending timer is
      // cancelled rather than left to fire.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final countBeforeStop = timedOut.length;
      await engine.stop();

      expect(timedOut.length, countBeforeStop);

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(timedOut.length, countBeforeStop);
    });

    test('the next character does not start until onRecognitionTimeout\'s '
        'future completes', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final releaseHook = Completer<void>();
      engine.onRecognitionTimeout = (_) => releaseHook.future;

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Only the first character should have played -- the hook for
      // it is still pending, so the loop must be blocked before the
      // second character.
      expect(player.played.length, 1);

      releaseHook.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.played.length, greaterThan(1));

      await engine.stop();
    });

    test('submitResponse fires onCorrectResponse when it matches the '
        'awaited character, without suppressing onRecognitionTimeout -- '
        'the computer still announces the answer regardless (kept on for '
        'debugging pending a future settings toggle)', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final correct = <String>[];
      final timedOut = <String>[];
      engine.onCorrectResponse = correct.add;
      engine.onRecognitionTimeout = (c) async => timedOut.add(c);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 20),
      );
      // After 'E's own ~8ms audio duration (so the recognition window
      // has actually opened) but before its 20ms deadline.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      engine.submitResponse('E');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await engine.stop();

      expect(correct, isNotEmpty);
      expect(correct, everyElement('E'));
      expect(timedOut, isNotEmpty);
    });

    test('submitResponse only fires onCorrectResponse once per character, '
        'even if called again before the deadline expires', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final correct = <String>[];
      engine.onCorrectResponse = correct.add;

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 200),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      engine.submitResponse('E');
      engine.submitResponse('E');
      engine.submitResponse('E');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await engine.stop();

      expect(correct.length, 1);
    });

    test('submitResponse with a character that does not match the awaited '
        'one is ignored, leaving the deadline to expire normally', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final correct = <String>[];
      final timedOut = <String>[];
      engine.onCorrectResponse = correct.add;
      engine.onRecognitionTimeout = (c) async => timedOut.add(c);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      engine.submitResponse('Z');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.stop();

      expect(correct, isEmpty);
      expect(timedOut, isNotEmpty);
    });

    test(
      'submitResponse does not fire onCorrectResponse once the recognition '
      'deadline has passed, even if the response arrives before the next '
      "character supersedes it -- a late response didn't beat the computer",
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(turnPlayer: player);
        final correct = <String>[];
        engine.onCorrectResponse = correct.add;

        // wpm=40 makes 'E' (one dit) ~30ms, so the window opens at
        // ~30ms and closes (deadline) at ~30+40=70ms; the next
        // character's own audio+wait don't reopen it again until
        // ~70+30=100ms. 85ms sits comfortably in between -- after the
        // deadline, before the next character.
        engine.start(
          characters: const ['E'],
          wpm: 40,
          recognitionTime: const Duration(milliseconds: 40),
        );
        await Future<void>.delayed(const Duration(milliseconds: 85));
        engine.submitResponse('E');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await engine.stop();

        expect(correct, isEmpty);
      },
    );

    test(
      'submitResponse when no recognition deadline is running is a no-op',
      () {
        final engine = TrainingEngine(turnPlayer: _RecordingPlayer());
        final correct = <String>[];
        engine.onCorrectResponse = correct.add;

        // Never started -- no turn has ever played.
        engine.submitResponse('E');

        expect(correct, isEmpty);
      },
    );

    test('pre-fetches the next character during the recognition-time wait '
        'and plays it via playPrepared instead of playTurn', () async {
      final player = _PrefetchingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 30),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await engine.stop();

      // The very first character has nothing prepared yet, so it
      // must go through the cold path -- every character after that
      // should have been prepared ahead of time and played via
      // playPrepared.
      expect(player.playedCold, ['E']);
      expect(player.playedPrepared, isNotEmpty);
      expect(player.playedPrepared, everyElement('E'));
      // stop() can land right as the final pre-fetch for this
      // iteration finishes but before the loop gets back around to
      // consume it, so prepared may lead playedPrepared by at most
      // one (same tolerance as the onRecognitionTimeout test above).
      expect(
        player.prepared.length,
        inInclusiveRange(
          player.playedPrepared.length,
          player.playedPrepared.length + 1,
        ),
      );
    });

    test('stop() cancels a character that was prepared but not yet played, '
        'so it can never be played later', () async {
      final player = _PrefetchingPlayer();
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 300),
      );
      // Let the first character play (and its prepare-ahead for the
      // next one complete) before stopping mid-recognition-wait --
      // well before that prepared character is ever consumed.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(player.prepared, isNotEmpty);
      await engine.stop();
      // stop()'s cancelPrepared() call is fire-and-forget.
      await Future<void>.delayed(Duration.zero);

      expect(await player.playPrepared(), isNull);
    });

    test('stop() landing while a prepare-ahead is still in flight never '
        'lets the loop play that superseded character afterward '
        '(confirmed on-device: this previously wedged Stop/Start)', () async {
      final player = _PrefetchingPlayer()
        ..prepareDelay = const Duration(milliseconds: 100);
      final engine = TrainingEngine(turnPlayer: player);

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: const Duration(milliseconds: 10),
      );
      // The first character plays cold and its own totalDuration
      // (morse tone + 10ms recognition) is much shorter than
      // prepareDelay, so by the time the loop is back at the top of
      // its next iteration, the prepare-ahead kicked off for the
      // second character is still in flight -- stop() lands squarely
      // inside the loop's `await prepareFuture`.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await engine.stop();

      // stop() itself doesn't return until _runLoop has actually
      // exited -- which, since prepareFuture hadn't resolved yet when
      // stop() was called, means _runLoop was still awaiting it when
      // stop() returned. Only one character should ever have been
      // played: the initial cold one. Waiting past prepareDelay here
      // confirms the loop didn't play a second, superseded one once
      // that prepare finally resolved.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(player.playedCold.length + player.playedPrepared.length, 1);
    });

    test(
      'falls back to playTurn when nothing was successfully prepared in time',
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(turnPlayer: player);

        engine.start(
          characters: const ['E'],
          wpm: 150,
          recognitionTime: _recognitionTime,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await engine.stop();

        // _RecordingPlayer doesn't override prepareTurn/playPrepared, so
        // it inherits TurnPlayer's no-op defaults -- every character,
        // not just the first, must still end up played via the cold
        // path.
        expect(player.played, isNotEmpty);
        expect(player.played, everyElement('E'));
      },
    );

    test(
      'a longer recognitionTime widens the gap between characters',
      () async {
        final fastPlayer = _RecordingPlayer();
        final fastEngine = TrainingEngine(turnPlayer: fastPlayer);
        fastEngine.start(
          characters: const ['E'],
          wpm: 150,
          recognitionTime: const Duration(milliseconds: 5),
        );

        final slowPlayer = _RecordingPlayer();
        final slowEngine = TrainingEngine(turnPlayer: slowPlayer);
        slowEngine.start(
          characters: const ['E'],
          wpm: 150,
          recognitionTime: const Duration(milliseconds: 200),
        );

        await Future<void>.delayed(const Duration(milliseconds: 150));
        await fastEngine.stop();
        await slowEngine.stop();

        expect(fastPlayer.played.length, greaterThan(slowPlayer.played.length));
      },
    );

    test('isVoiceEnabled false suppresses onRecognitionTimeout for turns '
        'generated while it was off', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(turnPlayer: player);
      final timedOut = <String>[];
      engine.onRecognitionTimeout = (c) async => timedOut.add(c);
      engine.isVoiceEnabled = () => false;

      engine.start(
        characters: const ['E'],
        wpm: 150,
        recognitionTime: _recognitionTime,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await engine.stop();

      expect(player.played, isNotEmpty);
      expect(timedOut, isEmpty);
    });
  });
}

class _RecordingPlayer extends TurnPlayer {
  final List<String> played = [];
  final List<double> wpms = [];

  @override
  Future<TurnTiming> playTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) async {
    played.add(character);
    wpms.add(wpm);
    return _timingFor(character, wpm, recognitionTime, extraGap: extraGap);
  }
}

class _ThrowingPlayer extends TurnPlayer {
  int callCount = 0;

  @override
  Future<TurnTiming> playTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) async {
    callCount++;
    throw Exception('playback failed');
  }
}

/// Unlike [_RecordingPlayer], actually implements the prepare-ahead
/// contract, so tests here can verify TrainingEngine uses it instead of
/// always falling back to [TurnPlayer.playTurn].
class _PrefetchingPlayer extends TurnPlayer {
  final List<String> prepared = [];
  final List<String> playedPrepared = [];
  final List<String> playedCold = [];
  // Lets tests land stop() while prepareTurn is still in flight, to
  // reproduce the "Stop lands mid-prepare" hang (confirmed on-device).
  Duration prepareDelay = Duration.zero;
  String? _readyCharacter;
  double? _readyWpm;
  Duration? _readyRecognitionTime;

  @override
  Future<void> prepareTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) async {
    if (prepareDelay > Duration.zero) {
      await Future<void>.delayed(prepareDelay);
    }
    prepared.add(character);
    _readyCharacter = character;
    _readyWpm = wpm;
    _readyRecognitionTime = recognitionTime;
  }

  @override
  Future<TurnTiming?> playPrepared() async {
    final character = _readyCharacter;
    if (character == null) return null;
    final wpm = _readyWpm!;
    final recognitionTime = _readyRecognitionTime!;
    _readyCharacter = null;
    playedPrepared.add(character);
    return _timingFor(character, wpm, recognitionTime);
  }

  @override
  Future<TurnTiming> playTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) async {
    playedCold.add(character);
    return _timingFor(character, wpm, recognitionTime);
  }

  @override
  Future<void> cancelPrepared() async {
    _readyCharacter = null;
  }
}
