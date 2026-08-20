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

/// Splices [extraGap] worth of leading silence, [morseSamples],
/// [recognitionTime] worth of silence, and (if given) [answerSamples]
/// into one continuous mono 16-bit-PCM WAV buffer at [sampleRate] -- the
/// core of the pre-mix architecture (morse_icr project memory).
///
/// Both silence gaps are realized as literal zero-filled samples, not a
/// software timer, so they're sample-accurate: pulled out here as a pure
/// function (parallel to how [ToneSynthesizer] separates Morse rendering
/// from playback plumbing) specifically so this offset arithmetic -- the
/// exact thing "accurate, repeatable and consistent recognition time"
/// depends on -- can be unit tested without a real [AudioPlayer].
///
/// [extraGap] leads this turn's own buffer, rather than trailing the
/// *previous* turn's, so it doesn't delay [TrainingEngine]'s live-TTS
/// fallback for a turn whose answer wasn't cached in time (that fallback
/// fires as soon as this turn's own [TurnTiming.totalDuration] elapses)
/// and so [morseEnd]/[answerStart] -- still measured from this buffer's
/// own start, per [TurnTiming]'s doc comment -- shift out along with it,
/// keeping the "beat the computer" window aligned with where the Morse
/// tone actually now sits.
RenderedTurn renderTurn({
  required Int16List morseSamples,
  required Duration recognitionTime,
  Int16List? answerSamples,
  Duration extraGap = Duration.zero,
  int sampleRate = 44100,
}) {
  int sampleCountFor(Duration duration) =>
      (duration.inMicroseconds * sampleRate / Duration.microsecondsPerSecond)
          .round();

  final gapCount = sampleCountFor(extraGap);
  final silenceCount = sampleCountFor(recognitionTime);
  final morseOffset = gapCount;
  final morseEndOffset = morseOffset + morseSamples.length;
  final answerOffset = morseEndOffset + silenceCount;
  final totalLength = answerOffset + (answerSamples?.length ?? 0);

  final combined = Int16List(totalLength);
  combined.setRange(morseOffset, morseEndOffset, morseSamples);
  // [answerOffset, totalLength) is either the answer, spliced in below,
  // or -- when there's no cached answer -- left at Int16List's default
  // zero fill, extending the trailing silence to the turn's end. The
  // leading [0, morseOffset) gap and the mid-turn recognition-time
  // silence are left at that same default zero fill too.
  if (answerSamples != null) {
    combined.setRange(answerOffset, totalLength, answerSamples);
  }

  Duration durationForSamples(int count) => Duration(
    microseconds: (count * Duration.microsecondsPerSecond / sampleRate).round(),
  );

  return RenderedTurn(
    wavBytes: pcm16WavBytes(combined, sampleRate: sampleRate),
    timing: TurnTiming(
      morseEnd: durationForSamples(morseEndOffset),
      answerStart: durationForSamples(answerOffset),
      totalDuration: durationForSamples(totalLength),
      hasAnswer: answerSamples != null,
    ),
  );
}
