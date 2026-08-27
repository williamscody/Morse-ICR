import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../debug_log.dart';
import 'character_recognizer.dart';
import 'recognition_sound_muter.dart';
import 'response_listener.dart';

/// Wraps package:speech_to_text to implement [ResponseListener]
/// (morse_icr_spec.md section 27).
///
/// Each platform listen session is time-limited by the OS (Android
/// especially, often on the order of ten seconds of silence) -- this
/// restarts listening automatically whenever a session ends on its own
/// while [startListening] is still supposed to be active, so
/// recognition stays live for the whole training session rather than
/// just its first several seconds.
class SpeechToTextResponseListener
    with OnsetDetectingResponseListener
    implements ResponseListener {
  SpeechToTextResponseListener({SpeechToText? speechToText})
    : _speechToText = speechToText ?? SpeechToText();

  final SpeechToText _speechToText;
  ResponseCallback? _onRecognized;
  bool _shouldBeListening = false;

  // [OnsetDetectingResponseListener.captureResponseWindow] results, each
  // captured the instant [_onSoundLevel] detects a speech onset and
  // consumed by the next [_onResult] call that actually matches that
  // *same* character (searched by [ResponseWindowSnapshot.character],
  // not queue position -- see that method's own comment for why).
  // `package:speech_to_text` has no onset event of its own (only ever a
  // finished/partial transcript, well after the fact), so
  // [_onSoundLevel] approximates one from raw sound-level readings, the
  // same role [UtteranceEndpointer.onSpeechStarted] plays for
  // [VoiceResponseListener].
  //
  // A list searched by character, not a single slot or a strict FIFO --
  // on-device data went through two failed designs before this one.
  // First, a single slot: silently discarded a perfectly good,
  // still-unconsumed onset whenever a *later* turn's own onset fired
  // before the earlier turn's recognition result had arrived to consume
  // it (routine -- results commonly lag speech by up to ~1s+). Fixed
  // with a FIFO queue (oldest popped unconditionally on any match).
  // Second, on-device data (2026-08-26, 35WPM/500ms) broke *that*: the
  // FIFO queue assumes exactly one onset per one successful character
  // match, in the same order -- but a single mismatched/merged-into-
  // another-word utterance (confirmed on-device: "T" transcribed as
  // "Hey", never isolating into its own matched token at all) drops one
  // match from that count while its onset still gets queued, permanently
  // shifting every later match onto the *previous* turn's onset instead
  // of its own. Once shifted, every single response for the rest of the
  // session is guaranteed a character-identity mismatch and gets
  // rejected, regardless of how promptly it was actually spoken --
  // confirmed directly: an onset that genuinely landed inside its own
  // window (`windowOpen: true`) got consumed by an unrelated match, and
  // the character it was actually captured for later got paired with a
  // stale, already-closed snapshot instead. Searching for the matching
  // `character` (same pattern `TrainingEngine._pendingTurns` already
  // uses) doesn't depend on parity between the two counts, so a dropped
  // match no longer misattributes everything downstream of it. Capped
  // (see [_onSoundLevel]) so a long stretch of never-matched onsets
  // (ambient noise, repeated mishears) can't grow this unboundedly.
  //
  // Third bug (2026-08-28): finding *no* matching entry here used to
  // mean [_onResult] passed `at: null` to [_onRecognized] -- which tells
  // `TrainingEngine.submitResponse` "this listener has no onset info at
  // all," skipping timing enforcement entirely and crediting on content
  // match alone within its 2s grace window. On-device data showed
  // `onSoundLevelChange` itself can go completely silent for many
  // seconds at a time (an 11-second stretch with *zero* onset/release
  // log lines, spanning six consecutive characters) while transcription
  // kept working fine throughout -- confirmed directly as the cause of
  // 7 false wins in one 35WPM/500ms session where the learner
  // deliberately answered late for every one of those six: with no
  // captured onset to judge against, `at: null` waved every one of them
  // through. The same silent stretches (just shorter) had *also* been
  // quietly credited earlier the same session for characters the
  // learner happened to answer on time anyway -- so the earlier
  // "successes" weren't actually evidence the fallback was working
  // correctly, just luck lining up with intent. [_onResult] now never
  // passes `at: null` -- finding no entry means no *positive evidence*
  // of on-time speech, which should fail closed (reject), not fall back
  // to a "no onset support at all" path this listener doesn't actually
  // belong on since it does track onset.
  final List<ResponseWindowSnapshot> _pendingSnapshots = [];

  // Onset detection state (see [_onSoundLevel]) -- a *relative* jump
  // above a slowly-adapting quiet-period baseline, not a fixed absolute
  // threshold. `onSoundLevelChange`'s own doc warns its units aren't
  // even documented for Android and differ from iOS's decibels, so
  // there's no cross-device number to hardcode confidently; adapting to
  // whatever's actually quiet right now should hold up better across
  // devices/rooms than a guessed absolute floor would.
  //
  // [_onsetMarginDb]/[_releaseMarginDb] (see their own doc comment near
  // [_onSoundLevel] for the current values and 2026-08-27 rationale for
  // lowering them) started as first-attempt placeholders, the same as
  // every other threshold in this codebase started out (see e.g.
  // dtw.dart's `placeholderMaxDistance` history), and are still not
  // claimed to be *finished* calibrating -- [logDebug] below logs every
  // reading and onset decision specifically so real captured numbers can
  // keep informing them. On-device data (2026-08-26, 35WPM/700ms) showed
  // actual speech clears even the original, higher margin by a wide
  // spread (onsets 40-55dB above a stable ~-67 to -70dB quiet baseline) --
  // the margin was never too *high* to ever trigger, the problem
  // quantified later (2026-08-27) was the several tens of ms it takes
  // amplitude to *ramp up to* whatever margin is set, eating into a
  // ~500ms window's own budget.
  //
  // A [_onsetHangover] (level must stay below the release margin for a
  // sustained stretch, not just one reading, before re-arming) was tried
  // here to fix a related but much smaller problem -- a single spoken
  // word occasionally crossing the onset margin, dipping briefly, and
  // crossing it again, firing two "onset" events for one utterance --
  // and reverted the same day: on-device data at these fast settings
  // (35WPM/700ms, ~500ms-wide windows) showed *every single* onset that
  // session landing 25-160ms after its own window had already closed,
  // scoring the whole session 0 despite genuinely on-time responses.
  // 500ms of required quiet is a substantial fraction of a ~500ms
  // window's own width plus the gap before it -- any ambient blip during
  // that stretch resets the countdown and can push the next real onset's
  // *detection* (not just its timing precision) past the deadline
  // entirely. Back to firing (and re-arming) on a single reading
  // crossing the margin -- the double-onset problem is real but
  // narrower in impact (see [_onResult]'s own fix for why a stray extra
  // onset mostly doesn't matter now) than a hangover long enough to
  // sometimes eat the whole window did.
  double? _quietBaseline;
  bool _speaking = false;
  // Counts down on each of the first few [_onSoundLevel] readings of a
  // listen session -- while positive, a reading unconditionally
  // overwrites [_quietBaseline] (bypassing the leaky EMA below) and
  // onset/release is not evaluated at all. Guards against exactly what
  // on-device data (2026-08-26) showed: the *very first* reading of a
  // listen session can be a cold-start artifact from before iOS's audio
  // pipeline is actually delivering real samples (observed: -100.85dB,
  // versus a steady-state quiet room around -70 to -75dB). Seeding
  // [_quietBaseline] from that single reading (the old `??= level`)
  // pins the baseline near silence; the very next *real* ambient
  // reading then trivially clears [_onsetMarginDb] above it and latches
  // [_speaking] true -- and it can never release again, since
  // [_releaseMarginDb] above a ~-100dB baseline is still far below any
  // real room's noise floor. Confirmed directly: onset detection never
  // fired again for the rest of that entire session after the first,
  // spurious trigger. A few overwrite-not-blend readings wash out one
  // bad sample fast, unlike [_baselineAdaptRate]'s slow EMA (deliberately
  // slow for its own job -- tolerating a brief loud moment *after*
  // baseline is already good -- which is too slow to recover from a
  // single wildly-wrong seed within any one turn's short window).
  int _warmupReadingsRemaining = _warmupReadingCount;

  // The OS reports one growing transcript for an entire listen session
  // rather than one per character (confirmed on-device: consecutive
  // single-letter utterances arrive as "E", "EE", "EET", "EETF", ...
  // with no word-boundary spaces between them), which defeats
  // character_recognizer's whitespace-split matching for every
  // character after the first. [restart] checkpoints [_consumedText]
  // to whatever's been heard so far, so [_onResult] only matches the
  // text appended since the last character began -- a software-only
  // reset. An earlier version restarted the native session instead
  // (stop() + listen()) to get the same effect, but doing that
  // adjacent to flutter_tts speaking the answer raced the OS
  // AVAudioSession handoff between the two plugins and crashed the
  // app on-device.
  String _consumedText = '';
  String _lastFullText = '';

  @override
  Future<void> startListening(ResponseCallback onRecognized) async {
    _onRecognized = onRecognized;
    _shouldBeListening = true;
    await RecognitionSoundMuter.mute();
    final available = await _speechToText.initialize(onStatus: _onStatus);
    // Logged (2026-08-28) after an on-device session (35WPM/500ms, app
    // presumably backgrounded overnight beforehand) produced *zero*
    // `heard`/onset/release log lines for its entire duration -- Morse
    // playback ran normally throughout, so recognition itself never
    // started at all, not just missed timing. Neither this nor [_listen]
    // logged anything on the failure paths that could explain why, so
    // there was no way to tell `initialize()` returning `false` apart
    // from [_listen]'s own early-return guard apart from a genuinely
    // silent native-side failure. All three are now visible.
    logDebug('speech_to_text: initialize available=$available');
    if (!available || !_shouldBeListening) return;
    await _listen();
  }

  @override
  Future<void> restart() async {
    _consumedText = _lastFullText;
  }

  @override
  void armForNewTurn() {
    // See [OnsetDetectingResponseListener.armForNewTurn]'s own doc
    // comment -- on-device data (2026-08-28, 35WPM/500ms) showed a
    // spoken letter's natural amplitude decay routinely outlasts a
    // ~500ms response window (readings staying elevated for the better
    // part of a second is normal, not a stuck-release bug), so waiting
    // for genuine silence before the *next* turn's onset can arm means
    // that next turn's real speech often never registers at all --
    // confirmed for 11 of 26 characters in one session, each swallowed
    // by its own immediate predecessor's still-active trailing speech.
    // Forcibly re-arming right when this turn's window opens trades that
    // guaranteed miss for a narrower risk: if the previous answer's tail
    // is still audible at this exact instant, it could occasionally get
    // mistaken for this turn's own onset. Judged the better trade --
    // that risk is bounded to the moment of the reset itself, while the
    // old behavior guaranteed a miss for the rest of the window whenever
    // it triggered.
    if (_speaking) {
      logDebug(
        'speech_to_text: armForNewTurn forcing release (was still '
        'speaking)',
      );
    }
    _speaking = false;
  }

  @override
  Future<void> stopListening() async {
    _shouldBeListening = false;
    _onRecognized = null;
    try {
      await _speechToText.stop();
    } finally {
      // Always restore the notification stream even if stop() itself
      // throws -- leaving it muted device-wide would be far worse than
      // the chime this silences in the first place.
      await RecognitionSoundMuter.unmute();
    }
  }

  Future<void> _listen() async {
    if (!_shouldBeListening) {
      logDebug('speech_to_text: _listen skipped, not supposed to be '
          'listening');
      return;
    }
    if (_speechToText.isListening) {
      // A session that produced *zero* `heard`/onset/release log lines
      // for its entire duration (2026-08-28, likely following an
      // overnight app backgrounding) traced to this flag: [_listen] is
      // only ever called right after a fresh [startListening] or right
      // after [_onStatus] reports the *previous* session already ended
      // -- so `isListening` should always be false by the time this
      // runs. The old code treated an unexpectedly-true reading here as
      // "someone else is legitimately using it, back off" and returned
      // without ever calling `listen()` again -- silently, with no
      // exception, so the caller (`TrainingScreen`'s Start handler) saw
      // a normal successful return and proceeded as if recognition had
      // started. The only plausible way to reach `isListening: true`
      // here is a stale native session that never got the memo it ended
      // (e.g. surviving an odd lifecycle transition) -- so force it
      // stopped and start fresh instead of deferring to it.
      logDebug(
        'speech_to_text: _listen found isListening already true -- '
        'stopping stale session before starting fresh',
      );
      try {
        await _speechToText.stop();
      } catch (e) {
        logDebug('speech_to_text: stop() before fresh listen threw $e');
      }
    }
    _consumedText = '';
    _lastFullText = '';
    // Fresh onset-detection state per listen session -- ambient level
    // can genuinely shift between OS-imposed session restarts (see
    // [_onStatus]), so starting from a known-clean baseline each time
    // beats carrying a possibly-stale one across the boundary.
    _quietBaseline = null;
    _speaking = false;
    _warmupReadingsRemaining = _warmupReadingCount;
    _pendingSnapshots.clear();
    // On-device recognition skips the network round-trip to Apple's
    // servers that the (default) hybrid on-device/network mode can
    // take -- measured on-device, results otherwise arrived 700ms-1.5s
    // after the speech that produced them, well past any recognition
    // window a fast-paced training loop can afford to wait.
    try {
      await _speechToText.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: SpeechListenOptions(onDevice: true),
      );
      logDebug('speech_to_text: listen() call returned');
    } catch (e) {
      // See [startListening]'s own log comment -- a silent exception
      // here (native-side failure to actually start the audio tap, for
      // instance) was previously indistinguishable from every other way
      // a session could produce zero recognition output.
      logDebug('speech_to_text: listen() threw $e');
    }
  }

  // Restarts listening once the OS-imposed session limit ends a listen
  // session on its own -- without this, recognition would silently stop
  // working partway through a training session instead of covering it.
  void _onStatus(String status) {
    // Logged (2026-08-28) alongside [startListening]/[_listen]'s own new
    // logging -- see their comments for the session that motivated this
    // (zero recognition output for its entire duration, no prior
    // visibility into any of these paths to say why).
    logDebug(
      'speech_to_text: status=$status shouldBeListening=$_shouldBeListening',
    );
    if (_shouldBeListening &&
        (status == SpeechToText.doneStatus ||
            status == SpeechToText.notListeningStatus)) {
      unawaited(_listen());
    }
  }

  // Runs on both partial and final results (package:speech_to_text
  // defaults to reporting partials) -- an unmatched result simply
  // doesn't call [_onRecognized], leaving listening to continue.
  //
  // A [SpeechRecognitionResult.isConfident] gate was tried here to
  // filter out ambient-noise false positives (short function words
  // like "a"/"I" getting hallucinated from silence, since those are
  // themselves valid single-character matches -- section 27) but had to
  // be reverted: on-device measurement showed it rejected *all* results,
  // including genuine correctly-spoken characters, not just noise --
  // consistent with `SpeechListenOptions(onDevice: true)` (see
  // [_listen]) reporting `confidence: 0.0` on iOS rather than the -1
  // "missing" sentinel [isConfident] treats as pass-through, since
  // Apple's on-device recognizer doesn't compute per-word confidence the
  // way its server-based path does. [logDebug] calls below capture
  // `confidence`/`resultType` on real device data before any further
  // filtering is attempted.
  void _onResult(SpeechRecognitionResult result) {
    final fullText = result.recognizedWords;
    _lastFullText = fullText;
    final newText = fullText.startsWith(_consumedText)
        ? fullText.substring(_consumedText.length)
        : fullText; // the OS revised earlier text -- treat it all as new
    logDebug(
      'heard "$newText" (full="$fullText" conf=${result.confidence} '
      'final=${result.finalResult} pending=$_pendingSnapshots)',
    );
    final character = characterForSpokenText(newText);
    // A [_pendingSnapshots] entry is only removed here, on an actual
    // match -- *not* unconditionally at the top of this method. Most
    // `_onResult` calls aren't a new utterance at all: `newText` above is
    // frequently the OS revising/re-confirming text already consumed by
    // an earlier call (on-device data, 2026-08-26, showed this firing for
    // essentially every partial update), and consuming an entry on every
    // one of those calls was destroying a still-valid onset before the
    // result it actually belonged to had even arrived.
    //
    // Removed by matching [character], not queue position -- see
    // [_pendingSnapshots]'s own doc comment for why a positional pop
    // (even a well-ordered FIFO one) silently misattributes every
    // response for the rest of a session the moment a single utterance
    // fails to isolate into its own matched token.
    //
    // Among same-character entries, the earliest *in-window* one wins,
    // not simply the earliest overall -- on-device data (2026-08-26,
    // 35WPM/500ms, random off) showed a spurious onset firing *before* a
    // turn's window had even opened (leftover vocal energy trailing the
    // previous character's answer, or ambient noise, while this
    // character was already the one being awaited), queueing ahead of
    // the genuine in-window onset for the same character. Taking
    // strictly the oldest entry -- fine when there's only ever one --
    // grabbed that bogus early one and rejected a response that was
    // actually on time; confirmed directly for three separate characters
    // in that session (each had exactly one `windowOpen: false` entry
    // timestamped *before* its own window opened, immediately followed
    // by a `windowOpen: true` one that would have credited cleanly).
    // Falls back to the earliest entry overall if none of them are
    // in-window, preserving the existing (correct) reject for a response
    // that's genuinely late.
    if (character != null) {
      _consumedText = fullText;
      int? openIndex;
      int? fallbackIndex;
      for (var i = 0; i < _pendingSnapshots.length; i++) {
        if (_pendingSnapshots[i].character != character) continue;
        fallbackIndex ??= i;
        if (_pendingSnapshots[i].windowOpen) {
          openIndex = i;
          break;
        }
      }
      final chosenIndex = openIndex ?? fallbackIndex;
      // Never passes `at: null` -- see this field's own reasoning.
      // Finding no matching entry means no *positive evidence* this
      // response was on time, not "this listener has no onset info at
      // all"; only the latter is what `TrainingEngine.submitResponse`'s
      // `at == null` path is meant for.
      final snapshot = chosenIndex == null
          ? (character: character, windowOpen: false)
          : _pendingSnapshots.removeAt(chosenIndex);
      _onRecognized?.call(character, at: snapshot);
    }
  }

  // [_onsetMarginDb]: how far above the adapted quiet baseline a reading
  // has to jump to count as onset. [_releaseMarginDb] is deliberately
  // smaller than [_onsetMarginDb] (hysteresis, a classic Schmitt
  // trigger) so a brief dip mid-word doesn't fragment one utterance into
  // several separate "onset" events -- speech has to fall most of the
  // way back toward baseline, not just dip slightly below the onset bar,
  // before the next rise counts as a new onset. Deliberately just this
  // one reading's amplitude, not also a sustained-quiet time requirement
  // on top -- see this class's own field doc comment for why a
  // hangover-based version of this was tried and reverted the same day.
  //
  // Lowered from 6.0/3.0 (2026-08-27) on real data, not a blind guess:
  // with the queue-attribution, in-window-preference, and baseline-
  // lockup bugs all fixed, a clean 35WPM/500ms A-Z session still only
  // credited 13/26, and hand-tracing every miss against its own window
  // close showed a consistent ~20-100ms detection lag past true speech
  // onset (e.g. B 50ms, F 75ms, G 92ms, I 91ms, T 98ms late) -- not
  // bookkeeping, the actual amplitude ramp time needed to clear 6dB.
  // Lower margins should let onset fire earlier on the same rise.
  // Ratio to [_releaseMarginDb] kept the same (2:1) to preserve the
  // hysteresis gap's relative size. A stray extra onset from firing more
  // eagerly is much less costly now than when these were first picked --
  // [_onResult]'s character-matching search and in-window preference
  // mean an extra spurious crossing mostly just sits harmlessly in
  // [_pendingSnapshots] rather than stealing another turn's credit.
  // Confirmed improved on-device (2026-08-27): a repeat 35WPM/500ms
  // session went from 13/26 credited to 19/28, with most remaining
  // misses' lateness margins shrinking to single digits-to-~80ms. Two
  // characters (of 9 still missed) showed a different, not-yet-confirmed
  // failure mode instead -- see the release branch's own log comment in
  // [_onSoundLevel].
  static const double _onsetMarginDb = 4.0;
  static const double _releaseMarginDb = 2.0;
  // How quickly [_quietBaseline] adapts toward the current reading while
  // not speaking -- small, so a single louder-than-usual quiet moment
  // (a door, a cough) doesn't yank the baseline up and desensitize onset
  // detection for a while after.
  static const double _baselineAdaptRate = 0.05;
  // Safety cap on [_pendingSnapshots] -- generous relative to how many
  // turns could plausibly go by with an onset detected but never matched
  // (ambient noise, a word that fails to transcribe) before the oldest
  // entry is just noise at this point. Not expected to matter in normal
  // use; guards against unbounded growth if matches stop arriving for an
  // extended stretch.
  static const int _maxPendingSnapshots = 8;
  // How many of a listen session's first [_onSoundLevel] readings are
  // spent purely calibrating [_quietBaseline] (see that field's own doc
  // comment) before onset detection is armed at all -- a first-attempt
  // placeholder, same as every other threshold in this file, picked
  // small enough not to meaningfully delay a real first turn's own
  // onset in the common case while still being enough readings to wash
  // out one cold-start outlier.
  static const int _warmupReadingCount = 5;

  void _onSoundLevel(double level) {
    if (_warmupReadingsRemaining > 0) {
      _warmupReadingsRemaining--;
      _quietBaseline = level;
      return;
    }
    final baseline = _quietBaseline ??= level;
    if (!_speaking) {
      if (level >= baseline + _onsetMarginDb) {
        _speaking = true;
        final snapshot = captureResponseWindow?.call();
        if (snapshot != null) {
          _pendingSnapshots.add(snapshot);
          while (_pendingSnapshots.length > _maxPendingSnapshots) {
            _pendingSnapshots.removeAt(0);
          }
        }
        logDebug(
          'speech_to_text: onset level=$level baseline=$baseline '
          'snapshot=$snapshot',
        );
      } else {
        _quietBaseline = baseline + (level - baseline) * _baselineAdaptRate;
      }
    } else if (level < baseline + _releaseMarginDb) {
      _speaking = false;
      // Logged (2026-08-27) to test a hypothesis -- **confirmed**
      // 2026-08-28: a session had an onset fire 87ms *before* a
      // turn's own window even opened, and the next release didn't come
      // until over a second later, well past that turn's window closing
      // -- `_speaking` stayed latched the entire time, so the turn's
      // *real* spoken response never registered as a new onset at all
      // (onset only fires from a `!_speaking` state). Confirmed with
      // headphones in use, ruling out speaker-to-mic bleed as the cause
      // of the sustained elevated reading.
      logDebug('speech_to_text: release level=$level baseline=$baseline');
    } else {
      // Logged (2026-08-28) to see *why* release sometimes takes over a
      // second -- genuine trailing vocal energy, a sustained elevated
      // reading, or something else in how readings arrive -- rather than
      // continuing to infer it only from the onset/release bookends. Only
      // fires while [_speaking] is latched and not yet released, so a
      // normal quick utterance (the overwhelming majority) adds nothing;
      // only a stuck stretch like the one above will produce a visible
      // run of these.
      logDebug(
        'speech_to_text: still speaking level=$level baseline=$baseline',
      );
    }
  }
}
