import 'dart:typed_data';

/// Wraps 16-bit PCM mono [samples] in a minimal WAV container.
///
/// Shared by [ToneSynthesizer] (Morse tones) and [KeepAliveAudioLoop]
/// (the background-execution keep-alive tone) so the format details
/// live in exactly one place.
Uint8List pcm16WavBytes(Int16List samples, {required int sampleRate}) {
  const bitsPerSample = 16;
  const numChannels = 1;
  final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = samples.length * 2;
  final fileSize = 36 + dataSize;

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
  writeUint16(1); // PCM
  writeUint16(numChannels);
  writeUint32(sampleRate);
  writeUint32(byteRate);
  writeUint16(blockAlign);
  writeUint16(bitsPerSample);
  writeString('data');
  writeUint32(dataSize);

  final pcmBytes = ByteData(dataSize);
  for (var i = 0; i < samples.length; i++) {
    pcmBytes.setInt16(i * 2, samples[i], Endian.little);
  }
  builder.add(pcmBytes.buffer.asUint8List());

  return builder.toBytes();
}

/// Parses the 'data' chunk of a mono 16-bit-PCM RIFF/WAVE file -- the
/// inverse of [pcm16WavBytes] -- into raw samples.
///
/// Used to pull [TtsAnswerSpeaker]'s cached answer audio (already
/// converted to this format by `convertToPcm16Wav`) back out as raw
/// samples for [TurnAudioEngine] to splice into a combined per-turn
/// buffer, and for trimming trailing silence before caching.
Int16List readPcm16Samples(Uint8List wavBytes) {
  final data = ByteData.sublistView(wavBytes);
  var offset = 12;
  while (offset + 8 <= wavBytes.length) {
    final id = String.fromCharCodes(wavBytes, offset, offset + 4);
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
  throw const FormatException('no data chunk found');
}
