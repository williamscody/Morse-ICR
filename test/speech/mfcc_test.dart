import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/mfcc.dart';

import 'test_audio.dart';

void main() {
  group('extractMfcc', () {
    test('produces one 13-coefficient vector per 25ms/10ms-hop frame', () {
      const sampleRate = 16000;
      const durationSeconds = 0.5;
      final clip = sineWavePcm16(
        300,
        durationSeconds: durationSeconds,
        sampleRate: sampleRate,
      );

      final features = extractMfcc(clip, sampleRate: sampleRate);

      final sampleCount = (durationSeconds * sampleRate).toInt();
      const frameLength = 400;
      const hopLength = 160;
      final expectedFrameCount = 1 + (sampleCount - frameLength) ~/ hopLength;
      expect(features.length, expectedFrameCount);
      for (final frame in features) {
        expect(frame.length, 13);
      }
    });

    test('returns nothing for a clip shorter than one frame', () {
      final clip = sineWavePcm16(300, durationSeconds: 0.01);

      expect(extractMfcc(clip), isEmpty);
    });

    test('a low-frequency and a high-frequency tone produce measurably '
        'different feature vectors', () {
      final low = extractMfcc(sineWavePcm16(200));
      final high = extractMfcc(sineWavePcm16(3000));

      var distance = 0.0;
      for (var i = 0; i < low[0].length; i++) {
        final diff = low[0][i] - high[0][i];
        distance += diff * diff;
      }
      expect(distance, greaterThan(1.0));
    });
  });
}
