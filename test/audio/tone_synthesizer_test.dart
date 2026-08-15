import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/tone_synthesizer.dart';
import 'package:morse_icr/morse/morse_event.dart';

void main() {
  group('ToneSynthesizer', () {
    test('produces a valid 16-bit PCM WAV header', () {
      const synth = ToneSynthesizer(sampleRate: 8000);
      final elements = [
        const MorseElement(toneOn: true, durationSeconds: 0.02),
      ];
      final bytes = synth.synthesizeWav(elements);
      final data = bytes.buffer.asByteData();

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
      expect(data.getUint16(20, Endian.little), 1); // PCM format
      expect(data.getUint16(22, Endian.little), 1); // mono
      expect(data.getUint32(24, Endian.little), 8000); // sample rate
      expect(data.getUint16(34, Endian.little), 16); // bits per sample
    });

    test('data chunk size matches expected sample count', () {
      const sampleRate = 8000;
      const synth = ToneSynthesizer(sampleRate: sampleRate);
      final elements = [
        const MorseElement(toneOn: true, durationSeconds: 0.01),
        const MorseElement(toneOn: false, durationSeconds: 0.01),
      ];
      final bytes = synth.synthesizeWav(elements);
      final data = bytes.buffer.asByteData();

      final expectedSamples =
          (0.01 * sampleRate).round() + (0.01 * sampleRate).round();
      final expectedDataSize = expectedSamples * 2; // 16-bit = 2 bytes
      expect(data.getUint32(40, Endian.little), expectedDataSize);
      expect(bytes.length, 44 + expectedDataSize);
    });

    test('silence segments produce zero-amplitude samples', () {
      const sampleRate = 8000;
      const synth = ToneSynthesizer(sampleRate: sampleRate);
      final elements = [
        const MorseElement(toneOn: false, durationSeconds: 0.01),
      ];
      final bytes = synth.synthesizeWav(elements);
      final pcm = ByteData.sublistView(bytes, 44);

      for (var i = 0; i < pcm.lengthInBytes; i += 2) {
        expect(pcm.getInt16(i, Endian.little), 0);
      }
    });

    test('tone segment reaches close to full amplitude away from ramps', () {
      const sampleRate = 44100;
      const amplitude = 0.6;
      const synth = ToneSynthesizer(
        sampleRate: sampleRate,
        amplitude: amplitude,
        rampSeconds: 0.001,
      );
      final elements = [
        const MorseElement(toneOn: true, durationSeconds: 0.02),
      ];
      final bytes = synth.synthesizeWav(elements);
      final pcm = ByteData.sublistView(bytes, 44);

      // Peak amplitude across the segment should get close to full scale
      // away from the ramps (a single mid-sample can land near a
      // zero-crossing, so check the max over the whole buffer instead).
      var peakValue = 0;
      for (var i = 0; i < pcm.lengthInBytes; i += 2) {
        final value = pcm.getInt16(i, Endian.little).abs();
        if (value > peakValue) peakValue = value;
      }
      final expectedPeak = (amplitude * 32767).round();

      expect(peakValue, greaterThan((expectedPeak * 0.9).round()));
    });
  });
}
