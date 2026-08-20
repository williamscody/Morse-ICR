import 'dart:async';

import '../audio/turn_player.dart';
import '../debug_log.dart';
import 'character_selector.dart';

/// Drives the character-generation training loop
/// (morse_icr_spec.md section 26 "training engine"): while running,
/// repeatedly selects a character from the active set and plays its
/// "turn" -- Morse tone, recognition-time silence, and (if available)
/// the spoken answer, all rendered into one continuous buffer by
/// [TurnPlayer] (morse_icr project memory: the pre-mix architecture) --
/// before generating the next one.
///
/// The recognition-time gap between the end of a character's Morse tone
/// and the computer speaking the answer (section 6) is baked into the
/// turn's own audio as literal silence, not paced by a software timer --
/// this is what makes the recognition-time setting sample-accurate
/// rather than subject to native platform-channel round-trip latency
/// (the live-triggered design this replaced hit an unfixed 600-1500ms
/// latency floor on the answer's own play() call). [submitResponse]'s
/// "beat the computer" window is evaluated against the same offsets the
/// turn was rendered with, measured from when its play() call was
/// acknowledged.
class TrainingEngine {
  TrainingEngine({required TurnPlayer turnPlayer, CharacterSelector? selector})
    : _turnPlayer = turnPlayer,
      _selector = selector ?? CharacterSelector();

  final TurnPlayer _turnPlayer;
  final CharacterSelector _selector;

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _wakeCompleter;
  Timer? _timer;
  double _wpm = 0;
  Duration _recognitionTime = Duration.zero;
  Duration _extraGap = Duration.zero;

  String? _awaitingResponseFor;
  String? _respondedTo;
  bool _responseWindowOpen = false;
  Timer? _windowOpenTimer;
  Timer? _windowCloseTimer;

  bool get isRunning => _running;

  /// Called with each character just before its turn starts playing.
  ///
  /// Never surfaced in the UI (morse_icr_spec.md section 24 forbids
  /// displaying the character); intended for future milestones
  /// (logging, statistics) and for tests, and used by TrainingScreen to
  /// checkpoint the speech recognizer against fresh speech (section 27).
  void Function(String character)? onCharacterGenerated;

  /// Called when a character's recognition deadline expires without an
  /// answer having been baked into its turn (i.e. [TurnPlayer] didn't
  /// have the answer cached, or [isVoiceEnabled] was false when this
  /// turn was generated) -- the live-fallback path for the "MISS" side
  /// of morse_icr_spec.md section 29's timeline. When the turn *did*
  /// bake in a spoken answer, it has already played automatically as
  /// part of the turn's own buffer, and this is not called at all. The
  /// training loop awaits the returned future before generating the next
  /// character.
  Future<void> Function(String character)? onRecognitionTimeout;

  /// Called (at most once per character) when [submitResponse]
  /// recognizes the correct character -- the "SUCCESS" path of
  /// morse_icr_spec.md section 29's timeline, parallel to
  /// [onRecognitionTimeout]'s "MISS" path.
  ///
  /// Deliberately does *not* suppress the computer's own announcement --
  /// it still plays out (baked into the turn's audio, or via
  /// [onRecognitionTimeout]'s live fallback) regardless, since speech-
  /// recognition accuracy is still being verified and Bill wants the
  /// voice kept on for debugging until a future settings toggle exists
  /// for it. Scoring/statistics (Milestones 14 and 15) and problem-
  /// character capture (Milestone 11) aren't wired up yet either; this
  /// only exists so later work can hook in without further changes here.
  void Function(String character)? onCorrectResponse;

  /// Whether the computer should announce each character's answer at
  /// all -- checked once per character, at the moment its turn is
  /// generated (cold or prepared-ahead), and frozen for that turn only
  /// (the same "a live setting change never interrupts a turn already in
  /// progress, only ones not yet started" rule [updateSettings] follows).
  /// Defaults to always-on if unset.
  bool Function()? isVoiceEnabled;

  /// Call when the learner is recognized as having said a character
  /// aloud (morse_icr_spec.md section 27). Only credited while
  /// [character]'s own recognition-time window is still open -- the gap
  /// between its Morse tone ending and the computer's answer starting --
  /// this is "beat the computer" (section 7): a response that arrives
  /// after that window has already closed loses, even if it's otherwise
  /// correct, so it must not light the green dot. (An earlier version
  /// credited a response any time up until the next character superseded
  /// it, to tolerate ASR's 700ms-1.5s result lag -- on-device testing
  /// showed that made the dot meaningless as a "did I beat the computer"
  /// signal, since most credited responses were actually late.) No-ops
  /// for a mismatched, stale (already-superseded), repeat, or
  /// deadline-expired response, or one that arrives before the current
  /// turn has actually started playing.
  void submitResponse(String character) {
    logDebug(
      'submitResponse($character) awaiting=$_awaitingResponseFor '
      'respondedTo=$_respondedTo',
    );
    if (character != _awaitingResponseFor || character == _respondedTo) {
      return;
    }
    if (!_responseWindowOpen) return;
    _respondedTo = character;
    onCorrectResponse?.call(character);
  }

  /// Starts generating and playing characters from [characters] at
  /// [wpm], with [recognitionTime] of silence baked into each one's
  /// turn and [extraGap] of additional silence leading it (the "Extra
  /// Gap" control, deliberately separate from recognition time -- see
  /// [_runLoop]'s prepare-ahead comment for why it leads the *next*
  /// turn's own buffer rather than trailing this one's), until [stop] is
  /// called. No-op if already running.
  void start({
    required List<String> characters,
    required double wpm,
    required Duration recognitionTime,
    Duration extraGap = Duration.zero,
  }) {
    if (_running) return;
    if (characters.isEmpty) {
      throw ArgumentError('Cannot train with an empty character set');
    }
    _wpm = wpm;
    _recognitionTime = recognitionTime;
    _extraGap = extraGap;
    _running = true;
    _loopFuture = _runLoop(characters);
  }

  /// Changes the character speed, recognition time, and/or extra gap
  /// used by turns generated from now on. The learner may adjust these
  /// live while training is running (they are not locked the way
  /// Personal Character Speed is once training is under way per
  /// morse_icr_spec.md section 17) -- a change never interrupts a turn
  /// already in progress, only ones not yet started.
  void updateSettings({
    double? wpm,
    Duration? recognitionTime,
    Duration? extraGap,
  }) {
    if (wpm != null) _wpm = wpm;
    if (recognitionTime != null) _recognitionTime = recognitionTime;
    if (extraGap != null) _extraGap = extraGap;
  }

  /// Stops the loop and waits for it to fully exit, interrupting any
  /// in-progress inter-turn wait so callers can rely on the engine being
  /// idle -- with no timers left pending -- once this completes.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _awaitingResponseFor = null;
    _respondedTo = null;
    _responseWindowOpen = false;
    _windowOpenTimer?.cancel();
    _windowOpenTimer = null;
    _windowCloseTimer?.cancel();
    _windowCloseTimer = null;
    // Awaited, not fire-and-forget, and deliberately first: Stop is no
    // longer only ever observed in the gap between turns (see
    // TurnAudioEngine's playTurn/playPrepared comments), so a turn's own
    // play() call can still be genuinely in progress right here.
    // TrainingScreen deactivates the shared audio session immediately
    // after this method returns -- doing that while playback is still
    // actually in flight silently kills it without ever resolving that
    // play() call's own Future, hanging it (and every operation the
    // player's queue serializes behind it) forever. Confirmed on-device
    // as the cause of Stop-then-Start wedging the app whenever a turn
    // was long enough (e.g. 500ms+ recognition time) for this race to be
    // reachable.
    await _turnPlayer.stopPlayback();
    // TurnPlayer implementations that support preparing ahead (see
    // _runLoop) outlive any single session -- without this, a turn
    // prepared-but-not-yet-played when Stop lands stays loaded and
    // valid on the shared player, and the next Start's own first
    // playTurn() call would queue up behind it instead of running
    // immediately. Fire-and-forget like the other non-essential cleanup
    // in TrainingScreen's own Stop path -- this must never be what makes
    // Stop itself slow or hang.
    unawaited(_turnPlayer.cancelPrepared());
    // _wakeCompleter can already be completed here -- its owner (_wait)
    // may have just resolved it naturally in the same event-loop turn,
    // before _runLoop's awaited continuation got a chance to move
    // _wakeCompleter on to the next one.
    final wakeCompleter = _wakeCompleter;
    if (wakeCompleter != null && !wakeCompleter.isCompleted) {
      wakeCompleter.complete();
    }
    _wakeCompleter = null;
    await _loopFuture;
    _loopFuture = null;
  }

  Future<void> _runLoop(List<String> characters) async {
    // All null until the current turn's wait below schedules a
    // pre-fetch for the turn after it -- see the prepare-ahead block at
    // the end of this loop for why. Deliberately *local* to this call,
    // not engine fields: a still-in-flight prepare abandoned by [stop]
    // (its future is never awaited once `_running` goes false) writes
    // into this specific closure's variables when it eventually
    // resolves, not into any later `start()` call's fresh `_runLoop`
    // invocation, so a stale pre-fetch from a stopped session can never
    // leak into the next one.
    String? preparedCharacter;
    double? preparedWpm;
    Duration? preparedRecognitionTime;
    bool? preparedIncludeAnswer;
    Duration? preparedExtraGap;
    Future<void>? prepareFuture;

    while (_running) {
      if (prepareFuture != null) {
        await prepareFuture;
        prepareFuture = null;
      }
      // [stop] can land while the await above is still pending -- it
      // doesn't cancel prepareFuture, only unblocks _wait (see the
      // class-level comment on the local prepare* variables) -- so by
      // the time it resolves, this session may already be over. Without
      // this check, the loop would go on to call playPrepared/playTurn
      // for a character stop() never asked for, issuing a genuinely new
      // play() call that stopPlayback() -- already run once, earlier,
      // as part of stop() -- has no way to know about or ever pause.
      // Confirmed on-device as a second, distinct route to the same
      // "play() never resolves, TurnAudioEngine's queue wedges forever"
      // failure the stopPlayback() fix in [stop] addresses for a turn
      // already mid-playback: this is the same failure for a turn that
      // hadn't started playing at all yet when Stop was pressed.
      if (!_running) break;

      final String character;
      final double wpm;
      final Duration recognitionTime;
      final bool includeAnswer;
      final Duration extraGap;
      TurnTiming? timing;

      if (preparedCharacter != null) {
        character = preparedCharacter!;
        wpm = preparedWpm!;
        recognitionTime = preparedRecognitionTime!;
        includeAnswer = preparedIncludeAnswer!;
        extraGap = preparedExtraGap!;
        preparedCharacter = null;
        preparedWpm = null;
        preparedRecognitionTime = null;
        preparedIncludeAnswer = null;
        preparedExtraGap = null;
        logDebug('generated: $character');
        onCharacterGenerated?.call(character);
        try {
          timing = await _turnPlayer.playPrepared();
        } catch (e) {
          logDebug('playPrepared($character) failed: $e');
        }
        if (timing == null) {
          // Nothing usable was pre-fetched (never prepared, prepare
          // failed, or a resetPlayer() raced it) -- fall back to the
          // same cold path used when nothing was prepared at all.
          try {
            timing = await _turnPlayer.playTurn(
              character,
              wpm,
              recognitionTime,
              includeAnswer: includeAnswer,
              extraGap: extraGap,
            );
          } catch (e) {
            logDebug('playTurn($character) failed: $e');
          }
        }
      } else {
        character = _selector.next(characters);
        // Freeze this turn's own speed, recognition time, extra gap, and
        // voice setting, even if [updateSettings] or [isVoiceEnabled]
        // change before it finishes -- only the *next* turn should
        // reflect a live change.
        wpm = _wpm;
        recognitionTime = _recognitionTime;
        includeAnswer = isVoiceEnabled?.call() ?? true;
        extraGap = _extraGap;
        logDebug('generated: $character');
        onCharacterGenerated?.call(character);
        try {
          timing = await _turnPlayer.playTurn(
            character,
            wpm,
            recognitionTime,
            includeAnswer: includeAnswer,
            extraGap: extraGap,
          );
        } catch (e) {
          // A playback failure shouldn't kill the training loop -- audio
          // output is an external boundary (device/plugin issues) the
          // learner can't control mid-session.
          logDebug('playTurn($character) failed: $e');
        }
      }
      if (!_running) break;

      final resolvedTiming =
          timing ??
          const TurnTiming(
            morseEnd: Duration.zero,
            answerStart: Duration.zero,
            totalDuration: Duration.zero,
            hasAnswer: false,
          );
      _awaitingResponseFor = character;
      _respondedTo = null;
      _responseWindowOpen = false;
      _windowOpenTimer?.cancel();
      _windowCloseTimer?.cancel();
      // Two short-lived Timers, rather than measuring elapsed wall-clock
      // time against the turn's own offsets, flip [_responseWindowOpen]
      // exactly at the Morse tone's end and the answer's start -- Dart
      // Timers are already established (morse_icr project memory) as
      // accurate to 1-5ms regardless of lock state, so this tracks the
      // "beat the computer" window precisely without depending on a
      // wall clock that a widget test's virtualized pump() doesn't
      // actually advance.
      _windowOpenTimer = Timer(resolvedTiming.morseEnd, () {
        _responseWindowOpen = true;
      });
      _windowCloseTimer = Timer(resolvedTiming.answerStart, () {
        _responseWindowOpen = false;
      });

      // Pre-fetch the *next* turn now, overlapping its render+
      // setAudioSource() cost with this turn's own playback instead of
      // paying it cold the instant this turn finishes -- on-device
      // measurement found that exact zero-gap handoff is where iOS's
      // background CPU throttling while locked shows up (morse_icr
      // project memory). Fire-and-forget: the loop only actually waits
      // for this the *next* time around, at the top of the while loop,
      // and only for as long as it takes -- a slow or failed prepare
      // just falls back to the cold path above, it never blocks Stop
      // (see the class-level comment on why this is a local variable
      // rather than an engine field).
      final upcoming = _selector.next(characters);
      final upcomingWpm = _wpm;
      final upcomingRecognitionTime = _recognitionTime;
      final upcomingIncludeAnswer = isVoiceEnabled?.call() ?? true;
      final upcomingExtraGap = _extraGap;
      prepareFuture = _turnPlayer
          .prepareTurn(
            upcoming,
            upcomingWpm,
            upcomingRecognitionTime,
            includeAnswer: upcomingIncludeAnswer,
            extraGap: upcomingExtraGap,
          )
          .then((_) {
            preparedCharacter = upcoming;
            preparedWpm = upcomingWpm;
            preparedRecognitionTime = upcomingRecognitionTime;
            preparedIncludeAnswer = upcomingIncludeAnswer;
            preparedExtraGap = upcomingExtraGap;
          })
          .catchError((Object e) {
            logDebug('prepareTurn($upcoming) failed: $e');
          });

      await _wait(resolvedTiming.totalDuration);
      if (!_running) break;

      if (!resolvedTiming.hasAnswer && includeAnswer) {
        final hook = onRecognitionTimeout;
        if (hook != null) {
          try {
            await hook(character);
          } catch (_) {
            // A misbehaving hook (e.g. speech synthesis failure)
            // shouldn't kill the training loop.
          }
        }
      }
    }
  }

  Future<void> _wait(Duration duration) {
    final completer = Completer<void>();
    _wakeCompleter = completer;
    _timer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }
}
