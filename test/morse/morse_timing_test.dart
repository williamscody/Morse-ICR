import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/morse/morse_timing.dart';

void main() {
  group('MorseTiming', () {
    final cases = <double, Map<String, double>>{
      40: {
        'unit': 0.030,
        'dit': 0.030,
        'dah': 0.090,
        'intra': 0.030,
        'inter': 0.090,
        'word': 0.210,
      },
      60: {
        'unit': 0.020,
        'dit': 0.020,
        'dah': 0.060,
        'intra': 0.020,
        'inter': 0.060,
        'word': 0.140,
      },
      90: {
        'unit': 0.013333333333333334,
        'dit': 0.013333333333333334,
        'dah': 0.04,
        'intra': 0.013333333333333334,
        'inter': 0.04,
        'word': 0.09333333333333334,
      },
      100: {
        'unit': 0.012,
        'dit': 0.012,
        'dah': 0.036,
        'intra': 0.012,
        'inter': 0.036,
        'word': 0.084,
      },
      120: {
        'unit': 0.010,
        'dit': 0.010,
        'dah': 0.030,
        'intra': 0.010,
        'inter': 0.030,
        'word': 0.070,
      },
      150: {
        'unit': 0.008,
        'dit': 0.008,
        'dah': 0.024,
        'intra': 0.008,
        'inter': 0.024,
        'word': 0.056,
      },
    };

    cases.forEach((wpm, expected) {
      test('$wpm WPM produces correct unit timings', () {
        final timing = MorseTiming(wpm);
        expect(timing.unitSeconds, closeTo(expected['unit']!, 1e-9));
        expect(timing.ditSeconds, closeTo(expected['dit']!, 1e-9));
        expect(timing.dahSeconds, closeTo(expected['dah']!, 1e-9));
        expect(
          timing.intraCharacterGapSeconds,
          closeTo(expected['intra']!, 1e-9),
        );
        expect(
          timing.interCharacterGapSeconds,
          closeTo(expected['inter']!, 1e-9),
        );
        expect(timing.wordGapSeconds, closeTo(expected['word']!, 1e-9));
      });
    });

    test('90 WPM matches spec example values in milliseconds', () {
      final timing = MorseTiming(90);
      expect(timing.ditSeconds * 1000, closeTo(13.333, 0.001));
      expect(timing.dahSeconds * 1000, closeTo(40.000, 0.001));
      expect(timing.intraCharacterGapSeconds * 1000, closeTo(13.333, 0.001));
      expect(timing.interCharacterGapSeconds * 1000, closeTo(40.000, 0.001));
    });
  });
}
