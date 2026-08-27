import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../debug_log.dart';
import 'enrollment_store.dart';
import 'file_enrollment_store.dart';
import 'preferred_input_device.dart';
import 'response_listener.dart';
import 'utterance_endpointer.dart';
import 'voice_character_matcher.dart';

/// Implements [ResponseListener] (morse_icr_spec.md section 38) using
/// the enrollment-trained [VoiceCharacterMatcher] instead of
/// `package:speech_to_text`: one continuous raw-PCM16 mic stream (same
/// `pcm16bits`/16000Hz/mono capture proven in Milestone 13 steps 1-2),
/// segmented into individual utterances by [UtteranceEndpointer], each
/// matched against the learner's enrolled recordings.
///
/// `TrainingScreen`'s production listener as of Milestone 13 step 5.
///
/// Used a much shorter [UtteranceEndpointer.hangoverDuration] (80ms) and
/// [UtteranceEndpointer.maxUtteranceDuration] (800ms) than enrollment's
/// own recorder through Milestone 13's timing work, purely to fit inside
/// the "beat the computer" recognitionTime window -- see that field's
/// doc comment for the on-device history (a fixed-duration
/// onset-triggered capture was tried in between and reverted: it fit
/// the response window better but truncated real speech and tanked
/// accuracy). Once onset-based timing (Milestone 13, 2026-08-22:
/// [UtteranceEndpointer.onSpeechStarted]) started judging the deadline
/// at speech *onset* instead of match completion, that pressure went
/// away entirely -- capture/match latency no longer affects whether a
/// response counts as on-time. But the short hangover/max-duration
/// settings were left in place, meaning every live query was still
/// being captured under tighter, more truncation-prone conditions than
/// the enrolled references it's compared against (enrollment uses
/// 500ms hangover / the 2000ms default max, see
/// `character_recorder.dart`). Matched to enrollment's settings here
/// (2026-08-23) to remove that query/reference capture mismatch as a
/// source of matching error, now that there's no longer a reason not
/// to.
class VoiceResponseListener
    with OnsetDetectingResponseListener
    implements ResponseListener {
  VoiceResponseListener({
    VoiceCharacterMatcher? matcher,
    EnrollmentStore? enrollmentStore,
    UtteranceEndpointer? endpointer,
  }) : _matcher =
           matcher ??
           VoiceCharacterMatcher(enrollmentStore ?? FileEnrollmentStore()),
       _endpointer =
           endpointer ??
           UtteranceEndpointer(
             hangoverDuration: const Duration(milliseconds: 500),
           ) {
    _endpointer.onSpeechStarted = _handleSpeechStarted;
  }

  final VoiceCharacterMatcher _matcher;
  final UtteranceEndpointer _endpointer;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  ResponseCallback? _onRecognized;
  Set<String>? _activeCharacters;
  ResponseWindowSnapshot? _pendingWindowSnapshot;

  /// Restricts matching to [characters] -- `TrainingScreen` calls this
  /// with the active training set right before each session starts
  /// (morse_icr_spec.md section 27: training a set never asks about
  /// characters outside it). Not part of [ResponseListener] itself,
  /// same as other implementation-specific hooks in this codebase
  /// (e.g. `TrainingScreen._applyAppSettings`'s `is TtsAnswerSpeaker`
  /// check) -- callers reach this via an `is VoiceResponseListener`
  /// check rather than it polluting the shared interface every
  /// implementation would otherwise have to support.
  void updateActiveCharacters(List<String> characters) {
    _activeCharacters = characters.toSet();
  }

  // [captureResponseWindow] (from [OnsetDetectingResponseListener]) is
  // what `TrainingScreen` wires to `TrainingEngine.captureResponseWindow`
  // -- [_handleSpeechStarted] below calls it to snapshot "beat the
  // computer" timing the instant the learner starts responding, well
  // before recognition finishes resolving what they said (Milestone 13,
  // 2026-08-22 -- see `TrainingEngine.submitResponse`'s `at` parameter).

  void _handleSpeechStarted() {
    _pendingWindowSnapshot = captureResponseWindow?.call();
  }

  @override
  Future<void> startListening(ResponseCallback onRecognized) async {
    _onRecognized = onRecognized;
    if (!await _recorder.hasPermission()) return;
    _endpointer.reset();
    _pendingWindowSnapshot = null;
    // Picks up any enrollment changes made since the last session
    // (Settings' "Personalize Recognition" can happen between sessions
    // while this listener instance outlives them) rather than matching
    // against cached, possibly-stale reference features.
    _matcher.invalidateCache();
    const sampleRate = 16000;
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        // See preferred_input_device.dart -- avoids a connected
        // Bluetooth headset's much lower-fidelity mic silently being
        // used instead of the phone's own.
        device: await preferredInputDevice(_recorder),
      ),
    );
    _subscription = stream.listen(_onChunk);
  }

  @override
  Future<void> restart() async {
    // Does nothing (2026-08-23, second reversion after a second
    // on-device regression -- see git history for the first). This
    // used to call `_endpointer.reset()` and clear
    // [_pendingWindowSnapshot]; both are now known actively harmful for
    // the same underlying reason: `TrainingScreen` calls [restart] on
    // *every* new character (`onCharacterGenerated`), which can land
    // while the learner's response to the *previous* character is
    // still in flight -- captured at onset (fast), but not yet finished
    // hanging over into a completed utterance (up to ~1.5s later for a
    // full word plus the 500ms hangover). Clearing [_pendingWindowSnapshot]
    // here destroys that still-pending onset snapshot before the
    // utterance completes, so when it finally does, `_onChunk` reads
    // `_pendingWindowSnapshot` as null and `submitResponse` falls back
    // to *live* state -- which has by then already advanced to the new
    // character -- silently reintroducing the exact "judged against
    // whenever recognition finishes, not when the learner actually
    // started responding" race onset-based timing (2026-08-22) existed
    // specifically to eliminate. On-device data (2026-08-23) showed
    // this precisely: a learner's genuinely correct, cleanly-matched
    // response to character N was consistently logged as a mismatched
    // response to character N+1 whenever N+1 followed N within about a
    // word's length -- read as "character N confused with N+1" at
    // first, until the pattern turned out to track sequence position
    // (always the *next* character in a fixed test order), not
    // acoustics, giving away the real cause. Neither field needs
    // clearing: [UtteranceEndpointer] guarantees at most one utterance
    // in flight at a time, and [_pendingWindowSnapshot] is read-and-
    // cleared synchronously the moment that utterance actually
    // completes ([_onChunk]), so there's no scenario where leaving both
    // alone leaks stale state into a later, unrelated utterance.
  }

  @override
  Future<void> stopListening() async {
    _onRecognized = null;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
  }

  void _onChunk(Uint8List chunk) {
    final utterance = _endpointer.addChunk(chunk, pcm16ChunkDuration(chunk));
    if (utterance != null) {
      // Captured (and cleared) here, before the async match below, so a
      // second utterance's onset can't overwrite it mid-match -- safe
      // since [UtteranceEndpointer] only ever has one utterance in
      // flight at a time, so onset-then-completion is always sequential
      // per utterance.
      final snapshot = _pendingWindowSnapshot;
      _pendingWindowSnapshot = null;
      // Diagnostic-only (Milestone 13 step 5 on-device trial):
      // [_matchAndReport] runs unawaited/unserialized, so overlapping
      // matches could in principle back up behind each other -- these
      // timestamps are here to confirm or rule that out from real
      // on-device timing before changing anything.
      logDebug('voice: utterance detected (${utterance.length} bytes)');
      unawaited(_matchAndReport(utterance, snapshot));
    }
  }

  Future<void> _matchAndReport(
    Uint8List utterance,
    ResponseWindowSnapshot? snapshot,
  ) async {
    final startedAt = DateTime.now();
    final character = await _matcher.match(
      utterance,
      candidates: _activeCharacters,
    );
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    logDebug('voice: match took ${elapsedMs}ms -> ${character ?? "no match"}');
    if (character != null) _onRecognized?.call(character, at: snapshot);
  }
}
