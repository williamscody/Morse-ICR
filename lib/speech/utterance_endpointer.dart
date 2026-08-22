import 'dart:typed_data';

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
    this.hangoverDuration = const Duration(milliseconds: 400),
    this.minUtteranceDuration = const Duration(milliseconds: 150),
    this.maxUtteranceDuration = const Duration(milliseconds: 2000),
  });

  /// PCM16 peak-amplitude (0-32767) a chunk must cross to count as
  /// speech rather than silence/background noise.
  final int speechThreshold;

  /// How much accumulated silence after speech ends the utterance.
  final Duration hangoverDuration;

  /// Utterances shorter than this are discarded as noise blips rather
  /// than returned from [addChunk].
  final Duration minUtteranceDuration;

  /// Safety cap forcing an utterance to end even if speech never
  /// pauses, so a stuck/loud input can't buffer forever.
  final Duration maxUtteranceDuration;

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
