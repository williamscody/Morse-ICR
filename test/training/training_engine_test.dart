import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/morse_character_player.dart';
import 'package:morse_icr/training/training_engine.dart';

const _recognitionTime = Duration(milliseconds: 20);

void main() {
  group('TrainingEngine', () {
    test('throws when starting with an empty character set', () {
      final engine = TrainingEngine(audioPlayer: _RecordingPlayer());
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
        final engine = TrainingEngine(audioPlayer: player);

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
      final engine = TrainingEngine(audioPlayer: player);

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
      final engine = TrainingEngine(audioPlayer: player);
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
      final engine = TrainingEngine(audioPlayer: player);

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
      final engine = TrainingEngine(audioPlayer: player);

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
      final engine = TrainingEngine(audioPlayer: player);
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
        final engine = TrainingEngine(audioPlayer: player);

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

    test(
      'updateSettings changes recognitionTime for the gap between '
      'characters generated afterward',
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(audioPlayer: player);

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
      },
    );

    test(
      'onRecognitionTimeout fires once per character once its recognition '
      'deadline expires',
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(audioPlayer: player);
        final timedOut = <String>[];
        engine.onRecognitionTimeout = timedOut.add;

        engine.start(
          characters: const ['E'],
          wpm: 150,
          recognitionTime: _recognitionTime,
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await engine.stop();

        expect(timedOut, isNotEmpty);
        expect(timedOut, everyElement('E'));
        // stop() can land mid-recognition-wait for the most recently
        // played character, cancelling its timer before it expires, so
        // timedOut may trail played by at most one.
        expect(timedOut.length, greaterThanOrEqualTo(player.played.length - 1));
        expect(timedOut.length, lessThanOrEqualTo(player.played.length));
      },
    );

    test(
      'onRecognitionTimeout only fires after that character has finished '
      'playing (morse_icr_spec.md section 29)',
      () async {
        final player = _RecordingPlayer();
        final engine = TrainingEngine(audioPlayer: player);
        final events = <String>[];
        engine.onCharacterGenerated = (c) => events.add('generated:$c');
        engine.onRecognitionTimeout = (c) => events.add('timeout:$c');

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
        // completes before the recognition timer -- and therefore its
        // timeout -- can start.
        expect(events.first, startsWith('generated:'));
        for (var i = 0; i < events.length; i++) {
          if (events[i].startsWith('timeout:')) {
            expect(events[i - 1], 'generated:${events[i].split(':')[1]}');
          }
        }
      },
    );

    test('stopping mid-recognition-wait does not fire onRecognitionTimeout '
        'for the in-progress character', () async {
      final player = _RecordingPlayer();
      final engine = TrainingEngine(audioPlayer: player);
      final timedOut = <String>[];
      engine.onRecognitionTimeout = timedOut.add;

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

    test(
      'a longer recognitionTime widens the gap between characters',
      () async {
        final fastPlayer = _RecordingPlayer();
        final fastEngine = TrainingEngine(audioPlayer: fastPlayer);
        fastEngine.start(
          characters: const ['E'],
          wpm: 150,
          recognitionTime: const Duration(milliseconds: 5),
        );

        final slowPlayer = _RecordingPlayer();
        final slowEngine = TrainingEngine(audioPlayer: slowPlayer);
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
  });
}

class _RecordingPlayer implements MorseCharacterPlayer {
  final List<String> played = [];
  final List<double> wpms = [];

  @override
  Future<void> playCharacter(String character, double wpm) async {
    played.add(character);
    wpms.add(wpm);
  }
}

class _ThrowingPlayer implements MorseCharacterPlayer {
  int callCount = 0;

  @override
  Future<void> playCharacter(String character, double wpm) async {
    callCount++;
    throw Exception('playback failed');
  }
}
