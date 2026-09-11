import 'dart:async';
import 'dart:typed_data' show Int16List;

import 'package:just_audio/just_audio.dart';

import '../debug_log.dart';
import '../morse/morse_event.dart';
import '../speech/answer_speaker.dart';
import 'in_memory_audio_source.dart';
import 'tone_synthesizer.dart';
import 'turn_player.dart';
import 'turn_renderer.dart';

/// Renders and plays one training "turn" -- a character's Morse tone, a
/// recognition-time silent gap, and (if cached) the spoken answer -- as
/// one continuous buffer, played with a single play() call.
///
/// This replaces the earlier design of live-triggering separate play()
/// calls for the Morse tone and, later, the TTS answer. That design hit
/// a real, unfixed native latency floor: [AnswerSpeaker]'s own play()
/// call was consistently taking 600-1500ms to be acknowledged, dwarfing
/// the learner's configured recognition time (morse_icr project memory).
/// Once a turn's buffer starts playing, everything within it -- Morse
/// tone, recognition-time silence, spoken answer -- is governed by the
/// audio hardware's own sample clock, immune to that per-call native
/// round-trip variance, because there are no further live platform-
/// channel calls needed mid-turn. Recognition time becomes literal
/// silence baked into the waveform rather than a Dart Timer racing a
/// separate live play() call.
class TurnAudioEngine implements TurnPlayer {
  TurnAudioEngine({
    required AnswerSpeaker answerSpeaker,
    this.synthesizer = const ToneSynthesizer(),
    AudioPlayer? player,
  }) : _answerSpeaker = answerSpeaker,
       _player =
           player ??
           AudioPlayer(
             handleAudioSessionActivation: false,
             handleInterruptions: false,
           ) {
    _watchProcessingState(_player);
  }
  // handleAudioSessionActivation: false -- by default, just_audio calls
  // AudioSession.instance.setActive(true) on the shared AVAudioSession
  // on *every* play() call. This app already owns that lifecycle
  // explicitly (see audio_session_setup.dart, called from
  // TrainingScreen's Start/resume handlers), and on-device measurement
  // found the redundant per-player reactivation was real, measurable
  // contention (morse_icr project memory).
  //
  // handleInterruptions: false -- by default, just_audio auto-pauses
  // itself in response to AudioSession interruption events (see its own
  // doc comment on the constructor parameter). Confirmed on-device
  // (Moto G Play 2024, 2026-09-10, network-mode speech recognition):
  // starting a recognition session triggers exactly this kind of
  // interruption, and with the default `true`, just_audio silently
  // paused a turn's own Morse/TTS playback mid-tone the moment
  // recognition grabbed the audio focus -- audible as tones cut off
  // partway through. This app already manages its own playback
  // lifecycle deliberately (Start/Stop, resetPlayer); it doesn't want a
  // *different* subsystem's own focus request silently pausing it.
  //
  // Every AudioPlayer this app constructs sets both the same way, for
  // the same reasons.

  static const _sampleRate = 44100;

  // Mutable (not final) so [updateMorseSettings] can swap in a new
  // instance when the learner adjusts Morse pitch/volume (section 35) --
  // [ToneSynthesizer] itself stays an immutable value type, matching how
  // [CountdownTimerConfig] and other settings snapshots in this project
  // are rebuilt wholesale rather than mutated in place.
  ToneSynthesizer synthesizer;
  final AnswerSpeaker _answerSpeaker;
  AudioPlayer _player;

  // TEMP diagnostic (2026-09-10): logs every processingState transition
  // with a timestamp, to check whether a reported per-character
  // "stepped, 50% then 100% ~50ms later" volume fade correlates with a
  // real buffering/loading window in just_audio's own state machine
  // (this app's InMemoryAudioSource is served through just_audio's
  // local HTTP loopback proxy, which has genuine per-call latency) --
  // as opposed to a platform/HAL volume ramp, which wouldn't show up
  // here at all. Remove once this investigation concludes either way.
  StreamSubscription<ProcessingState>? _processingStateSub;

  void _watchProcessingState(AudioPlayer player) {
    _processingStateSub?.cancel();
    _processingStateSub = player.processingStateStream.listen((state) {
      logDebug('processingState: $state');
    });
  }

  // Every operation below runs through this queue, so a resetPlayer()
  // triggered by TrainingScreen's app-resume handler can never dispose
  // _player out from under a prepareTurn/playTurn/playPrepared call
  // that's still in flight against it. Strictly sequential rather than a
  // real lock: each operation only starts once the previous one's future
  // has resolved.
  Future<void> _queue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  // Set by _prepareTurn, consumed by _playPrepared. Tracks which
  // AudioPlayer instance the loaded buffer actually belongs to -- since
  // everything is serialized through [_queue], resetPlayer() can only
  // ever run between operations, never during one, but this identity
  // check is cheap insurance against a prepared buffer outliving the
  // player it was loaded into.
  AudioPlayer? _preparedPlayer;
  TurnTiming? _preparedTiming;

  @override
  Future<TurnTiming> playTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) {
    final issued = Completer<TurnTiming>();
    unawaited(
      _enqueue(
        () => _playTurn(
          character,
          wpm,
          recognitionTime,
          includeAnswer,
          extraGap,
          issued,
        ),
      ).catchError((Object e) {
        if (!issued.isCompleted) issued.completeError(e);
        logDebug('playTurn($character) failed: $e');
      }),
    );
    return issued.future;
  }

  // just_audio's play() Future does not resolve once playback *starts*
  // -- confirmed against the bundled iOS plugin source (AudioPlayer.m's
  // play: handler stashes the method call's FlutterResult and only
  // invokes it later, from pause/complete/dispose or a superseding
  // play() call) -- it resolves once playback *ends* or is interrupted.
  // [TrainingEngine] paces its own loop and the "beat the computer"
  // response-window Timers off of when a turn was *issued* to the
  // player, not when its playback finishes, so [issued] completes as
  // soon as play() has been called rather than once play() itself
  // resolves (on-device testing found awaiting that resolution here was
  // what turned a supposedly near-zero turn-to-turn handoff into a real,
  // roughly-one-turn-length dead-air gap between packages -- doubling
  // perceived character-to-character spacing, and delaying the window
  // Timers until well after the audio they're meant to track had
  // already finished playing). The enqueued operation itself still
  // awaits play() to real completion below, though, so [_queue] doesn't
  // let a subsequent [_prepareTurn] touch this same shared player
  // (pause()+setAudioSource()) until this turn has actually finished
  // playing.
  Future<void> _playTurn(
    String character,
    double wpm,
    Duration recognitionTime,
    bool includeAnswer,
    Duration extraGap,
    Completer<TurnTiming> issued,
  ) async {
    // Only the very first _playTurn() of a session (or after
    // resetPlayer()) gets a primer -- see [_primerSamples]'s own doc
    // comment for why, and [_warmedUp]'s for why the cold path
    // ([_playTurn], not [_prepareTurn]/[_playPrepared]) is exactly where
    // this belongs: it's what a session's first turn always goes
    // through.
    final primer = _warmedUp ? null : _primerSamples();
    final rendered = _renderTurn(
      character,
      wpm,
      recognitionTime,
      includeAnswer,
      extraGap,
      leadingPrimerSamples: primer,
    );
    _warmedUp = true;
    // just_audio's native iOS setAudioSource() (AudioPlayer.m's load:)
    // auto-starts the newly loaded source immediately if its own
    // `playing` flag is still true from before -- pausing first (a
    // no-op if already paused) guarantees our own play() call below is
    // what actually starts this turn, never a stale-state side effect of
    // setAudioSource() itself (morse_icr project memory: this was the
    // root cause of the "two morse characters, then voice" bug).
    // Tried skipping this on Android (2026-09-10), theorizing it was an
    // iOS-only guard, against a reported per-character stepped
    // volume-fade -- made things measurably worse (TTS sometimes not
    // sounding at all, badly broken timing), so this pause() is
    // required on Android too, not just iOS. Reverted; see
    // [[project_android_bluetooth_recognition]] project memory. The
    // per-character version of that fade was fixed instead by enabling
    // [TrainingScreen]'s KeepAliveAudioLoop on Android too (previously
    // iOS-only) -- see that call site's own comment. A first-turn-only
    // version of the fade is still open.
    await _player.pause();
    logDebug('playTurn($character): setAudioSource');
    // initialPosition explicit, not relying on setAudioSource's own
    // documented zero default -- investigating a reported first-turn
    // audio-loss/fade pattern ("as if the audio stream is starting
    // somewhere along its path, depending on where it previously
    // stopped" -- Bill, 2026-09-10) that would exactly match a stale
    // seek position carrying over from whatever this player last
    // played, if the native side doesn't reliably honor that default
    // itself.
    await _player.setAudioSource(
      InMemoryAudioSource(rendered.wavBytes),
      initialPosition: Duration.zero,
    );
    _preparedPlayer = null;
    _preparedTiming = null;
    // answerStart/totalDuration/hasAnswer logged here (not just at the
    // top of this method) so this line's own timestamp is what anchors
    // them to a real wall-clock moment -- correlating this against
    // SpeechToTextResponseListener's own status/restart timestamps is
    // the intended diagnostic for the AirPods loud-voice bug under
    // investigation (2026-09-02): that restart cycle flips the shared
    // AVAudioSession's category on every OS-driven listen-session
    // restart, on a cadence that isn't synchronized to turn playback at
    // all, and this is what a restart landing inside a turn's *answer*
    // segment specifically (not its much-shorter Morse segment) would
    // look like in the logs.
    logDebug(
      'playTurn($character): play() answerStart=${rendered.timing.answerStart} '
      'totalDuration=${rendered.timing.totalDuration} '
      'hasAnswer=${rendered.timing.hasAnswer}',
    );
    final playFuture = _player.play();
    issued.complete(rendered.timing);
    logDebug('playTurn($character): play() issued');
    await playFuture;
    logDebug('playTurn($character): play() completed');
  }

  /// Renders [character]'s turn ahead of time and loads it into the
  /// player without starting playback, so a later [playPrepared] call
  /// only needs to call play(). Queued behind the current turn's own
  /// play() call (see [_playTurn]'s matching comment on why that call
  /// only resolves once real playback ends), so in practice this only
  /// starts once the current turn has actually finished playing, not
  /// while it's still audible -- both turns share one [AudioPlayer], so
  /// starting this any earlier would mean pausing/reloading the source
  /// still playing out to the learner.
  @override
  Future<void> prepareTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
    required Duration extraGap,
  }) {
    return _enqueue(
      () => _prepareTurn(
        character,
        wpm,
        recognitionTime,
        includeAnswer,
        extraGap,
      ),
    );
  }

  Future<void> _prepareTurn(
    String character,
    double wpm,
    Duration recognitionTime,
    bool includeAnswer,
    Duration extraGap,
  ) async {
    final rendered = _renderTurn(
      character,
      wpm,
      recognitionTime,
      includeAnswer,
      extraGap,
    );
    final player = _player;
    // See _playTurn's matching comment -- without pausing first,
    // setAudioSource() below could auto-play this turn immediately as a
    // side effect, silently starting it before playPrepared is ever
    // called. (Tried Android-conditional, see _playTurn's own comment on
    // why that was reverted -- required on Android too.)
    await player.pause();
    logDebug('prepareTurn($character): setAudioSource');
    // See _playTurn's matching comment on why initialPosition is
    // explicit here.
    await player.setAudioSource(
      InMemoryAudioSource(rendered.wavBytes),
      initialPosition: Duration.zero,
    );
    if (identical(player, _player)) {
      _preparedPlayer = player;
      _preparedTiming = rendered.timing;
    }
    logDebug('prepareTurn($character): ready');
  }

  @override
  Future<TurnTiming?> playPrepared() {
    final issued = Completer<TurnTiming?>();
    unawaited(
      _enqueue(() => _playPrepared(issued)).catchError((Object e) {
        if (!issued.isCompleted) issued.completeError(e);
        logDebug('playPrepared() failed: $e');
      }),
    );
    return issued.future;
  }

  // See _playTurn's matching comment -- [issued] completes as soon as
  // play() has been called, not once its own Future resolves (which
  // just_audio only does at end-of-playback), while the enqueued
  // operation still awaits real completion so [_queue] keeps a
  // subsequent [_prepareTurn] from touching the shared player until this
  // turn has actually finished playing.
  Future<void> _playPrepared(Completer<TurnTiming?> issued) async {
    if (!identical(_preparedPlayer, _player) || _preparedTiming == null) {
      issued.complete(null);
      return;
    }
    final timing = _preparedTiming!;
    _preparedPlayer = null;
    _preparedTiming = null;
    // See _playTurn's matching comment -- same diagnostic purpose, and
    // this is the path an actual training session almost always takes
    // (prepareTurn() runs ahead of time while the previous turn is still
    // playing; playTurn() is only the not-ready-in-time fallback).
    logDebug(
      'playPrepared(): play() answerStart=${timing.answerStart} '
      'totalDuration=${timing.totalDuration} hasAnswer=${timing.hasAnswer}',
    );
    final playFuture = _player.play();
    issued.complete(timing);
    logDebug('playPrepared(): play() issued');
    await playFuture;
    logDebug('playPrepared(): play() completed');
  }

  /// Discards whatever [prepareTurn] most recently rendered, without
  /// playing it. TrainingScreen calls this from Stop -- TurnAudioEngine
  /// itself outlives any single training session, so without this, a
  /// turn prepared-but-not-yet-played when Stop lands stays loaded and
  /// valid, and the *next* Start's own playTurn() call would otherwise
  /// queue up behind whatever's still in flight for it in [_queue].
  @override
  Future<void> cancelPrepared() {
    return _enqueue(() async {
      _preparedPlayer = null;
      _preparedTiming = null;
    });
  }

  // Deliberately bypasses [_enqueue]: this exists specifically to unstick
  // an in-flight _playTurn/_playPrepared operation that [_queue] is
  // currently blocked on (see [TurnPlayer.stopPlayback]'s doc comment),
  // so it has to be able to reach the player directly rather than queue
  // up behind the very operation it's meant to free. just_audio's
  // pause() is what actually resolves that stuck operation's own play()
  // Future (see _playTurn's comment on why play() doesn't resolve on its
  // own until paused/completed/interrupted) -- confirmed on-device as
  // the fix for Stop-then-Start silently wedging the app whenever Stop
  // landed while a turn (long enough, e.g. 500ms+ recognition time) was
  // still actually playing: TrainingScreen deactivates the shared
  // AVAudioSession right after TrainingEngine.stop() returns, and doing
  // that while a play() call was still genuinely in flight silently
  // killed native playback without ever invoking just_audio's own
  // pause/complete handlers, leaving that call's Future -- and every
  // operation queued behind it -- hung forever. Safe to call when
  // nothing is actually playing (pause() is a no-op on both the Dart and
  // native side in that case), and safe to race against a concurrently-
  // queued pause()/play() call, since both just idempotently toggle the
  // same native playing state.
  @override
  Future<void> stopPlayback() => _player.pause();

  /// Updates the Morse sidetone's pitch/volume (section 35) for turns
  /// rendered from now on -- like a live WPM/recognition-time change,
  /// this never touches a turn already rendered or in progress, only
  /// ones not yet started. [frequencyHz]/[amplitude] leave the
  /// corresponding [synthesizer] field unchanged when omitted.
  void updateMorseSettings({double? frequencyHz, double? amplitude}) {
    synthesizer = ToneSynthesizer(
      sampleRate: synthesizer.sampleRate,
      frequencyHz: frequencyHz ?? synthesizer.frequencyHz,
      amplitude: amplitude ?? synthesizer.amplitude,
      rampSeconds: synthesizer.rampSeconds,
    );
  }

  RenderedTurn _renderTurn(
    String character,
    double wpm,
    Duration recognitionTime,
    bool includeAnswer,
    Duration extraGap, {
    Int16List? leadingPrimerSamples,
  }) {
    final morseSamples = synthesizer.renderSamples(
      morseElementsForCharacter(character, wpm),
    );
    final answerSamples = includeAnswer
        ? _answerSpeaker.cachedSamplesFor(character)
        : null;
    return renderTurn(
      morseSamples: morseSamples,
      recognitionTime: recognitionTime,
      answerSamples: answerSamples,
      extraGap: extraGap,
      leadingPrimerSamples: leadingPrimerSamples,
      sampleRate: _sampleRate,
    );
  }

  // See [_playTurn]'s own use of this -- a low-amplitude tone spliced
  // directly onto the front of a session's first turn, in the same
  // buffer as the real content, so a Bluetooth link that needs to wake
  // up pays that cost against this primer instead of the learner's
  // actual first character. Not pure silence: some audio pipelines
  // special-case all-zero PCM (e.g. skipping a full Bluetooth wake since
  // silence doesn't need to actually reach the far end), so a genuinely
  // silent primer may never exercise the same wake-up path real audio
  // content does -- confirmed on-device (Moto G Play 2024, 2026-09-08):
  // a silent version of this same idea, played as a separate play()
  // call before the first turn rather than spliced into it, did not fix
  // the reported symptom.
  //
  // 2026-09-11: switched from a 300ms tone at the Morse tone's own pitch
  // to a sub-bass (20Hz) tone, matching [KeepAliveAudioLoop]'s own
  // frequency choice -- that tone is confirmed (on-device) to satisfy
  // whatever Android's audio pipeline needs to consider a stream
  // "really" playing, whereas this primer's original full-pitch version
  // did not resolve a persistent, first-turn-only truncated-Morse/
  // TTS-first symptom even combined with `initialPosition: Duration.zero`
  // and the unconditional KeepAliveAudioLoop fix (see
  // [[project_android_bluetooth_recognition]]). Working theory motivating
  // the longer duration: Bill directly observed Android's Stop button
  // audibly fading out currently-playing audio (unlike iOS, which cuts
  // immediately) -- consistent with Android's own
  // AudioService.FadeOutManager applying a gain ramp
  // (fadeOutUid/unfadeOutUid) tied to audio focus loss/gain, which
  // requestAudioFocus() at Start would trigger a matching ramp-*up* for,
  // below the app/just_audio layer entirely. 300ms was confirmed too
  // short to outlast that ramp; 500ms measurably improved things
  // on-device (TTS-first symptom gone), bumped to 750ms next to fully
  // confirm the truncated-Morse remainder is gone too.
  Int16List _primerSamples() {
    final primerSynthesizer = ToneSynthesizer(
      sampleRate: _sampleRate,
      frequencyHz: 20,
      amplitude: 0.05,
    );
    return primerSynthesizer.renderSamples(const [
      MorseElement(toneOn: true, durationSeconds: 0.75),
    ]);
  }

  /// Recreates the underlying [AudioPlayer], discarding the old one.
  ///
  /// [InMemoryAudioSource]'s [StreamAudioSource] support is backed by a
  /// local loopback HTTP server that package:just_audio creates once per
  /// [AudioPlayer] instance and only re-binds if its own internal
  /// "running" flag is false. On-device testing confirmed that server
  /// can go silently unreachable across an iOS background+lock+resume
  /// cycle -- every subsequent [playTurn] call then fails with native
  /// error -1004 ("Could not connect to the server") -- without that
  /// flag ever getting reset, so just_audio's own self-healing never
  /// kicks in. A fresh [AudioPlayer] gets a fresh proxy server,
  /// sidestepping the problem entirely; call this on app resume.
  Future<void> resetPlayer() {
    return _enqueue(_resetPlayer);
  }

  Future<void> _resetPlayer() async {
    final old = _player;
    // See constructor's own doc comment for handleAudioSessionActivation
    // and handleInterruptions.
    _player = AudioPlayer(
      handleAudioSessionActivation: false,
      handleInterruptions: false,
    );
    _watchProcessingState(_player);
    _preparedPlayer = null;
    _preparedTiming = null;
    _warmedUp = false;
    await old.dispose();
  }

  // Guards the primer [_playTurn] splices onto a session's first turn
  // (see [_primerSamples]'s own doc comment). Originally assumed this
  // only needed to happen once per [_player] instance ("a second Start
  // against an already-warm player doesn't need it again") -- confirmed
  // wrong on-device (2026-09-11, Moto G Play 2024): a *fresh app launch*
  // Start got a perfect first Morse tone (primer audibly played), but a
  // Stop then Start right after, same player instance, played no primer
  // at all and the clipping came right back. The primer isn't actually
  // warming up the player/buffer pipeline itself -- it's very likely
  // absorbing an Android audio-focus gain ramp (see
  // [[project_android_bluetooth_recognition]]'s FadeOutManager theory),
  // which this app's own Stop/Start handlers re-trigger on *every* cycle
  // (`deactivateAudioSession()`/`activateAudioSession()`), not just once
  // per player instance. [markSessionStart] now resets this on every
  // Start/Resume, not just [_resetPlayer]'s app-background-recovery
  // path.
  //
  // Previously a separate play() call issued before the first real
  // [playTurn] (2026-09-08 "TTS plays before Morse" investigation) --
  // confirmed on-device (2026-09-10) that a separate call didn't help:
  // the very next play() call (the real turn) could still pay its own
  // Bluetooth-link-wake cost, since it's a distinct play() from the
  // primer's. Moved to splicing the primer directly onto the front of
  // the first turn's own buffer instead -- one continuous play() call,
  // no gap for the link to go idle in between. See
  // [[project_android_bluetooth_recognition]] project memory.
  bool _warmedUp = false;

  /// Call at the start of every training session (Start and Resume
  /// alike, see `TrainingScreen`) -- see [_warmedUp]'s own doc comment
  /// for why a session's first turn needs its primer every time audio
  /// focus is freshly (re)acquired, not just once per [_player]
  /// instance/app launch.
  void markSessionStart() {
    _warmedUp = false;
  }

  Future<void> dispose() => _player.dispose();
}
