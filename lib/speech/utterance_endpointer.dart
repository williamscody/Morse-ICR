import 'dart:typed_data';

/// The duration [chunk] represents, assuming raw PCM16 mono audio at
/// [sampleRate] -- shared by every caller streaming real-time PCM16
/// chunks into an [UtteranceEndpointer] (`VoiceResponseListener`'s live
/// recognition and `character_recorder.dart`'s enrollment capture).
Duration pcm16ChunkDuration(Uint8List chunk, {int sampleRate = 16000}) {
  final sampleCount = chunk.length ~/ 2;
  return Duration(microseconds: sampleCount * 1000000 ~/ sampleRate);
}

/// Segments a continuous stream of raw PCM16 audio chunks into
/// individual spoken-character utterances (morse_icr_spec.md section
/// 38), via a simple peak-amplitude voice-activity detector -- the same
/// per-chunk peak scan Milestone 13 step 1's on-device mic spike used to
/// confirm real signal was coming through.
///
/// Kept separate from the real microphone plumbing (`VoiceResponseListener`)
/// so the segmentation decision itself is unit-testable without a mic,
/// the same split step 3 used for MFCC/DTW math vs. real capture.
///
/// All four thresholds below are unvalidated placeholders -- like
/// `voice_character_matcher.dart`'s `placeholderMaxDistance`, section 38
/// flags this as needing on-device tuning against Bill's actual voice
/// and recording environment, not a finished design.
class UtteranceEndpointer {
  UtteranceEndpointer({
    this.speechThreshold = 1000,
    this.hangoverDuration = const Duration(milliseconds: 150),
    this.minUtteranceDuration = const Duration(milliseconds: 150),
    this.maxUtteranceDuration = const Duration(milliseconds: 2000),
  });

  /// PCM16 peak-amplitude (0-32767) a chunk must cross to count as
  /// speech rather than silence/background noise.
  final int speechThreshold;

  /// How much accumulated silence after speech ends the utterance --
  /// pure latency tax on top of the match itself, since nothing is
  /// reported until this elapses.
  ///
  /// Lowered from an initial 400ms placeholder to 150ms, then to 80ms
  /// for live recognition specifically (Milestone 13 step 5,
  /// 2026-08-21/22), purely to fit inside a 1000ms recognitionTime
  /// deadline that was, at the time, judged against when matching
  /// *finished* rather than when speech started. A fixed-duration
  /// onset-triggered capture was tried in between (`FixedWindowCapture`,
  /// since removed): it landed inside the window far more often, but a
  /// duration short enough to fit (400ms) truncated real speech and
  /// collapsed match accuracy (4/7 correct at 600ms down to 1/8 at
  /// 400ms, with wrong answers clustering on a couple of generic
  /// short-clip "attractors" -- the same failure mode enrollment
  /// trimming fixed once already, this time on the query side), while a
  /// duration long enough to preserve accuracy (600ms) missed the
  /// window every time.
  ///
  /// Onset-based timing ([onSpeechStarted], Milestone 13, 2026-08-22)
  /// replaced all of that: the deadline is now judged at speech onset,
  /// so hangover length no longer affects whether a response counts as
  /// on-time. `VoiceResponseListener` (2026-08-23) went back to
  /// matching enrollment's own 500ms hangover for live recognition too,
  /// since an 80ms hangover was truncating live queries far more
  /// aggressively than the enrolled references they're matched against
  /// -- a query/reference capture mismatch, not a genuine accuracy
  /// tradeoff, once timing pressure was no longer the reason for it.
  final Duration hangoverDuration;

  /// Utterances shorter than this are discarded as noise blips rather
  /// than returned from [addChunk].
  final Duration minUtteranceDuration;

  /// Safety cap forcing an utterance to end even if speech never
  /// pauses, so a stuck/loud input can't buffer forever.
  final Duration maxUtteranceDuration;

  /// Called the instant a chunk first crosses [speechThreshold] -- i.e.
  /// speech onset -- well before [addChunk] eventually returns the
  /// complete utterance once silence (or [maxUtteranceDuration]) ends
  /// it. Not every caller needs this (`character_recorder.dart`'s
  /// enrollment capture leaves it unset); `VoiceResponseListener` uses
  /// it to snapshot "beat the computer" timing at the earliest possible
  /// moment, since recognition itself can take far longer to finish
  /// than onset detection does (Milestone 13, 2026-08-22 on-device
  /// data: match latency alone was pushing the deadline check past
  /// close on nearly every response, even when the learner started
  /// answering well within the window).
  void Function()? onSpeechStarted;

  bool _speaking = false;
  final BytesBuilder _buffer = BytesBuilder();
  Duration _bufferedDuration = Duration.zero;
  Duration _silenceDuration = Duration.zero;

  /// Feeds one chunk of raw PCM16 bytes, captured over [chunkDuration].
  /// Returns the completed utterance's raw PCM16 bytes once an endpoint
  /// is reached, or null while still accumulating (or if a completed
  /// utterance was too short and got discarded as noise).
  Uint8List? addChunk(Uint8List pcm16Chunk, Duration chunkDuration) {
    final isSpeech = _peakAmplitude(pcm16Chunk) >= speechThreshold;

    if (!_speaking) {
      if (!isSpeech) return null;
      _speaking = true;
      _buffer.clear();
      _bufferedDuration = Duration.zero;
      _silenceDuration = Duration.zero;
      onSpeechStarted?.call();
    }

    _buffer.add(pcm16Chunk);
    _bufferedDuration += chunkDuration;
    _silenceDuration = isSpeech
        ? Duration.zero
        : _silenceDuration + chunkDuration;

    final endpointReached =
        _silenceDuration >= hangoverDuration ||
        _bufferedDuration >= maxUtteranceDuration;
    return endpointReached ? _endUtterance() : null;
  }

  /// Discards any in-progress (not yet emitted) utterance without
  /// returning it -- backs [ResponseListener.restart], so speech heard
  /// before a new character's window began never gets matched against
  /// it.
  void reset() {
    _speaking = false;
    _buffer.clear();
    _bufferedDuration = Duration.zero;
    _silenceDuration = Duration.zero;
  }

  Uint8List? _endUtterance() {
    _speaking = false;
    final tooShort = _bufferedDuration < minUtteranceDuration;
    final bytes = _buffer.toBytes();
    _buffer.clear();
    _bufferedDuration = Duration.zero;
    _silenceDuration = Duration.zero;
    return tooShort ? null : bytes;
  }

  int _peakAmplitude(Uint8List chunk) {
    var maxAbs = 0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = (chunk[i] | (chunk[i + 1] << 8)).toSigned(16);
      final abs = sample.abs();
      if (abs > maxAbs) maxAbs = abs;
    }
    return maxAbs;
  }
}
