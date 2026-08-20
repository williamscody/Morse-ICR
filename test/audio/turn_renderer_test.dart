import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/pcm16_wav.dart';
import 'package:morse_icr/audio/turn_renderer.dart';

void main() {
  group('renderTurn', () {
    test('bakes recognitionTime as zero-filled silence between the Morse '
        'tone and the answer', () {
      final morseSamples = Int16List.fromList([100, 200, 300]);
      final answerSamples = Int16List.fromList([400, 500]);

      final rendered = renderTurn(
        morseSamples: morseSamples,
        recognitionTime: const Duration(microseconds: 45), // 2 samples @44100Hz
        answerSamples: answerSamples,
        sampleRate: 44100,
      );

      final samples = readPcm16Samples(rendered.wavBytes);
      expect(samples, [100, 200, 300, 0, 0, 400, 500]);
    });

    test('reports morseEnd, answerStart, and totalDuration matching the '
        'sample offsets exactly', () {
      const sampleRate = 44100;
      final morseSamples = Int16List(441); // 10ms of Morse tone
      final answerSamples = Int16List(882); // 20ms of answer
      const recognitionTime = Duration(milliseconds: 50); // 2205 samples

      final rendered = renderTurn(
        morseSamples: morseSamples,
        recognitionTime: recognitionTime,
        answerSamples: answerSamples,
        sampleRate: sampleRate,
      );

      expect(rendered.timing.morseEnd, const Duration(milliseconds: 10));
      expect(rendered.timing.answerStart, const Duration(milliseconds: 60));
      expect(rendered.timing.totalDuration, const Duration(milliseconds: 80));
      expect(rendered.timing.hasAnswer, isTrue);
    });

    test('with no answer samples, the turn ends right after the '
        'recognition-time silence and hasAnswer is false', () {
      final morseSamples = Int16List(441); // 10ms
      const recognitionTime = Duration(milliseconds: 50);

      final rendered = renderTurn(
        morseSamples: morseSamples,
        recognitionTime: recognitionTime,
        sampleRate: 44100,
      );

      expect(rendered.timing.hasAnswer, isFalse);
      expect(rendered.timing.answerStart, rendered.timing.totalDuration);
      final samples = readPcm16Samples(rendered.wavBytes);
      expect(samples.length, 441 + 2205);
    });

    test('a zero recognitionTime bakes no silence at all', () {
      final morseSamples = Int16List.fromList([1, 2, 3]);
      final answerSamples = Int16List.fromList([4, 5]);

      final rendered = renderTurn(
        morseSamples: morseSamples,
        recognitionTime: Duration.zero,
        answerSamples: answerSamples,
        sampleRate: 44100,
      );

      expect(rendered.timing.morseEnd, rendered.timing.answerStart);
      final samples = readPcm16Samples(rendered.wavBytes);
      expect(samples, [1, 2, 3, 4, 5]);
    });
  });
}
