import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/pcm16_wav.dart';

void main() {
  group('readPcm16Samples', () {
    test('round-trips samples written by pcm16WavBytes', () {
      final samples = Int16List.fromList([0, 100, -100, 32767, -32768]);

      final wav = pcm16WavBytes(samples, sampleRate: 44100);

      expect(readPcm16Samples(wav), samples);
    });

    test('round-trips an empty sample list', () {
      final samples = Int16List(0);

      final wav = pcm16WavBytes(samples, sampleRate: 44100);

      expect(readPcm16Samples(wav), isEmpty);
    });

    test('throws FormatException when no data chunk is present', () {
      final bogus = Uint8List.fromList('RIFF0000WAVEfmt '.codeUnits);

      expect(() => readPcm16Samples(bogus), throwsFormatException);
    });
  });
}
