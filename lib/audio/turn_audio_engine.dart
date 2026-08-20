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

  final ToneSynthesizer synthesizer;
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
  }) {
    return _enqueue(
      () => _playTurn(character, wpm, recognitionTime, includeAnswer),
    );
  }

  Future<TurnTiming> _playTurn(
    String character,
    double wpm,
    Duration recognitionTime,
    bool includeAnswer,
  ) async {
    final rendered = _renderTurn(
      character,
      wpm,
      recognitionTime,
      includeAnswer,
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
    await _player.play();
    logDebug('playTurn($character): play() returned');
    return rendered.timing;
  }

  /// Renders [character]'s turn ahead of time and loads it into the
  /// player without starting playback, so a later [playPrepared] call
  /// only needs to call play(). Intended to run during the *current*
  /// turn's playback, overlapping this call's own render and
  /// setAudioSource() cost with time the learner is already listening
  /// through.
  @override
  Future<void> prepareTurn(
    String character,
    double wpm,
    Duration recognitionTime, {
    required bool includeAnswer,
  }) {
    return _enqueue(
      () => _prepareTurn(character, wpm, recognitionTime, includeAnswer),
    );
  }

  Future<void> _prepareTurn(
    String character,
    double wpm,
    Duration recognitionTime,
    bool includeAnswer,
  ) async {
    final rendered = _renderTurn(
      character,
      wpm,
      recognitionTime,
      includeAnswer,
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
    return _enqueue(_playPrepared);
  }

  Future<TurnTiming?> _playPrepared() async {
    if (!identical(_preparedPlayer, _player) || _preparedTiming == null) {
      return null;
    }
    final timing = _preparedTiming!;
    _preparedPlayer = null;
    _preparedTiming = null;
    logDebug('playPrepared(): play()');
    await _player.play();
    logDebug('playPrepared(): play() returned');
    return timing;
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

  RenderedTurn _renderTurn(
    String character,
    double wpm,
    Duration recognitionTime,
    bool includeAnswer,
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
