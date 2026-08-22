import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../audio/audio_session_setup.dart';
import '../audio/keep_alive_audio_loop.dart';
import '../audio/training_audio_handler.dart';
import '../audio/turn_audio_engine.dart';
import '../debug_log.dart';
import '../speech/answer_speaker.dart';
import '../speech/response_listener.dart';
import '../speech/speech_to_text_response_listener.dart';
import '../speech/tts_answer_speaker.dart';
import '../training/app_settings.dart';
import '../training/app_settings_store.dart';
import '../training/character_set.dart';
import '../training/countdown_timer_config.dart';
import '../training/countdown_timer_store.dart';
import '../training/file_app_settings_store.dart';
import '../training/file_countdown_timer_store.dart';
import '../training/file_problem_character_store.dart';
import '../training/file_training_log_store.dart';
import '../training/problem_character_store.dart';
import '../training/training_engine.dart';
import '../training/training_log_store.dart';
import '../training/training_session_record.dart';
import 'countdown_timer_settings.dart';
import 'problem_character_keyboard.dart';
import 'settings_screen.dart';
import 'training_log_screen.dart';
import 'widgets/stepped_int_control.dart';

/// The training screen wired to the character-generation loop,
/// recognition timer, computer-voice answer, and the learner's own
/// spoken response.
///
/// Provides character-speed control, recognition-time control,
/// character-set selection, and a start/stop toggle that drives
/// [TrainingEngine], which announces each character via [AnswerSpeaker]
/// once its recognition deadline lapses, unless [ResponseListener]
/// recognizes the learner saying it first. Nothing yet scores a
/// response (Milestone 14); persistence is still Milestone 10.
class TrainingScreen extends StatefulWidget {
  /// [trainingEngine], [answerSpeaker], and [responseListener] let tests
  /// substitute fakes so they don't have to exercise the real
  /// [TurnAudioEngine] platform plugin, real text-to-speech, or a real
  /// microphone; production code always omits them and gets the real
  /// implementations. [headphonesConnectedCheck] defaults to a real
  /// [hasNonSpeakerAudioOutput] platform check, and
  /// [reconfigureAudioSessionOnStart] to the real [configureAudioSession]
  /// (see [_toggleTraining] for why it exists) -- both default to real
  /// platform checks that tests override, since an unmocked
  /// `audio_session` platform-channel call hangs rather than throwing
  /// under `flutter test`, which a try/catch at the call site can't
  /// protect against.
  const TrainingScreen({
    super.key,
    TrainingEngine? trainingEngine,
    AnswerSpeaker? answerSpeaker,
    ResponseListener? responseListener,
    ProblemCharacterStore? problemCharacterStore,
    CountdownTimerStore? countdownTimerStore,
    TrainingLogStore? trainingLogStore,
    AppSettingsStore? appSettingsStore,
    Future<bool> Function() headphonesConnectedCheck = hasNonSpeakerAudioOutput,
    Future<void> Function() reconfigureAudioSessionOnStart =
        configureAudioSession,
    Future<void> Function() activateAudioSessionOnStart = activateAudioSession,
    Future<void> Function() deactivateAudioSessionOnStop =
        deactivateAudioSession,
  }) : _injectedTrainingEngine = trainingEngine,
       _injectedAnswerSpeaker = answerSpeaker,
       _injectedResponseListener = responseListener,
       _injectedProblemCharacterStore = problemCharacterStore,
       _injectedCountdownTimerStore = countdownTimerStore,
       _injectedTrainingLogStore = trainingLogStore,
       _injectedAppSettingsStore = appSettingsStore,
       _headphonesConnectedCheck = headphonesConnectedCheck,
       _reconfigureAudioSessionOnStart = reconfigureAudioSessionOnStart,
       _activateAudioSessionOnStart = activateAudioSessionOnStart,
       _deactivateAudioSessionOnStop = deactivateAudioSessionOnStop;

  final TrainingEngine? _injectedTrainingEngine;
  final AnswerSpeaker? _injectedAnswerSpeaker;
  final ResponseListener? _injectedResponseListener;
  final ProblemCharacterStore? _injectedProblemCharacterStore;
  final CountdownTimerStore? _injectedCountdownTimerStore;
  final TrainingLogStore? _injectedTrainingLogStore;
  final AppSettingsStore? _injectedAppSettingsStore;
  final Future<bool> Function() _headphonesConnectedCheck;
  final Future<void> Function() _reconfigureAudioSessionOnStart;
  final Future<void> Function() _activateAudioSessionOnStart;
  final Future<void> Function() _deactivateAudioSessionOnStop;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen>
    with WidgetsBindingObserver {
  int _wpm = 90;
  int _recognitionTimeMs = 500;
  int _extraGapMs = 0;
  final Set<CharacterSetType> _selectedCharacterSets = {
    CharacterSetType.letters,
  };
  // Non-null means a problem-character set (morse_icr_spec.md sections
  // 11, 12, 39) is the active training set, in place of whatever
  // [_selectedCharacterSets] chips are checked -- set once Done is
  // tapped in [ProblemCharacterKeyboard], or on cold launch if one was
  // already persisted (see [initState]), and cleared the moment the
  // learner taps any character-set chip again (section 39: "remains
  // active until the user selects a different character set or edits
  // the problem-character list").
  List<String>? _problemCharacters;
  // The 3 memory slots plus which one, if any, is the active timer that
  // auto-stops training (morse_icr_spec.md section 9) -- persisted via
  // [_countdownTimerStore], loaded once in [initState] the same way
  // [_problemCharacters] is.
  CountdownTimerConfig _countdownTimerConfig = const CountdownTimerConfig();
  // Non-null only while the active timer is actually counting down
  // during a training session -- null the rest of the time, so the main
  // screen falls back to displaying the selected memory's stored
  // duration (section 9: the timer value is "restored to its most
  // recent value" once a session ends, whether by the timer reaching
  // zero or the learner tapping Stop).
  Duration? _countdownRemaining;
  Timer? _countdownTicker;
  // Counts up while a session is running, next to "Training…" -- reset
  // to zero the moment Stop (manual or countdown-triggered) tears the
  // session down, same lifecycle as [_countdownTicker].
  Duration _elapsedTime = Duration.zero;
  Timer? _elapsedTicker;
  bool _isTraining = false;
  // Not shown in the UI -- tracked ahead of character-level statistics
  // (Milestone 15), which will need a played-character count. Not part
  // of the training log (Milestone 10, morse_icr_spec.md section 21)
  // itself -- Bill's own field list for that omitted it.
  int _charactersPlayed = 0;
  // Set the moment Start actually begins the training loop, read back
  // when the session ends (whether by Stop or the countdown timer
  // reaching zero) to compute the elapsed time recorded in the training
  // log (section 22).
  DateTime? _sessionStartedAt;
  // The speed/recognition-time/extra-gap settings in effect the moment
  // the session started, logged alongside it -- all three stay live-
  // adjustable mid-session, so this is the settings the learner actually
  // chose to *start* training at, not necessarily what they ended on.
  int _sessionStartWpm = 0;
  int _sessionStartRecognitionTimeMs = 0;
  int _sessionStartExtraGapMs = 0;
  bool _voiceEnabled = true;
  bool _voicePreparing = false;
  bool _recognitionEnabled = true;
  bool _lastResponseCorrect = false;
  // Settings screen preferences (morse_icr_spec.md section 35), loaded
  // from [_appSettingsStore] in initState and applied to the audio
  // engines below -- see [_applyAppSettings].
  AppSettings _appSettings = const AppSettings();

  TurnAudioEngine? _turnAudioEngine;
  KeepAliveAudioLoop? _keepAliveLoop;
  late final TrainingEngine _trainingEngine;
  late final AnswerSpeaker _answerSpeaker;
  late final ResponseListener _responseListener;
  late final ProblemCharacterStore _problemCharacterStore;
  late final CountdownTimerStore _countdownTimerStore;
  late final TrainingLogStore _trainingLogStore;
  late final AppSettingsStore _appSettingsStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _answerSpeaker = widget._injectedAnswerSpeaker ?? TtsAnswerSpeaker();
    if (widget._injectedTrainingEngine != null) {
      _trainingEngine = widget._injectedTrainingEngine!;
    } else {
      final turnEngine = TurnAudioEngine(answerSpeaker: _answerSpeaker);
      _turnAudioEngine = turnEngine;
      _trainingEngine = TrainingEngine(turnPlayer: turnEngine);
      _keepAliveLoop = KeepAliveAudioLoop();
    }
    _responseListener =
        widget._injectedResponseListener ?? SpeechToTextResponseListener();
    _problemCharacterStore =
        widget._injectedProblemCharacterStore ?? FileProblemCharacterStore();
    // Reflects a previously-saved problem-character set as the active
    // training set right from cold launch, not just for the rest of the
    // session it was entered in -- on-device testing showed a set that
    // silently reverted to "not active" (with no on-screen indication
    // why) after a force-quit, despite the underlying list itself having
    // correctly persisted, read as a bug rather than the intended
    // behavior.
    _problemCharacterStore.load().then((characters) {
      if (!mounted || characters == null || characters.isEmpty) return;
      setState(() => _problemCharacters = characters);
    });
    _countdownTimerStore =
        widget._injectedCountdownTimerStore ?? FileCountdownTimerStore();
    _countdownTimerStore.load().then((config) {
      if (!mounted) return;
      setState(() => _countdownTimerConfig = config);
    });
    _trainingLogStore =
        widget._injectedTrainingLogStore ?? FileTrainingLogStore();
    _appSettingsStore =
        widget._injectedAppSettingsStore ?? FileAppSettingsStore();
    // Applied once loaded, not just stored -- [_answerSpeaker] and
    // [_turnAudioEngine] were already constructed above (with default
    // settings, since a persisted value can't be awaited synchronously
    // here) and need correcting the moment the real settings are known,
    // the same "momentarily-stale-then-corrected" approach
    // [TtsAnswerSpeaker]'s own voice-quality selection already takes.
    _appSettingsStore.load().then((settings) {
      if (!mounted) return;
      setState(() => _appSettings = settings);
      _applyAppSettings(settings);
    });
    final answerSpeaker = _answerSpeaker;
    if (answerSpeaker is TtsAnswerSpeaker) {
      // Pre-rendering every character's spoken word (section 36) takes
      // a moment, most noticeably right after the learner installs a
      // higher-quality voice -- surface that instead of leaving early
      // announcements silently slow or missing.
      _voicePreparing = true;
      answerSpeaker.ready.whenComplete(() {
        if (mounted) setState(() => _voicePreparing = false);
      });
    }
    _trainingEngine.onCharacterGenerated = (character) {
      if (mounted) {
        setState(() {
          _charactersPlayed++;
          _lastResponseCorrect = false;
        });
      }
      // Checkpoints the recognizer so this character is matched
      // against fresh speech instead of the whole session's growing
      // transcript (morse_icr_spec.md section 27).
      unawaited(_responseListener.restart());
    };
    // The Voice switch is the sole authority on whether the computer
    // speaks -- checked once per character, at the moment its turn is
    // generated (TrainingEngine.isVoiceEnabled), so toggling it
    // mid-session takes effect starting the next character, the same
    // "never interrupts a turn already in progress" rule speed and
    // recognition-time changes already follow. Scoring the response is
    // out of scope until Milestone 14.
    //
    // No muting around this: [SpeechToTextResponseListener] keeps the
    // mic listening continuously through the computer's own
    // announcement, and on-device testing showed the phone reliably
    // re-hearing its own TTS voice and crediting it as the learner's
    // response -- but a software mute here can't distinguish that echo
    // from a genuine late response, since both land in the exact same
    // post-announcement window (ASR results lag the speech that produced
    // them by 700ms-1.5s, well past this recognition deadline). Fixed at
    // the acoustic level instead, by requiring headphones whenever
    // recognition is on (see [_toggleTraining]/[_onRecognitionChanged]),
    // so the mic has nothing of the computer's own voice to hear.
    _trainingEngine.isVoiceEnabled = () => _voiceEnabled;
    // Live-fallback only: fires when TurnAudioEngine couldn't bake the
    // answer into the turn's own pre-mixed audio (not yet cached, or
    // Voice was off when this turn was generated). The normal case needs
    // no wiring here at all -- the answer already played automatically
    // as part of the turn's own buffer (morse_icr project memory: the
    // pre-mix architecture).
    _trainingEngine.onRecognitionTimeout = _answerSpeaker.speak;
    // A simple green-dot indicator that the learner's spoken response
    // was recognized -- not scoring (Milestone 14), just visible
    // confirmation that recognition is doing something, since the
    // character itself is never shown (section 24).
    _trainingEngine.onCorrectResponse = (character) {
      if (mounted) setState(() => _lastResponseCorrect = true);
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeDebounceTimer?.cancel();
    _countdownTicker?.cancel();
    _elapsedTicker?.cancel();
    _trainingEngine.stop();
    _turnAudioEngine?.dispose();
    _keepAliveLoop?.dispose();
    _responseListener.stopListening();
    super.dispose();
  }

  // iOS sends a brief, spurious resumed->inactive->hidden->paused blip
  // right at the moment the screen locks (confirmed on-device: this
  // round-trips in well under 100ms in every captured log, vs. an
  // actual resume which persists). Reacting to that blip as a real
  // resume was itself a bug -- it tore down and recreated
  // [_keepAliveLoop]'s player (see [_reactivateAudioSession]) right as
  // iOS was about to check for continuous background playback before
  // suspending the app, so the freshly-recreated player's not-yet-
  // acknowledged play() call couldn't satisfy that check, and iOS froze
  // the whole process (not just audio) until the learner manually
  // unlocked -- confirmed via a multi-second gap with zero log
  // activity of any kind spanning exactly that window. Debouncing here
  // means a resumed event only triggers reactivation once it's held for
  // [_resumeDebounce] without another lifecycle transition superseding
  // it, so the lock-time blip is silently ignored instead.
  Timer? _resumeDebounceTimer;
  static const _resumeDebounce = Duration(milliseconds: 500);

  // iOS can silently leave the shared AVAudioSession deactivated or on
  // the wrong category after the app is backgrounded and resumed
  // without being killed -- most plausibly via
  // [SpeechToTextResponseListener]'s own category churn being
  // mid-flight when backgrounded (morse_icr_spec.md section 27).
  // Re-applying the session's configuration and (if a session is
  // running) reactivating it here means that no longer depends on the
  // process having been fully killed and relaunched to pick up a fresh
  // session.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logDebug('lifecycle: $state (isTraining=$_isTraining)');
    _resumeDebounceTimer?.cancel();
    _resumeDebounceTimer = null;
    if (state != AppLifecycleState.resumed) return;
    _resumeDebounceTimer = Timer(_resumeDebounce, () {
      _resumeDebounceTimer = null;
      unawaited(_reactivateAudioSession());
    });
  }

  Future<void> _reactivateAudioSession() async {
    try {
      await configureAudioSession();
      logDebug('reactivate: configured');
    } catch (e) {
      logDebug('reactivate: configure failed: $e');
    }
    // Confirmed on-device (-1004 "Could not connect to the server" on
    // every subsequent playCharacter call): just_audio's local
    // StreamAudioSource proxy server can go silently unreachable across
    // a background+lock+resume cycle without its own self-healing
    // noticing. Unconditional -- the break happens regardless of
    // whether a session was actively training when backgrounded (see
    // [TurnAudioEngine.resetPlayer]), and recreating an idle player is
    // harmless.
    try {
      await _turnAudioEngine?.resetPlayer();
      final answerSpeaker = _answerSpeaker;
      if (answerSpeaker is TtsAnswerSpeaker) {
        await answerSpeaker.resetPlayer();
      }
      await _keepAliveLoop?.resetPlayer();
      logDebug('reactivate: players reset');
    } catch (e) {
      logDebug('reactivate: player reset failed: $e');
    }
    if (!_isTraining) return;
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      logDebug('reactivate: setActive(true) ok');
    } catch (e) {
      logDebug('reactivate: setActive failed: $e');
    }
    try {
      await _keepAliveLoop?.start();
      logDebug('reactivate: keep-alive loop restarted');
    } catch (e) {
      logDebug('reactivate: keep-alive loop restart failed: $e');
    }
  }

  // Guards against a second tap landing while a previous call is still
  // awaiting one of the several real, potentially slow platform calls
  // below (headphone check, audio session reconfigure/activate,
  // keep-alive loop start) -- without this, a tap during that window
  // reads [_isTraining] before the in-flight call has finished acting
  // on it, does the opposite of what's actually in progress, and can
  // leave the button's label and the actual running/stopped state
  // permanently out of sync with each other. Confirmed on-device as
  // the cause of a "Stop/Start reversed" bug once these `await`s were
  // added.
  bool _togglingTraining = false;

  // [recordedDuration] lets the countdown-timer's own expiry path (see
  // [_startCountdownTicker]) log the timer's full configured duration
  // rather than a wall-clock elapsed time that's inherently a shade
  // short of it (a Timer.periodic tick doesn't land at the exact instant
  // the countdown reaches zero) -- morse_icr_spec.md section 22: "If the
  // timer reaches zero, record the full configured duration." A manual
  // Stop tap always omits it, falling back to actual wall-clock elapsed
  // time (section 22's other case).
  Future<void> _toggleTraining({Duration? recordedDuration}) async {
    if (_togglingTraining) return;
    _togglingTraining = true;
    try {
      await _toggleTrainingUnguarded(recordedDuration: recordedDuration);
    } finally {
      _togglingTraining = false;
    }
  }

  Future<void> _toggleTrainingUnguarded({Duration? recordedDuration}) async {
    if (_isTraining) {
      logDebug('stop: tapped');
      await _trainingEngine.stop();
      try {
        await _responseListener.stopListening().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        logDebug('stop: stopListening failed: $e');
      }
      if (!mounted) return;
      try {
        await widget._deactivateAudioSessionOnStop().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        // Not fatal -- audio output is an external boundary the
        // learner can't control mid-session.
      }
      // Fire-and-forget -- see the matching start() call for why.
      final keepAliveLoop = _keepAliveLoop;
      if (keepAliveLoop != null) {
        unawaited(
          keepAliveLoop.stop().catchError((Object e) {
            logDebug('stop: keep-alive loop stop failed: $e');
          }),
        );
      }
      trainingAudioHandler?.reportIdle();
      await _recordCompletedSession(recordedDuration);
      _cancelCountdownTicker();
      _cancelElapsedTicker();
      setState(() {
        _isTraining = false;
        // Reset to the memory's stored duration rather than leaving the
        // display sitting mid-countdown or at zero (morse_icr_spec.md
        // section 9: "the timer value should be restored to its most
        // recent value") -- see [_countdownDisplayText], which falls
        // back to the selected memory's stored duration whenever
        // [_countdownRemaining] is null.
        _countdownRemaining = null;
        _elapsedTime = Duration.zero;
      });
      logDebug('stop: done');
      return;
    }

    logDebug('start: tapped');
    final characters = _activeCharacters;
    if (characters.isEmpty) return;

    if (_recognitionEnabled && !await widget._headphonesConnectedCheck()) {
      if (!mounted) return;
      _showHeadphonesRequiredMessage();
      return;
    }

    _sessionStartedAt = DateTime.now();
    _sessionStartWpm = _wpm;
    _sessionStartRecognitionTimeMs = _recognitionTimeMs;
    _sessionStartExtraGapMs = _extraGapMs;
    setState(() {
      _isTraining = true;
      _charactersPlayed = 0;
      _elapsedTime = Duration.zero;
    });
    _startCountdownTicker();
    _startElapsedTicker();
    // [_reactivateAudioSession] only reconfigures on resume if a
    // session was already running (so it doesn't wake up an idle
    // session behind the learner's back) -- but that means a session
    // stopped *before* backgrounding, then locked, then resumed, never
    // gets its category reapplied at all. Reconfiguring and activating
    // fresh right here, at the moment audio is actually about to be
    // needed, doesn't depend on any earlier lifecycle event having
    // handled it correctly. Best-effort: a failure here shouldn't
    // block starting the training loop itself.
    // Every external call in this sequence is timeout-guarded: a hung
    // (not just failing) native call here previously left
    // [_togglingTraining] stuck true forever, since nothing ever
    // returned to reach the `finally` in [_toggleTraining] -- Stop
    // stopped working at all, confirmed on-device.
    const externalCallTimeout = Duration(seconds: 5);
    try {
      await widget._reconfigureAudioSessionOnStart().timeout(
        externalCallTimeout,
      );
      await widget._activateAudioSessionOnStart().timeout(externalCallTimeout);
      logDebug('start: session reconfigured and activated');
    } catch (e) {
      logDebug('start: reconfigure/activate failed: $e');
    }
    trainingAudioHandler?.reportTraining();
    // Fire-and-forget, not awaited: on-device measurement found this
    // call alone can take ~10s to resolve (vs. ~100-300ms for the
    // Morse player's own play() calls) -- likely LoopMode interacting
    // with the StreamAudioSource proxy setup. It's a background-
    // continuity nice-to-have, not something the learner's perceived
    // Start responsiveness should ever wait on; awaiting it here (even
    // with a timeout) was the direct cause of "Start does nothing for
    // several seconds."
    final keepAliveLoop = _keepAliveLoop;
    if (keepAliveLoop != null) {
      unawaited(
        keepAliveLoop.start().catchError((Object e) {
          logDebug('start: keep-alive loop failed: $e');
        }),
      );
    }
    if (_recognitionEnabled) {
      try {
        await _responseListener
            .startListening(_trainingEngine.submitResponse)
            .timeout(externalCallTimeout);
      } catch (e) {
        logDebug('start: startListening failed: $e');
      }
    }
    _trainingEngine.start(
      characters: characters,
      wpm: _wpm.toDouble(),
      recognitionTime: Duration(milliseconds: _recognitionTimeMs),
      extraGap: Duration(milliseconds: _extraGapMs),
    );
  }

  // The problem-character set, when active, entirely replaces the
  // character-set chips (morse_icr_spec.md section 39) -- not merged
  // with them.
  List<String> get _activeCharacters =>
      _problemCharacters ?? charactersForSelection(_selectedCharacterSets);

  bool get _hasSelectedCharacters => _activeCharacters.isNotEmpty;

  // The training log's summary of whichever character set or problem-
  // character list was actually active -- safe to read at Stop time
  // rather than snapshotting at Start, since both the character-set
  // chips and the Focus button are disabled for the whole session
  // (see [build]), so this can't have changed mid-session.
  String get _focusSummary {
    final problemCharacters = _problemCharacters;
    if (problemCharacters != null) return problemCharacters.join(' ');
    return _selectedCharacterSets.map((type) => type.label).join(', ');
  }

  // Appends one entry to the training log (morse_icr_spec.md section 21)
  // for the session that's ending -- called from the Stop path
  // regardless of whether Stop was tapped manually or the countdown
  // timer triggered it. A no-op if [_sessionStartedAt] is somehow unset
  // (shouldn't happen: it's set at the top of Start, and Stop only ever
  // runs while [_isTraining] is true).
  Future<void> _recordCompletedSession(Duration? recordedDuration) async {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) return;
    _sessionStartedAt = null;
    final record = TrainingSessionRecord(
      id: startedAt.microsecondsSinceEpoch.toString(),
      startedAt: startedAt,
      duration: recordedDuration ?? DateTime.now().difference(startedAt),
      focusSummary: _focusSummary,
      wpm: _sessionStartWpm,
      recognitionTimeMs: _sessionStartRecognitionTimeMs,
      extraGapMs: _sessionStartExtraGapMs,
    );
    try {
      final existing = await _trainingLogStore.load();
      await _trainingLogStore.save([...existing, record]);
    } catch (e) {
      logDebug('stop: training log save failed: $e');
    }
  }

  void _openTrainingLog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrainingLogScreen(store: _trainingLogStore),
      ),
    );
  }

  // No-op (leaves the countdown row showing "Off") unless a memory is
  // both selected and actually has a stored duration -- e.g. right after
  // its memory was cleared out from under it (morse_icr project: see
  // [CountdownTimerSettings._editSlot]'s auto-deselect).
  void _startCountdownTicker() {
    final duration = _countdownTimerConfig.selectedDuration;
    if (duration == null || duration <= Duration.zero) return;
    _countdownRemaining = duration;
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _countdownRemaining;
      if (remaining == null) return;
      final next = remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _cancelCountdownTicker();
        if (mounted) setState(() => _countdownRemaining = null);
        // Section 9: "Stop generating new training characters... Stop
        // the recognition cycle" -- the same full Stop path a manual tap
        // runs, so nothing about session teardown needs duplicating
        // here. [duration] (not the possibly-short-by-a-tick wall-clock
        // elapsed time) is what gets logged -- see [_toggleTraining]'s
        // [recordedDuration] doc.
        unawaited(_toggleTraining(recordedDuration: duration));
        return;
      }
      if (mounted) setState(() => _countdownRemaining = next);
    });
  }

  void _cancelCountdownTicker() {
    _countdownTicker?.cancel();
    _countdownTicker = null;
  }

  void _startElapsedTicker() {
    _elapsedTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _sessionStartedAt;
      if (startedAt == null) return;
      if (mounted) {
        setState(() => _elapsedTime = DateTime.now().difference(startedAt));
      }
    });
  }

  void _cancelElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
  }

  // What the main-screen timer row shows: the live countdown while one
  // is actually running, otherwise the selected memory's stored
  // duration (so it reads as ready-to-run rather than stuck at the last
  // value it counted down to), or "Off" when no memory is selected.
  String get _countdownDisplayText {
    final remaining = _countdownRemaining;
    if (remaining != null) return formatCountdown(remaining);
    final selected = _countdownTimerConfig.selectedDuration;
    if (selected != null) return formatCountdown(selected);
    return 'Off';
  }

  Future<void> _openCountdownTimerSettings() async {
    final config = await Navigator.of(context).push<CountdownTimerConfig>(
      MaterialPageRoute(
        builder: (_) => CountdownTimerSettings(store: _countdownTimerStore),
      ),
    );
    if (config == null || !mounted) return;
    setState(() => _countdownTimerConfig = config);
  }

  Future<void> _openProblemCharacterKeyboard() async {
    final characters = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ProblemCharacterKeyboard(store: _problemCharacterStore),
      ),
    );
    // Null means the learner backed out without ever tapping Done --
    // leave whatever training set was already active alone. An empty
    // (non-null) list means Done was tapped after Clear: an explicit
    // request to deactivate the problem-character set entirely, back to
    // whatever the character-set chips are checked.
    if (characters == null || !mounted) return;
    setState(() => _problemCharacters = characters.isEmpty ? null : characters);
  }

  // Speech Recognition requires headphones (see [hasNonSpeakerAudioOutput]
  // for why) -- surfaced here rather than failing silently into the
  // self-echo false positives that motivated the requirement.
  void _showHeadphonesRequiredMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Speech Recognition needs headphones (wired or Bluetooth) -- '
          'otherwise the phone hears its own spoken answers. Connect '
          'headphones, or turn off Speech Recognition in Settings.',
        ),
      ),
    );
  }

  // Shared by the Settings screen's Speech Recognition switch, whether
  // toggled before a session (no live listener to touch yet) or mid-
  // session (starts/stops listening immediately, same as the Voice
  // switch's own immediate effect on the next announcement).
  Future<void> _onRecognitionChanged(bool value) async {
    if (value && !await widget._headphonesConnectedCheck()) {
      if (!mounted) return;
      _showHeadphonesRequiredMessage();
      return;
    }
    setState(() => _recognitionEnabled = value);
    if (!_isTraining) return;
    if (value) {
      unawaited(
        _responseListener.startListening(_trainingEngine.submitResponse),
      );
    } else {
      unawaited(_responseListener.stopListening());
    }
  }

  // Pushes [settings] out to the audio engines that actually act on them
  // (section 35) -- called both right after a fresh load (see initState)
  // and after every live change from the Settings screen. Morse
  // pitch/volume only take effect on the next turn rendered, the same
  // "never interrupts a turn already in progress" rule WPM/recognition-
  // time/extra-gap changes already follow; the "." / "/" spelling
  // change re-renders just those two characters.
  void _applyAppSettings(AppSettings settings) {
    _turnAudioEngine?.updateMorseSettings(
      frequencyHz: settings.morsePitchHz.toDouble(),
      amplitude: settings.morseVolumePercent / 100,
    );
    final answerSpeaker = _answerSpeaker;
    if (answerSpeaker is TtsAnswerSpeaker) {
      unawaited(
        answerSpeaker.updatePunctuationSpelling(
          speakPeriodAsDot: settings.speakPeriodAsDot,
          speakSlashAsStroke: settings.speakSlashAsStroke,
        ),
      );
      answerSpeaker.setVoiceVolume(settings.voiceVolumePercent / 100);
    }
  }

  // Persists, applies, and reflects in this screen's own state one
  // change from the Settings screen -- shared by every `on...Changed`
  // callback [_openSettings] wires up below.
  void _updateAppSettings(AppSettings settings) {
    setState(() => _appSettings = settings);
    _applyAppSettings(settings);
    unawaited(_appSettingsStore.save(settings));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          voiceEnabled: _voiceEnabled,
          voicePreparing: _voicePreparing,
          recognitionEnabled: _recognitionEnabled,
          speakPeriodAsDot: _appSettings.speakPeriodAsDot,
          speakSlashAsStroke: _appSettings.speakSlashAsStroke,
          morsePitchHz: _appSettings.morsePitchHz,
          morseVolumePercent: _appSettings.morseVolumePercent,
          voiceVolumePercent: _appSettings.voiceVolumePercent,
          onVoiceChanged: (value) => setState(() => _voiceEnabled = value),
          onRecognitionChanged: _onRecognitionChanged,
          onSpeakPeriodAsDotChanged: (value) => _updateAppSettings(
            _appSettings.copyWith(speakPeriodAsDot: value),
          ),
          onSpeakSlashAsStrokeChanged: (value) => _updateAppSettings(
            _appSettings.copyWith(speakSlashAsStroke: value),
          ),
          onMorsePitchChanged: (value) =>
              _updateAppSettings(_appSettings.copyWith(morsePitchHz: value)),
          onMorseVolumeChanged: (value) => _updateAppSettings(
            _appSettings.copyWith(morseVolumePercent: value),
          ),
          onVoiceVolumeChanged: (value) => _updateAppSettings(
            _appSettings.copyWith(voiceVolumePercent: value),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Morse ICR'),
        leading: IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Training Log',
          onPressed: _openTrainingLog,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SectionCard(
                    title: 'Training Settings',
                    child: Column(
                      children: [
                        SteppedIntControl(
                          label: 'Character Speed',
                          value: _wpm,
                          min: 15,
                          max: 120,
                          step: 1,
                          suffix: 'WPM',
                          onChanged: (v) {
                            setState(() => _wpm = v);
                            _trainingEngine.updateSettings(wpm: v.toDouble());
                          },
                        ),
                        const SizedBox(height: 24),
                        SteppedIntControl(
                          label: 'Recognition Time',
                          value: _recognitionTimeMs,
                          min: 50,
                          max: 1000,
                          step: 1,
                          suffix: 'ms',
                          onChanged: (v) {
                            setState(() => _recognitionTimeMs = v);
                            _trainingEngine.updateSettings(
                              recognitionTime: Duration(milliseconds: v),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        SteppedIntControl(
                          label: 'Extra Gap',
                          value: _extraGapMs,
                          min: 0,
                          max: 1000,
                          step: 1,
                          suffix: 'ms',
                          onChanged: (v) {
                            setState(() => _extraGapMs = v);
                            _trainingEngine.updateSettings(
                              extraGap: Duration(milliseconds: v),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _isTraining ? null : _openCountdownTimerSettings,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Timer',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Text(
                              _countdownDisplayText,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: _countdownRemaining != null
                                        ? colorScheme.primary
                                        : null,
                                    fontWeight: _countdownRemaining != null
                                        ? FontWeight.bold
                                        : null,
                                  ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              color: _isTraining
                                  ? Theme.of(context).disabledColor
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    title: 'Character Set',
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final type in CharacterSetType.values)
                              FilterChip(
                                label: Text(type.label),
                                showCheckmark: false,
                                selected: _selectedCharacterSets.contains(
                                  type,
                                ),
                                selectedColor: colorScheme.primaryContainer,
                                onSelected: _isTraining
                                    ? null
                                    : (selected) {
                                        setState(() {
                                          if (selected) {
                                            _selectedCharacterSets.add(type);
                                          } else {
                                            _selectedCharacterSets.remove(
                                              type,
                                            );
                                          }
                                          // Selecting a chip at all --
                                          // even just deselecting one --
                                          // supersedes an active problem-
                                          // character set (morse_icr_spec.md
                                          // section 39).
                                          _problemCharacters = null;
                                        });
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: OutlinedButton(
                            // Matches the character-set FilterChips' own
                            // rounded-rectangle shape (Material 3's
                            // default chip shape: an 8.0 circular border
                            // radius) rather than OutlinedButton's
                            // default pill/stadium shape, for visual
                            // consistency between the two character-set-
                            // selection controls on this screen.
                            style: OutlinedButton.styleFrom(
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(8),
                                ),
                              ),
                              foregroundColor: _problemCharacters != null
                                  ? colorScheme.primary
                                  : null,
                              side: _problemCharacters != null
                                  ? BorderSide(color: colorScheme.primary)
                                  : null,
                            ),
                            onPressed: _isTraining
                                ? null
                                : _openProblemCharacterKeyboard,
                            child: Text(
                              _problemCharacters == null
                                  ? 'Focus (none)'
                                  : 'Focus (${_problemCharacters!.length} active)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _isTraining
                            ? colorScheme.tertiaryContainer
                            : colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isTraining ? 'Training…' : 'Idle',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _isTraining
                                      ? colorScheme.onTertiaryContainer
                                      : null,
                                ),
                          ),
                          if (_isTraining) ...[
                            const SizedBox(width: 8),
                            Text(
                              formatCountdown(_elapsedTime),
                              key: const Key('elapsedTimeDisplay'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                  ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              key: const Key('correctResponseIndicator'),
                              width: 12,
                              height: 12,
                              child: _lastResponseCorrect
                                  ? const DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.green,
                                        shape: BoxShape.circle,
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isTraining ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _isTraining || _hasSelectedCharacters
                        ? _toggleTraining
                        : null,
                    child: Text(_isTraining ? 'Stop' : 'Start'),
                  ),
                  const SizedBox(height: 16),
                  _DebugLogPanel(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tinted, rounded grouping container for a related cluster of main-
/// screen controls (Training Settings, Timer, Character Set), giving the
/// page visual structure and a "splash of color" (Bill's own framing)
/// beyond plain stacked text and controls. Uses Material 3's
/// `surfaceContainerHigh` tonal-elevation color -- the recommended way
/// to differentiate a raised grouping from the page background without
/// picking an arbitrary custom color -- and, when [title] is given, an
/// accent-colored label using the theme's own primary color so every
/// section reads as part of one cohesive scheme.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    this.title,
    this.padding = const EdgeInsets.all(16),
    required this.child,
  });

  final String? title;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Text(
                title!,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

// Temporary diagnostic panel for the audio-session bug under
// investigation -- see lib/debug_log.dart. Copyable because release
// builds on this project's test device have no readable console
// output. Remove once that bug is confirmed fixed on-device.
class _DebugLogPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: debugLogEntries,
      builder: (context, entries, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Debug log (${entries.length})',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: entries.join('\n')),
                        ),
                  child: const Text('Copy log'),
                ),
                TextButton(
                  onPressed: entries.isEmpty
                      ? null
                      : () => debugLogEntries.value = [],
                  child: const Text('Clear'),
                ),
              ],
            ),
            Container(
              height: 160,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: SelectableText(
                  entries.isEmpty ? '(no log entries yet)' : entries.join('\n'),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
