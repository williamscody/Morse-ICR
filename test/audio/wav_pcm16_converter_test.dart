import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/audio/wav_pcm16_converter.dart';

/// Builds a minimal RIFF/WAVE file with a 'fmt ' and 'data' chunk, for
/// tests to feed into [convertToPcm16Wav] without needing a real
/// flutter_tts-rendered file on disk.
Uint8List _buildWav({
  required int formatTag,
  required int sampleRate,
  required int bitsPerSample,
  required Uint8List data,
}) {
  const numChannels = 1;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final fileSize = 36 + data.length;

  final builder = BytesBuilder();
  void writeString(String s) => builder.add(s.codeUnits);
  void writeUint32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  void writeUint16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  writeString('RIFF');
  writeUint32(fileSize);
  writeString('WAVE');
  writeString('fmt ');
  writeUint32(16);
  writeUint16(formatTag);
  writeUint16(numChannels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeString('data');
  writeUint32(data.length);
  builder.add(data);
  return builder.toBytes();
}

Uint8List _float32Data(List<double> samples) {
  final bytes = ByteData(samples.length * 4);
  for (var i = 0; i < samples.length; i++) {
    bytes.setFloat32(i * 4, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List _int16Data(List<int> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Parses back the samples of a WAV produced by [pcm16WavBytes]
/// (16-bit PCM, mono), for asserting on [convertToPcm16Wav]'s output.
Int16List _readPcm16Samples(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav, offset, offset + 4);
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    if (id == 'data') {
      final samples = Int16List(size ~/ 2);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = data.getInt16(start + i * 2, Endian.little);
      }
      return samples;
    }
    offset = start + size + (size.isOdd ? 1 : 0);
  }
  throw StateError('no data chunk found');
}

void main() {
  group('convertToPcm16Wav', () {
    test('converts 32-bit float PCM samples to 16-bit at the same rate', () {
      final input = _buildWav(
        formatTag: 3, // IEEE float
        sampleRate: 44100,
        bitsPerSample: 32,
        data: _float32Data([0.0, 0.5, -0.5, 1.0, -1.0]),
      );

      final output = convertToPcm16Wav(input, targetSampleRate: 44100);
      final samples = _readPcm16Samples(output);

      expect(samples.length, 5);
      expect(samples[0], 0);
      expect(samples[1], closeTo(16384, 2));
      expect(samples[2], closeTo(-16384, 2));
      expect(samples[3], 32767);
      expect(samples[4], closeTo(-32767, 2));
    });

    test('leaves already-16-bit-PCM-at-target-rate samples unchanged', () {
      final input = _buildWav(
        formatTag: 1, // PCM
        sampleRate: 44100,
        bitsPerSample: 16,
        data: _int16Data([100, -100, 32000, -32000]),
      );

      final output = convertToPcm16Wav(input, targetSampleRate: 44100);
      final samples = _readPcm16Samples(output);

      // Round-trips through a normalized float (see convertToPcm16Wav's
      // shared conversion path for the 32-bit-float case), so exact
      // equality isn't guaranteed -- within 1 of the original is.
      expect(samples.length, 4);
      const expected = [100, -100, 32000, -32000];
      for (var i = 0; i < samples.length; i++) {
        expect(samples[i], closeTo(expected[i], 1));
      }
    });

    test('resamples to the target rate, changing the sample count', () {
      // 10 samples at 22050Hz resampled to 44100Hz should produce
      // roughly twice as many samples.
      final input = _buildWav(
        formatTag: 3,
        sampleRate: 22050,
        bitsPerSample: 32,
        data: _float32Data(List.generate(10, (i) => i / 10)),
      );

      final output = convertToPcm16Wav(input, targetSampleRate: 44100);
      final samples = _readPcm16Samples(output);

      expect(samples.length, closeTo(20, 2));
    });

    test('throws FormatException for a non-WAV input', () {
      expect(
        () => convertToPcm16Wav(Uint8List.fromList([1, 2, 3, 4])),
        throwsFormatException,
      );
    });

    test('throws FormatException for stereo input', () {
      final builder = BytesBuilder();
      void writeString(String s) => builder.add(s.codeUnits);
      void writeUint32(int v) {
        final b = ByteData(4)..setUint32(0, v, Endian.little);
        builder.add(b.buffer.asUint8List());
      }

      void writeUint16(int v) {
        final b = ByteData(2)..setUint16(0, v, Endian.little);
        builder.add(b.buffer.asUint8List());
      }

      final data = _int16Data([0, 0, 0, 0]);
      writeString('RIFF');
      writeUint32(36 + data.length);
      writeString('WAVE');
      writeString('fmt ');
      writeUint32(16);
      writeUint16(1);
      writeUint16(2); // stereo
      writeUint32(44100);
      writeUint32(44100 * 2 * 2);
      writeUint16(4);
      writeUint16(16);
      writeString('data');
      writeUint32(data.length);
      builder.add(data);

      expect(
        () => convertToPcm16Wav(builder.toBytes()),
        throwsFormatException,
      );
    });
  });
}
