import 'dart:typed_data';

import 'pcm16_wav.dart';
import 'turn_player.dart';

/// One turn's rendered audio, ready to hand to an [AudioPlayer]'s
/// `setAudioSource`, alongside the precise offsets within it.
class RenderedTurn {
  const RenderedTurn({required this.wavBytes, required this.timing});
  final Uint8List wavBytes;
  final TurnTiming timing;
}

/// Splices [morseSamples], [recognitionTime] worth of silence, and (if
/// given) [answerSamples] into one continuous mono 16-bit-PCM WAV buffer
/// at [sampleRate] -- the core of the pre-mix architecture (morse_icr
/// project memory).
///
/// The recognition-time gap is realized as literal zero-filled samples,
/// not a software timer, so it is sample-accurate: pulled out here as a
/// pure function (parallel to how [ToneSynthesizer] separates Morse
/// rendering from playback plumbing) specifically so this offset
/// arithmetic -- the exact thing "accurate, repeatable and consistent
/// recognition time" depends on -- can be unit tested without a real
/// [AudioPlayer].
RenderedTurn renderTurn({
  required Int16List morseSamples,
  required Duration recognitionTime,
  Int16List? answerSamples,
  int sampleRate = 44100,
}) {
  final silenceCount =
      (recognitionTime.inMicroseconds *
              sampleRate /
              Duration.microsecondsPerSecond)
          .round();
  final answerOffset = morseSamples.length + silenceCount;
  final totalLength = answerOffset + (answerSamples?.length ?? 0);

  final combined = Int16List(totalLength);
  combined.setRange(0, morseSamples.length, morseSamples);
  // [answerOffset, totalLength) is either the answer, spliced in below,
  // or -- when there's no cached answer -- left at Int16List's default
  // zero fill, extending the trailing silence to the turn's end.
  if (answerSamples != null) {
    combined.setRange(answerOffset, totalLength, answerSamples);
  }

  Duration durationForSamples(int count) => Duration(
    microseconds: (count * Duration.microsecondsPerSecond / sampleRate).round(),
  );

  return RenderedTurn(
    wavBytes: pcm16WavBytes(combined, sampleRate: sampleRate),
    timing: TurnTiming(
      morseEnd: durationForSamples(morseSamples.length),
      answerStart: durationForSamples(answerOffset),
      totalDuration: durationForSamples(totalLength),
      hasAnswer: answerSamples != null,
    ),
  );
}
