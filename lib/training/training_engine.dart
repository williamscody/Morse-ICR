import 'dart:async';

import '../audio/turn_player.dart';
import '../debug_log.dart';
import '../speech/response_listener.dart' show ResponseWindowSnapshot;
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
  TrainingEngine({
    required TurnPlayer turnPlayer,
    CharacterSelector? selector,
    Duration pendingResponseTimeout = const Duration(seconds: 2),
  }) : _turnPlayer = turnPlayer,
       _selector = selector ?? CharacterSelector(),
       _pendingResponseTimeout = pendingResponseTimeout;

  final TurnPlayer _turnPlayer;
  final CharacterSelector _selector;
  // How long a closed-but-uncredited turn stays eligible for a late
  // credit before [_finalizeMissed] gives up on it -- see
  // [_pendingTurns]'s doc comment. Overridable (tests use a short value)
  // so the timeout itself is directly testable without a real multi-
  // second wait; production code relies on the default.
  final Duration _pendingResponseTimeout;

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _wakeCompleter;
  Timer? _timer;
  double _wpm = 0;
  Duration _recognitionTime = Duration.zero;
  Duration _extraGap = Duration.zero;

  String? _awaitingResponseFor;
  bool _responseWindowOpen = false;
  // The bookkeeping object for whatever [_awaitingResponseFor] currently
  // is -- shared by reference with [_pendingTurns] once its window
  // closes, so a late credit finds and marks the *same* object rather
  // than only ever being able to affect "the current turn" or "the
  // pending list" as two disconnected things (see [_pendingTurns]).
  _OutstandingTurn? _currentTurn;
  // Turns whose response window has already closed without being
  // credited yet, each still eligible for a late credit -- routine here,
  // not an edge case: recognition latency (endpointer hangover + DTW
  // match) commonly runs several hundred ms to ~1s, comparable to or
  // longer than a single turn's own cadence at fast WPM/short
  // recognitionTime, so a genuinely on-time response's credit frequently
  // doesn't land until *after* one or more later turns have already
  // begun. An earlier design fired a turn's miss determination as soon
  // as the *next* turn began, using a single shared "was the awaited
  // character credited yet" field -- on-device data (2026-08-24,
  // 24WPM/700ms) showed this fired a false miss for the outgoing turn
  // moments before its own late-but-legitimate credit arrived (and the
  // shared field then got overwritten by that late credit, corrupting
  // whatever the *new* current turn's own bookkeeping needed it for
  // next). Tracking each closed turn as its own object, kept eligible
  // for a genuinely generous, fixed real-time window rather than
  // "however long the next turn happens to take," fixes both.
  final List<_OutstandingTurn> _pendingTurns = [];
  Timer? _windowOpenTimer;
  Timer? _windowCloseTimer;

  bool get isRunning => _running;

  /// Forwards to [CharacterSelector.randomOrder] -- see its doc comment.
  /// Takes effect on the very next character generated, same as
  /// [updateSettings]'s other live-adjustable fields.
  set randomCharacterOrder(bool value) => _selector.randomOrder = value;

  /// Called with each character just before its turn starts playing.
  ///
  /// Never surfaced in the UI (morse_icr_spec.md section 24 forbids
  /// displaying the character); intended for future milestones
  /// (logging, statistics) and for tests, and used by TrainingScreen to
  /// checkpoint the speech recognizer against fresh speech (section 27).
  void Function(String character)? onCharacterGenerated;

  /// Called the instant [character]'s response window actually opens
  /// (the same moment [_responseWindowOpen] flips true), not when it was
  /// merely generated -- lets an onset-capable [ResponseListener] re-arm
  /// onset detection at exactly this boundary. Added 2026-08-28: on-device
  /// data showed a spoken letter's natural vocal decay routinely outlasts
  /// a ~500ms response window, so the *previous* turn's trailing speech
  /// was still active (by amplitude) when this turn's window opened,
  /// preventing its own onset from ever registering (onset only fires
  /// from a not-currently-speaking state) -- confirmed for 11 of 26
  /// characters in one session, each swallowed by its immediate
  /// predecessor's own tail. `SpeechToTextResponseListener` uses this to
  /// force a fresh arming state per turn instead of waiting for genuine
  /// acoustic silence between answers, which back-to-back rapid speech
  /// may never actually provide.
  void Function(String character)? onResponseWindowOpened;

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
  /// for it.
  void Function(String character)? onCorrectResponse;

  /// Called (at most once per character) once its turn's outcome is
  /// finalized and [onCorrectResponse] never fired for it: wrong content,
  /// no response at all, or a response whose *onset* itself came after
  /// the window had already closed all count as missed. The exact
  /// complement of [onCorrectResponse].
  ///
  /// Deliberately **not** fired synchronously the instant the response
  /// window closes -- a match resolving after the window closes is not
  /// the same as a late response, since [onCorrectResponse] itself judges
  /// onset time, not match-completion time (a real recognizer commonly
  /// takes hundreds of ms past the window's own close to finish matching
  /// speech that started well within it, occasionally over a second).
  /// Firing at close time raced that pipeline and lost: an on-time
  /// response whose match simply hadn't resolved yet got wrongly reported
  /// as missed here moments before also being (correctly) reported as
  /// correct via [onCorrectResponse] -- confirmed on-device (2026-08-23)
  /// as the cause of nearly every character in a session getting
  /// auto-flagged as a problem character regardless of whether it was
  /// actually answered correctly.
  ///
  /// A first fix deferred the check to the *next* character's turn
  /// beginning instead of the window closing -- an improvement, but still
  /// not a safe bound: on-device data (2026-08-24, 24WPM/700ms) showed
  /// match latency routinely outlasting a single turn's own cadence,
  /// so this fired *again*, now for a response that was on track to be
  /// correctly credited a turn or two later. One character (D) came back
  /// with 5 misses that session despite genuinely being answered
  /// correctly 4 of those 5 times. [_pendingTurns] fixes this properly:
  /// a closed-but-uncredited turn stays eligible for a late credit for
  /// [_pendingResponseTimeout] of real time (not turn-boundaries), and
  /// only fires this once that's elapsed with no credit -- see
  /// [_finalizeMissed]. Never fires for a turn [stop] cut short mid-
  /// window (its window never finished closing at all, so it never
  /// entered [_pendingTurns] to begin with).
  void Function(String character)? onMissedResponse;

  // Reports [turn] as missed and drops it from [_pendingTurns] -- called
  // either by its own finalize [Timer] elapsing with no credit, or
  // directly by [stop] to finalize whatever's still outstanding rather
  // than leave it to a timer that a stopped engine will never let fire.
  // Cancelling the timer here (not just in [submitResponse]'s credit
  // path) is what makes the [stop] call site safe -- otherwise its own
  // still-pending finalize [Timer] outlives the engine.
  void _finalizeMissed(_OutstandingTurn turn) {
    turn.finalizeTimer?.cancel();
    _pendingTurns.remove(turn);
    onMissedResponse?.call(turn.character);
  }

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
  ///
  /// [at], when given, is judged instead of live state -- a
  /// [ResponseWindowSnapshot] captured back when the learner actually
  /// *started* responding (e.g. speech onset), not whenever recognition
  /// eventually finished figuring out what they said. On-device data
  /// (Milestone 13, 2026-08-22) found recognition latency alone was
  /// pushing the deadline check past close on nearly every response even
  /// when the learner started answering well within the window --
  /// judging against the snapshot instead means recognition speed no
  /// longer eats into a recognitionTime budget it was never actually
  /// needed for. Also fixes a correctness gap at tight budgets: if
  /// recognition resolves after the *next* turn has already started,
  /// the response still attributes to the turn it was actually an
  /// attempt for ([at]'s own `character`), not whatever's currently
  /// awaited -- including, per [_pendingTurns], one further back than
  /// that.
  ///
  /// Omitted (the default) -- meant for a listener with no separate
  /// onset moment to hook *at all* -- skips the live-state deadline
  /// check entirely and goes straight to the current/pending search
  /// below, unconditionally, crediting on content match alone within
  /// [_pendingResponseTimeout] with no timing judgment whatsoever.
  /// `SpeechToTextResponseListener` originally used this path
  /// unconditionally (it only ever got a finished transcript result,
  /// with no sound-level/VAD hook to approximate onset from) -- on-device
  /// data (2026-08-26, 30WPM/800ms) showed why the live-state fallback
  /// this replaced doesn't work for such a listener even as an
  /// approximation: `package:speech_to_text`'s result lag routinely
  /// exceeds a single turn's own cadence, so by the time *any* result
  /// arrives, live state has already advanced at least one full turn
  /// past the one it's actually an answer for.
  ///
  /// It later gained real onset detection and stopped using this path at
  /// all, for the opposite reason: on-device data (2026-08-28) showed its
  /// underlying `onSoundLevelChange` callback can go silent for many
  /// seconds at a stretch while transcription keeps working fine, and
  /// `at: null` in that gap meant "no timing enforcement," not "no
  /// timing evidence" -- confirmed as the cause of 7 false wins in one
  /// session where the learner deliberately answered late throughout that
  /// silent stretch. This parameter now stays reserved for a listener
  /// that genuinely has no onset concept at all, not one whose onset
  /// detection can occasionally, silently come up empty.
  void submitResponse(String character, {ResponseWindowSnapshot? at}) {
    final awaitingCharacter = at?.character ?? _awaitingResponseFor;
    final windowOpen = at?.windowOpen ?? _responseWindowOpen;
    logDebug(
      'submitResponse($character) awaiting=$awaitingCharacter '
      'windowOpen=$windowOpen',
    );
    // windowOpen surfaces the actual "beat the computer" deadline
    // (morseEnd..answerStart, via [_windowOpenTimer]/[_windowCloseTimer]
    // below) directly -- content matching alone doesn't distinguish a
    // mismatch from a same-character response that simply arrived after
    // its own window had already closed, which on-device debugging
    // (Milestone 13 step 5) needs to tell apart. Skipped for a no-onset
    // listener ([at] null) -- see this method's own doc comment.
    if (at != null && (character != awaitingCharacter || !windowOpen)) {
      return;
    }

    // The current turn is the overwhelmingly common case (matched by
    // object identity with [_currentTurn], not just character, so a
    // duplicate response for an *already*-credited current turn falls
    // through to the pending search below and correctly finds nothing).
    // Otherwise this is a late credit for an older, already-closed turn
    // -- search oldest-first so a character that recurs while an earlier
    // instance is still pending resolves to that earlier one first.
    _OutstandingTurn? turn;
    final current = _currentTurn;
    if (current != null &&
        current.character == character &&
        !current.credited) {
      turn = current;
    } else {
      for (final pending in _pendingTurns) {
        if (pending.character == character && !pending.credited) {
          turn = pending;
          break;
        }
      }
    }
    if (turn == null) return;

    turn.credited = true;
    turn.finalizeTimer?.cancel();
    _pendingTurns.remove(turn);
    onCorrectResponse?.call(character);
  }

  /// Snapshots which character (if any) the response window is
  /// currently open for, and whether it's open -- see [submitResponse]'s
  /// `at` parameter. Meant to be called synchronously at the exact
  /// instant a listener detects the learner starting to respond (not
  /// after any async work), so the live fields read here are still
  /// exactly correct for that moment.
  ResponseWindowSnapshot captureResponseWindow() =>
      (character: _awaitingResponseFor, windowOpen: _responseWindowOpen);

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
    // Finalizes every still-outstanding turn as missed before clearing
    // state below, rather than leaving them to their own finalize
    // [Timer]s -- those get cancelled by [stop] just like every other
    // pending timer, and a stopped engine should report a complete,
    // deterministic tally rather than one that depends on whether Stop
    // happened to land before or after a given turn's own timeout. A
    // turn still mid-window when Stop lands never made it into
    // [_pendingTurns] to begin with, so it's correctly left unreported
    // either way (see [onMissedResponse]'s doc comment).
    for (final turn in List<_OutstandingTurn>.of(_pendingTurns)) {
      _finalizeMissed(turn);
    }
    _awaitingResponseFor = null;
    _currentTurn = null;
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
      // The previous turn's own outcome (if any) is *not* finalized here
      // -- see [_pendingTurns]'s doc comment for why turn-boundary
      // crossing is no longer what that depends on; it stays outstanding
      // in [_pendingTurns], eligible for a late credit, independent of
      // however many further turns start in the meantime.
      _awaitingResponseFor = character;
      _currentTurn = _OutstandingTurn(character);
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
      // Milestone 13 step 5 on-device debugging: absolute open/close
      // timestamps, directly comparable against VoiceResponseListener's
      // "utterance detected"/"match took" log lines, rather than having
      // to estimate the window's position from a turn's total duration.
      _windowOpenTimer = Timer(resolvedTiming.morseEnd, () {
        _responseWindowOpen = true;
        logDebug('windowOpen($character): opened');
        onResponseWindowOpened?.call(character);
      });
      final closingTurn = _currentTurn!;
      _windowCloseTimer = Timer(resolvedTiming.answerStart, () {
        _responseWindowOpen = false;
        logDebug('windowOpen($character): closed');
        if (closingTurn.credited)
          return; // already credited -- nothing to track
        closingTurn.finalizeTimer = Timer(
          _pendingResponseTimeout,
          () => _finalizeMissed(closingTurn),
        );
        _pendingTurns.add(closingTurn);
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

/// One character's turn, tracked from the moment it's generated until
/// [TrainingEngine] finalizes it as either credited ([submitResponse]) or
/// missed ([TrainingEngine._finalizeMissed]) -- see
/// [TrainingEngine._pendingTurns]'s doc comment for why this needs to be
/// its own identity-bearing object rather than a couple of scalar fields.
class _OutstandingTurn {
  _OutstandingTurn(this.character);

  final String character;
  bool credited = false;
  // Set only once this turn's response window has closed (see
  // [TrainingEngine]'s `_windowCloseTimer`) -- null while the window is
  // still open, since nothing needs to time out yet.
  Timer? finalizeTimer;
}
