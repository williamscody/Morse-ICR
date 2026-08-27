import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/utterance_endpointer.dart';

const _chunkDuration = Duration(milliseconds: 100);

Uint8List _chunk(int peakAmplitude) {
  final bytes = ByteData(2);
  bytes.setInt16(0, peakAmplitude, Endian.little);
  return bytes.buffer.asUint8List();
}

void main() {
  group('UtteranceEndpointer', () {
    late UtteranceEndpointer endpointer;

    setUp(() {
      endpointer = UtteranceEndpointer(
        speechThreshold: 1000,
        hangoverDuration: const Duration(milliseconds: 300),
        minUtteranceDuration: const Duration(milliseconds: 150),
        maxUtteranceDuration: const Duration(milliseconds: 800),
      );
    });

    test('silence never starts an utterance', () {
      for (var i = 0; i < 10; i++) {
        expect(endpointer.addChunk(_chunk(0), _chunkDuration), isNull);
      }
    });

    test('a speech burst followed by enough silence emits an utterance '
        'trimmed of the trailing (hangover) silence', () {
      // Three loud chunks (300ms of "speech") ...
      expect(endpointer.addChunk(_chunk(5000), _chunkDuration), isNull);
      expect(endpointer.addChunk(_chunk(5000), _chunkDuration), isNull);
      expect(endpointer.addChunk(_chunk(5000), _chunkDuration), isNull);
      // ... then silence: hangoverDuration is 300ms, so the 3rd silent
      // chunk (300ms accumulated) is what triggers the endpoint.
      expect(endpointer.addChunk(_chunk(0), _chunkDuration), isNull);
      expect(endpointer.addChunk(_chunk(0), _chunkDuration), isNull);
      final utterance = endpointer.addChunk(_chunk(0), _chunkDuration);

      expect(utterance, isNotNull);
      // The hangover exists to *detect* the endpoint -- once detected,
      // that trailing silence isn't part of the word, so only the 3
      // speech chunks are kept.
      expect(utterance!.length, 3 * _chunk(0).length);
    });

    test('a blip shorter than minUtteranceDuration is discarded as '
        'noise', () {
      // A hangover-triggered end is always at least hangoverDuration
      // long, so exercising the "too short" path needs
      // minUtteranceDuration set above that floor -- otherwise nothing
      // a hangover-triggered end produces could ever be "too short".
      final strict = UtteranceEndpointer(
        speechThreshold: 1000,
        hangoverDuration: const Duration(milliseconds: 300),
        minUtteranceDuration: const Duration(milliseconds: 500),
        maxUtteranceDuration: const Duration(milliseconds: 800),
      );

      // 1 speech chunk + 3 silent (hangover) chunks = 400ms, under the
      // 500ms minimum.
      expect(strict.addChunk(_chunk(5000), _chunkDuration), isNull);
      expect(strict.addChunk(_chunk(0), _chunkDuration), isNull);
      expect(strict.addChunk(_chunk(0), _chunkDuration), isNull);
      final result = strict.addChunk(_chunk(0), _chunkDuration);

      expect(result, isNull);
    });

    test('continuous loud input force-ends at maxUtteranceDuration', () {
      // maxUtteranceDuration is 800ms -> the 8th 100ms chunk of
      // unbroken speech should force an endpoint even with no silence.
      for (var i = 0; i < 7; i++) {
        expect(endpointer.addChunk(_chunk(5000), _chunkDuration), isNull);
      }
      final utterance = endpointer.addChunk(_chunk(5000), _chunkDuration);

      expect(utterance, isNotNull);
      expect(utterance!.length, 8 * _chunk(0).length);
    });

    test('reset discards an in-progress utterance without affecting the '
        'next one', () {
      endpointer.addChunk(_chunk(5000), _chunkDuration);
      endpointer.addChunk(_chunk(5000), _chunkDuration);

      endpointer.reset();

      // A fresh utterance after reset behaves exactly like the first
      // test's from-silence case, unaffected by the discarded one.
      expect(endpointer.addChunk(_chunk(5000), _chunkDuration), isNull);
      expect(endpointer.addChunk(_chunk(0), _chunkDuration), isNull);
      expect(endpointer.addChunk(_chunk(0), _chunkDuration), isNull);
      final utterance = endpointer.addChunk(_chunk(0), _chunkDuration);

      expect(utterance, isNotNull);
      // 1 speech chunk, trailing (hangover) silence trimmed off.
      expect(utterance!.length, 1 * _chunk(0).length);
    });

    test('audio immediately before speech crosses the threshold is kept '
        'as pre-roll', () {
      final withPreRoll = UtteranceEndpointer(
        speechThreshold: 1000,
        hangoverDuration: const Duration(milliseconds: 300),
        minUtteranceDuration: const Duration(milliseconds: 50),
        maxUtteranceDuration: const Duration(milliseconds: 800),
        preRollDuration: const Duration(milliseconds: 200),
      );

      // Two quiet chunks (200ms), entirely within preRollDuration ...
      expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      // ... then a loud chunk crosses the threshold ...
      expect(withPreRoll.addChunk(_chunk(5000), _chunkDuration), isNull);
      // ... then enough silence to end it.
      expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      final utterance = withPreRoll.addChunk(_chunk(0), _chunkDuration);

      expect(utterance, isNotNull);
      // The 2 pre-roll chunks plus the 1 speech chunk -- trailing
      // silence trimmed off as in the tests above.
      expect(utterance!.length, 3 * _chunk(0).length);
    });

    test('pre-roll only keeps audio within preRollDuration, discarding '
        'anything further back', () {
      final withPreRoll = UtteranceEndpointer(
        speechThreshold: 1000,
        hangoverDuration: const Duration(milliseconds: 300),
        minUtteranceDuration: const Duration(milliseconds: 50),
        maxUtteranceDuration: const Duration(milliseconds: 800),
        preRollDuration: const Duration(milliseconds: 150),
      );

      // 5 quiet chunks (500ms) -- far more than preRollDuration (150ms).
      for (var i = 0; i < 5; i++) {
        expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      }
      expect(withPreRoll.addChunk(_chunk(5000), _chunkDuration), isNull);
      expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      expect(withPreRoll.addChunk(_chunk(0), _chunkDuration), isNull);
      final utterance = withPreRoll.addChunk(_chunk(0), _chunkDuration);

      expect(utterance, isNotNull);
      // Only the most recent 100ms pre-roll chunk (closest whole chunk
      // to the 150ms window) plus the 1 speech chunk survive.
      expect(utterance!.length, 2 * _chunk(0).length);
    });

    test('onSpeechStarted fires exactly once, at the first speech chunk '
        'of an utterance', () {
      var calls = 0;
      endpointer.onSpeechStarted = () => calls++;

      endpointer.addChunk(_chunk(0), _chunkDuration);
      expect(calls, 0, reason: 'silence should never trigger it');
      endpointer.addChunk(_chunk(5000), _chunkDuration);
      expect(calls, 1, reason: 'the first speech chunk starts the utterance');
      endpointer.addChunk(_chunk(5000), _chunkDuration);
      expect(calls, 1, reason: 'later chunks of the same utterance should not');
    });

    test('onSpeechStarted fires again for the next utterance once the '
        'previous one ends', () {
      var calls = 0;
      endpointer.onSpeechStarted = () => calls++;

      endpointer.addChunk(_chunk(5000), _chunkDuration);
      endpointer.addChunk(_chunk(0), _chunkDuration);
      endpointer.addChunk(_chunk(0), _chunkDuration);
      endpointer.addChunk(_chunk(0), _chunkDuration);
      expect(calls, 1);

      endpointer.addChunk(_chunk(5000), _chunkDuration);
      expect(calls, 2);
    });
  });
}
