import 'dart:async';

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
       _player = player ?? AudioPlayer(handleAudioSessionActivation: false);
  // handleAudioSessionActivation: false -- by default, just_audio calls
  // AudioSession.instance.setActive(true) on the shared AVAudioSession
  // on *every* play() call. This app already owns that lifecycle
  // explicitly (see audio_session_setup.dart, called from
  // TrainingScreen's Start/resume handlers), and on-device measurement
  // found the redundant per-player reactivation was real, measurable
  // contention (morse_icr project memory). Every AudioPlayer this app
  // constructs sets this the same way, for the same reason.

  static const _sampleRate = 44100;

  // Mutable (not final) so [updateMorseSettings] can swap in a new
  // instance when the learner adjusts Morse pitch/volume (section 35) --
  // [ToneSynthesizer] itself stays an immutable value type, matching how
  // [CountdownTimerConfig] and other settings snapshots in this project
  // are rebuilt wholesale rather than mutated in place.
  ToneSynthesizer synthesizer;
  final AnswerSpeaker _answerSpeaker;
  AudioPlayer _player;

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
    final rendered = _renderTurn(
      character,
      wpm,
      recognitionTime,
      includeAnswer,
      extraGap,
    );
    // just_audio's native iOS setAudioSource() (AudioPlayer.m's load:)
    // auto-starts the newly loaded source immediately if its own
    // `playing` flag is still true from before -- pausing first (a
    // no-op if already paused) guarantees our own play() call below is
    // what actually starts this turn, never a stale-state side effect of
    // setAudioSource() itself (morse_icr project memory: this was the
    // root cause of the "two morse characters, then voice" bug).
    await _player.pause();
    logDebug('playTurn($character): setAudioSource');
    await _player.setAudioSource(InMemoryAudioSource(rendered.wavBytes));
    _preparedPlayer = null;
    _preparedTiming = null;
    logDebug('playTurn($character): play()');
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
    // called.
    await player.pause();
    logDebug('prepareTurn($character): setAudioSource');
    await player.setAudioSource(InMemoryAudioSource(rendered.wavBytes));
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
    logDebug('playPrepared(): play()');
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
    Duration extraGap,
  ) {
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
      sampleRate: _sampleRate,
    );
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
    _player = AudioPlayer(handleAudioSessionActivation: false);
    _preparedPlayer = null;
    _preparedTiming = null;
    await old.dispose();
  }

  Future<void> dispose() => _player.dispose();
}
