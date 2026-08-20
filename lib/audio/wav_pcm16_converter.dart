import 'dart:typed_data';

import 'pcm16_wav.dart';

/// Re-encodes an arbitrary PCM WAV file's bytes as 16-bit PCM at
/// [targetSampleRate], matching [pcm16WavBytes]'s own format.
///
/// Written specifically for `package:flutter_tts`'s `synthesizeToFile`
/// output: reading its native iOS implementation
/// (`SwiftFlutterTtsPlugin.swift`) shows it writes 32-bit IEEE-float PCM
/// at `AVSpeechSynthesizer`'s own native sample rate (not 44.1kHz) --
/// a structurally different, larger-per-sample format from the 16-bit
/// PCM/44.1kHz WAV this app's own [ToneSynthesizer] and
/// [KeepAliveAudioLoop] already produce. On-device measurement found
/// `AudioPlayer.play()`'s own native acknowledgment latency for TTS
/// answer audio was consistently 600-1000ms+ -- uncorrelated with
/// spoken-word length or whether the phone was locked, unlike Morse
/// audio's own play() latency -- pointing at this format mismatch
/// itself, not background throttling, as the cause. Converting once at
/// pre-render time (not per playback) means every actual `speak()` call
/// plays the same efficient format Morse audio already does.
///
/// Only handles what flutter_tts actually produces: mono, 16- or
/// 32-bit, PCM or IEEE-float. Throws [FormatException] on anything
/// else (a compressed format, multi-channel, etc.) -- callers should
/// fall back to playing the original bytes rather than silently
/// producing garbled audio from a format this wasn't written for.
Uint8List convertToPcm16Wav(Uint8List bytes, {int targetSampleRate = 44100}) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WAVE') {
    throw const FormatException('Not a RIFF/WAVE file');
  }

  int? formatTag;
  int? numChannels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataLength;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes, offset, offset + 4);
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkDataStart = offset + 8;
    if (chunkId == 'fmt ') {
      formatTag = data.getUint16(chunkDataStart, Endian.little);
      numChannels = data.getUint16(chunkDataStart + 2, Endian.little);
      sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
      bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
    } else if (chunkId == 'data') {
      dataOffset = chunkDataStart;
      dataLength = chunkSize;
    }
    // Chunks are padded to even byte boundaries.
    offset = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (formatTag == null ||
      numChannels == null ||
      sampleRate == null ||
      bitsPerSample == null ||
      dataOffset == null ||
      dataLength == null) {
    throw const FormatException('Missing fmt or data chunk');
  }
  if (numChannels != 1) {
    throw FormatException('Expected mono, got $numChannels channels');
  }

  const formatPcm = 1;
  const formatIeeeFloat = 3;
  final sampleCount = dataLength ~/ (bitsPerSample ~/ 8);
  final samples = Float64List(sampleCount);
  if (formatTag == formatIeeeFloat && bitsPerSample == 32) {
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getFloat32(dataOffset + i * 4, Endian.little);
    }
  } else if (formatTag == formatPcm && bitsPerSample == 16) {
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(dataOffset + i * 2, Endian.little) / 32768.0;
    }
  } else {
    throw FormatException(
      'Unsupported format: tag=$formatTag bits=$bitsPerSample',
    );
  }

  final resampled = sampleRate == targetSampleRate
      ? samples
      : _resample(samples, sampleRate, targetSampleRate);

  final int16Samples = Int16List(resampled.length);
  for (var i = 0; i < resampled.length; i++) {
    final clamped = resampled[i].clamp(-1.0, 1.0);
    int16Samples[i] = (clamped * 32767).round();
  }

  return pcm16WavBytes(int16Samples, sampleRate: targetSampleRate);
}

/// Simple linear-interpolation resample -- adequate for spoken-word
/// answer audio (not music), and far cheaper than a proper bandlimited
/// resampler for a WAV that's only ever a few hundred milliseconds long.
Float64List _resample(Float64List samples, int fromRate, int toRate) {
  if (samples.isEmpty) return samples;
  final outLength = (samples.length * toRate / fromRate).round();
  final out = Float64List(outLength);
  final ratio = (samples.length - 1) / (outLength - 1).clamp(1, 1 << 30);
  for (var i = 0; i < outLength; i++) {
    final srcPos = i * ratio;
    final srcIndex = srcPos.floor();
    final frac = srcPos - srcIndex;
    final a = samples[srcIndex.clamp(0, samples.length - 1)];
    final b = samples[(srcIndex + 1).clamp(0, samples.length - 1)];
    out[i] = a + (b - a) * frac;
  }
  return out;
}
