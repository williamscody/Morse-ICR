import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../audio/audio_session_setup.dart';
import '../audio/keep_alive_audio_loop.dart';
import '../audio/notification_permission.dart';
import '../audio/training_audio_handler.dart';
import '../audio/turn_audio_engine.dart';
import '../debug_log.dart';
import '../speech/answer_speaker.dart';
import '../speech/enrollment_store.dart';
import '../speech/file_enrollment_store.dart';
import '../speech/response_listener.dart';
import '../speech/speech_to_text_response_listener.dart';
import '../speech/tts_answer_speaker.dart';
import '../speech/tts_voice_option.dart';
import '../speech/voice_response_listener.dart';
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
import 'enrollment_screen.dart';
import 'help_screen.dart';
import 'problem_character_keyboard.dart';
import 'settings_screen.dart';
import 'training_log_screen.dart';
import 'widgets/stepped_int_control.dart';

// See lib/debug_log.dart's own note -- kept as a flip-able flag, not
// deleted, for the next hard-to-diagnose on-device bug.
//
// 2026-09-02: turned back on, then off again the same day -- see
// debug_log.dart's matching note for what got fixed.
const bool _showDebugLogPanel = false;

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
    EnrollmentStore? enrollmentStore,
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
       _injectedEnrollmentStore = enrollmentStore,
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
  final EnrollmentStore? _injectedEnrollmentStore;
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
  // True only between a Pause tap and the matching Resume/Stop -- the
  // session itself stays "in progress" (_isTraining remains true, so
  // Character Set/Focus/Timer-row stay disabled exactly as they already
  // are for the rest of a session) but the training engine, response
  // listener, and audio session are torn down exactly the way Stop tears
  // them down, and rebuilt exactly the way Start rebuilds them on Resume
  // -- reusing that already-hardened teardown/rebuild path rather than
  // inventing a genuinely-still-running "paused" engine state.
  bool _isPaused = false;
  // Set the instant Pause is tapped, consumed by Resume to shift
  // [_sessionStartedAt] forward by however long the pause actually
  // lasted -- so both the live elapsed-time ticker and the eventual
  // training-log duration (both computed as `DateTime.now() -
  // _sessionStartedAt`) transparently exclude paused time without a
  // separate accumulator field.
  DateTime? _pausedAt;
  // Not shown in the UI -- tracked ahead of character-level statistics
  // (Milestone 15), which will need a played-character count. Not part
  // of the training log (Milestone 10, morse_icr_spec.md section 21)
  // itself -- Bill's own field list for that omitted it.
  int _charactersPlayed = 0;
  // Per-character hit/miss tallies for this session, cleared at Start --
  // the raw material [_persistMissedCharacters] uses at Stop to decide
  // what to auto-populate into Problem Characters (morse_icr_spec.md
  // section 39). Deliberately *not* a single "ever missed" set: a normal
  // session cycles the active characters multiple times, and on-device
  // testing (2026-08-23, 28WPM/500ms) found that flagging on any single
  // miss -- even one immediately followed by a correct answer next time
  // around -- flagged nearly the entire trained set, since almost every
  // character gets missed at least once somewhere in a longer session.
  // Tallying hits and misses instead lets [_persistMissedCharacters] flag
  // only characters actually missed *more often than not*, which is what
  // "problem character" is meant to mean.
  final Map<String, int> _sessionHits = {};
  final Map<String, int> _sessionMisses = {};
  // Whether Speech Recognition was actually on for this session, frozen
  // at Start the same way wpm/recognitionTime/extraGap are below -- gates
  // whether [_sessionHits]/[_sessionMisses] are populated at all. Without
  // this, a session run with recognition off would have
  // TrainingEngine.onMissedResponse fire for literally every character
  // (nothing can ever be credited correct with no listener running),
  // flooding the problem-character list with the entire active set.
  bool _recognitionActiveThisSession = false;
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
  // Populated once [TtsAnswerSpeaker.voiceSelectionReady] resolves,
  // alongside [_voicePreparing] going false -- see initState. Not
  // [TtsAnswerSpeaker.ready] (2026-09-05): that additionally waits on
  // every character finishing pre-render, which under a slow/glitchy
  // voice (Samantha (Enhanced) on this device/iOS version) left this
  // list empty -- and the Settings "Speech Voice" picker stuck showing
  // "Auto" -- for as long as that took, sometimes minutes, even though
  // which voice to use had already been decided almost immediately.
  // Empty (rather than awaited synchronously) until then, same
  // "momentarily-stale" pattern as everything else seeded from
  // [_appSettingsStore]'s async load.
  List<TtsVoiceOption> _availableVoices = [];
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
  late final EnrollmentStore _enrollmentStore;
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
      // iOS-only (see KeepAliveAudioLoop's own doc comment): it exists
      // purely to keep iOS's UIBackgroundModes "audio" grant continuously
      // satisfied. Android has no equivalent heuristic to satisfy -- once
      // the foreground service (section 42, Android background audio) is
      // running, the process stays scheduled regardless of what audio is
      // or isn't playing at any given instant, so this near-silent tone
      // would just be redundant background CPU/battery use there. Every
      // call site below already reads this via `?.`, so leaving it null
      // on Android makes them all no-ops for free.
      if (Platform.isIOS) _keepAliveLoop = KeepAliveAudioLoop();
    }
    _problemCharacterStore =
        widget._injectedProblemCharacterStore ?? FileProblemCharacterStore();
    _enrollmentStore = widget._injectedEnrollmentStore ?? FileEnrollmentStore();
    // Milestone 13's enrollment-trained (MFCC/DTW) recognizer was the
    // production ResponseListener from step 5 (2026-08-23) until
    // 2026-08-26, when on-device testing via EnrollmentScreen's Test
    // mode found persistent confusion on classically hard-to-distinguish
    // letter names (M/N, T/K, A pulling in L/O/I/E) that careful
    // re-enrollment didn't meaningfully improve -- read as a ceiling on
    // few-shot DTW-over-MFCC against a handful of personal recordings,
    // not a tunable bug. Reverted to the general-purpose
    // package:speech_to_text engine this originally replaced: a full
    // acoustic+language model trained on vastly more data should handle
    // these classic confusions better than nearest-neighbor distance
    // over ~3 samples. The original reason *that* engine was replaced --
    // 700ms-1.5s recognition latency corrupting the "beat the computer"
    // timing judgment -- no longer applies now that TrainingEngine judges
    // timing at speech *onset* (Milestone 13, 2026-08-22) rather than
    // whenever a match finishes resolving, so latency no longer eats
    // into the recognitionTime budget the way it used to. Still no
    // engine-selection toggle, per Bill's standing decision -- one
    // canonical production listener. The MFCC/DTW engine and
    // EnrollmentScreen are left in place, just unused here, in case this
    // doesn't pan out either.
    _responseListener =
        widget._injectedResponseListener ?? SpeechToTextResponseListener();
    // Lets any onset-capable listener (VoiceResponseListener,
    // SpeechToTextResponseListener) snapshot "beat the computer" timing
    // the instant it detects the learner starting to respond, rather
    // than only being able to judge timing once recognition fully
    // resolves what they said (Milestone 13, 2026-08-22 -- see
    // TrainingEngine.submitResponse's `at` parameter). A one-time
    // wire-up since both objects live for the whole widget lifetime,
    // unlike updateActiveCharacters below which changes per session.
    final responseListener = _responseListener;
    // Dart doesn't promote a local through an `is` check into an
    // unrelated interface/mixin type (only into a subtype of its own
    // declared type) -- an explicit cast is needed even though the
    // check above already guarantees it's safe.
    if (responseListener is OnsetDetectingResponseListener) {
      (responseListener as OnsetDetectingResponseListener)
              .captureResponseWindow =
          _trainingEngine.captureResponseWindow;
      // Lets the listener re-arm onset detection right when a turn's
      // window opens rather than only on acoustic silence -- see
      // TrainingEngine.onResponseWindowOpened's own doc comment
      // (2026-08-28) for why waiting for silence isn't reliable enough
      // between back-to-back rapid answers.
      _trainingEngine.onResponseWindowOpened = (character) {
        (responseListener as OnsetDetectingResponseListener).armForNewTurn();
      };
    }
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
      setState(() {
        _appSettings = settings;
        _wpm = settings.characterSpeedWpm;
        _recognitionTimeMs = settings.recognitionTimeMs;
        _extraGapMs = settings.extraGapMs;
        _voiceEnabled = settings.voiceEnabled;
        _recognitionEnabled = settings.recognitionEnabled;
        // Excludes Word even if a learner selected it before it was
        // hidden from the chip row above -- otherwise a persisted
        // selection of just Word would restore to an active set with no
        // characters in it (charactersForSelection) and no way to fix
        // that from the UI, since there's no chip left to deselect it
        // with (Bill, 2026-08-31).
        final restored =
            {
              for (final name in settings.selectedCharacterSetNames)
                CharacterSetType.values.asNameMap()[name],
            }..removeWhere(
              (type) => type == null || type == CharacterSetType.words,
            );
        if (restored.isNotEmpty) {
          _selectedCharacterSets
            ..clear()
            ..addAll(restored.cast<CharacterSetType>());
        }
      });
      _applyAppSettings(settings);
    });
    final answerSpeaker = _answerSpeaker;
    if (answerSpeaker is TtsAnswerSpeaker) {
      // Voice selection (which installed voice will actually speak)
      // settles quickly; watching that alone -- not the much slower
      // [TtsAnswerSpeaker.ready], which additionally waits on every
      // character finishing pre-render -- is what keeps this spinner and
      // the Settings voice picker responsive even when pre-rendering
      // itself is slow or repeatedly hitting the known AVSpeechSynthesizer
      // hang under a voice like Samantha (Enhanced) (morse_icr project
      // memory). Pre-rendering keeps running in the background regardless
      // of this; [speak] already falls back to live synthesis for
      // whatever isn't cached yet.
      _voicePreparing = true;
      answerSpeaker.voiceSelectionReady.whenComplete(() {
        if (mounted) {
          setState(() {
            _voicePreparing = false;
            _availableVoices = answerSpeaker.availableVoices;
          });
        }
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
    // No muting around this: the mic listens continuously through the
    // computer's own announcement, and on-device testing (with the
    // general-purpose speech_to_text engine this app used before
    // Milestone 13's enrollment-trained recognizer) showed the phone
    // reliably re-hearing its own TTS voice and crediting it as the
    // learner's response -- but a software mute here can't distinguish
    // that echo from a genuine late response, since both land in the
    // exact same post-announcement window. Fixed at the acoustic level
    // instead, by requiring headphones whenever
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
      if (_recognitionActiveThisSession) {
        _sessionHits[character] = (_sessionHits[character] ?? 0) + 1;
      }
    };
    // Feeds this session's per-character hit/miss tally, which
    // [_persistMissedCharacters] uses at Stop to auto-populate Problem
    // Characters (morse_icr_spec.md section 39) -- see
    // [_recognitionActiveThisSession] for why this is gated rather than
    // unconditional.
    _trainingEngine.onMissedResponse = (character) {
      if (_recognitionActiveThisSession) {
        _sessionMisses[character] = (_sessionMisses[character] ?? 0) + 1;
      }
    };
    // Lets the lock screen's Play/Pause control drive the same
    // pause/resume toggle the on-screen buttons use -- [_togglePause] is
    // already bidirectional (it checks [_isPaused] itself), so either
    // callback wired to it produces the correct result regardless of
    // which direction the lock screen's single toggle was actually in.
    trainingAudioHandler?.onPlayRequested = _togglePause;
    trainingAudioHandler?.onPauseRequested = _togglePause;
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
    // trainingAudioHandler outlives this screen (set once at app startup)
    // -- clear its callbacks rather than leave them pointing at a
    // disposed State.
    if (trainingAudioHandler?.onPlayRequested == _togglePause) {
      trainingAudioHandler?.onPlayRequested = null;
    }
    if (trainingAudioHandler?.onPauseRequested == _togglePause) {
      trainingAudioHandler?.onPauseRequested = null;
    }
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
  // without being killed -- originally traced to the general-purpose
  // speech_to_text engine's own category churn being mid-flight when
  // backgrounded (morse_icr_spec.md section 27; that engine was later
  // replaced by Milestone 13's enrollment-trained recognizer, but this
  // reactivation safeguard hasn't been re-verified as unnecessary, so it
  // stays). Re-applying the session's configuration and (if a session is
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
      await _persistMissedCharacters();
      await _persistCharacterScores();
      _cancelCountdownTicker();
      _cancelElapsedTicker();
      setState(() {
        _isTraining = false;
        _isPaused = false;
        _pausedAt = null;
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
    _recognitionActiveThisSession = _recognitionEnabled;
    _sessionHits.clear();
    _sessionMisses.clear();
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
    // Fire-and-forget -- a denial doesn't block training, it just means
    // Android's foreground-service notification (and lock-screen card)
    // won't be visible (section 42, Android background audio). A no-op
    // on iOS and pre-13 Android.
    unawaited(requestNotificationPermissionIfNeeded());
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
      final responseListener = _responseListener;
      if (responseListener is VoiceResponseListener) {
        responseListener.updateActiveCharacters(characters);
      }
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

  // Reuses [_togglingTraining] as a single "a main-button action is in
  // flight" guard shared with Start/Stop, rather than a separate flag --
  // Pause/Resume await several of the same real, potentially slow
  // platform calls Start/Stop do, and a Stop tap racing a still-in-flight
  // Resume is exactly the kind of state-desync [_togglingTraining] was
  // introduced to prevent there.
  //
  // [!_isTraining] guard: on Android, the OS's own "media resumption"
  // feature (section 42, Android background audio) independently binds
  // to this app's declared MediaBrowserService the moment a session ever
  // starts, and keeps showing a stale Play/Pause card for a while even
  // after a real Stop -- confirmed on-device via `dumpsys activity
  // services` showing com.android.systemui itself holding the service
  // bound, which is what blocks the service from actually tearing down
  // on its own schedule. That's an Android platform behavior for any app
  // using a MediaSession, not a bug in this app's own Stop path (which
  // does correctly transition to idle) -- but it means a stale tap on
  // that lingering card can still reach [onPlayRequested]/
  // [onPauseRequested] after the real session is long gone. Without this
  // guard, [_isPaused] alone decides pause-vs-resume regardless of
  // [_isTraining], and a stray tap would call [_pauseUnguarded] on a
  // session that isn't running, leaving [_isPaused] stuck true while
  // [_isTraining] is false.
  Future<void> _togglePause() async {
    if (!_isTraining) return;
    if (_togglingTraining) return;
    _togglingTraining = true;
    try {
      if (_isPaused) {
        await _resumeUnguarded();
      } else {
        await _pauseUnguarded();
      }
    } finally {
      _togglingTraining = false;
    }
  }

  // Tears the session down exactly the way Stop does -- engine, response
  // listener, keep-alive tone, and the shared audio session -- without
  // recording a training-log entry or touching problem-character/score
  // persistence (unlike Stop, this session isn't over: [_isTraining]
  // stays true, [_sessionHits]/[_sessionMisses] are left alone for
  // [_resumeUnguarded] or a later real Stop to eventually persist). Both
  // tickers are cancelled but *not* reset -- [_countdownRemaining] and
  // [_elapsedTime] stay frozen at whatever they last showed, for
  // [_resumeCountdownTicker]/[_startElapsedTicker] to continue from.
  Future<void> _pauseUnguarded() async {
    logDebug('pause: tapped');
    _pausedAt = DateTime.now();
    await _trainingEngine.stop();
    try {
      await _responseListener.stopListening().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      logDebug('pause: stopListening failed: $e');
    }
    if (!mounted) return;
    try {
      await widget._deactivateAudioSessionOnStop().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      // Not fatal -- audio output is an external boundary the learner
      // can't control mid-session.
    }
    final keepAliveLoop = _keepAliveLoop;
    if (keepAliveLoop != null) {
      unawaited(
        keepAliveLoop.stop().catchError((Object e) {
          logDebug('pause: keep-alive loop stop failed: $e');
        }),
      );
    }
    // Keeps the lock-screen "Now Playing" card up, showing a Play
    // control, rather than dropping it the way a real Stop does -- the
    // session itself hasn't ended.
    trainingAudioHandler?.reportPaused();
    _cancelCountdownTicker();
    _cancelElapsedTicker();
    if (!mounted) return;
    setState(() => _isPaused = true);
    logDebug('pause: done');
  }

  // Rebuilds the session exactly the way Start does -- headphone check,
  // audio session reconfigure/activate, keep-alive tone, response
  // listener, and a fresh TrainingEngine.start() call -- using the
  // *live* current speed/recognition-time/extra-gap/character-set values
  // rather than the ones frozen at the original Start, matching how
  // those controls already stay live-adjustable mid-session.
  Future<void> _resumeUnguarded() async {
    logDebug('resume: tapped');
    if (_recognitionEnabled && !await widget._headphonesConnectedCheck()) {
      if (!mounted) return;
      _showHeadphonesRequiredMessage();
      return;
    }
    final pausedAt = _pausedAt;
    final startedAt = _sessionStartedAt;
    if (pausedAt != null && startedAt != null) {
      // Shifts the session's own start-time anchor forward by exactly
      // how long this pause lasted, so every later computation still
      // derived from it (the elapsed-time ticker, and the eventual
      // training-log duration at a real Stop) transparently excludes
      // paused time with no separate accumulator field needed.
      _sessionStartedAt = startedAt.add(DateTime.now().difference(pausedAt));
    }
    _pausedAt = null;
    const externalCallTimeout = Duration(seconds: 5);
    try {
      await widget._reconfigureAudioSessionOnStart().timeout(
        externalCallTimeout,
      );
      await widget._activateAudioSessionOnStart().timeout(externalCallTimeout);
      logDebug('resume: session reconfigured and activated');
    } catch (e) {
      logDebug('resume: reconfigure/activate failed: $e');
    }
    trainingAudioHandler?.reportTraining();
    final keepAliveLoop = _keepAliveLoop;
    if (keepAliveLoop != null) {
      unawaited(
        keepAliveLoop.start().catchError((Object e) {
          logDebug('resume: keep-alive loop failed: $e');
        }),
      );
    }
    final characters = _activeCharacters;
    if (_recognitionEnabled) {
      final responseListener = _responseListener;
      if (responseListener is VoiceResponseListener) {
        responseListener.updateActiveCharacters(characters);
      }
      try {
        await _responseListener
            .startListening(_trainingEngine.submitResponse)
            .timeout(externalCallTimeout);
      } catch (e) {
        logDebug('resume: startListening failed: $e');
      }
    }
    _trainingEngine.start(
      characters: characters,
      wpm: _wpm.toDouble(),
      recognitionTime: Duration(milliseconds: _recognitionTimeMs),
      extraGap: Duration(milliseconds: _extraGapMs),
    );
    _resumeCountdownTicker();
    _startElapsedTicker();
    if (!mounted) return;
    setState(() => _isPaused = false);
    logDebug('resume: done');
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

  // Flags this session's *majority-missed* characters for review
  // (morse_icr_spec.md section 39) -- additive, never clearing an
  // already-flagged character just because this particular session
  // didn't happen to miss it. A character only counts as missed here if
  // [_sessionMisses] outweighs [_sessionHits] for it -- missed strictly
  // more often than it was answered correctly -- not on any single miss,
  // so a character gotten wrong once but right the next time it comes up
  // in the same session doesn't get flagged (see [_sessionHits]'s doc
  // comment for why).
  //
  // Deliberately does *not* merge these into the persisted Focus
  // character list itself -- only [saveAutoFlagged]. An earlier version
  // did merge them in, which silently expanded the active training set
  // (and [ProblemCharacterKeyboard]'s own "Focus (n active)" count) with
  // characters the learner never actually chose; worse, since
  // [ProblemCharacterKeyboard] deliberately doesn't border an
  // unreviewed auto-flagged chip (that border is reserved for a
  // character the learner picked), those silently-added characters
  // looked completely unselected there despite genuinely being active --
  // on-device testing (2026-08-26) found this needed two taps to
  // actually select such a character (the first tap *deselected* the
  // invisible pre-existing selection, the second one reselected it) and
  // left "Focus (10 active)" on this screen with no visible relationship
  // to what was actually bordered on that one. Flagging without merging
  // means auto-detected characters surface as a suggestion (and, once
  // scored, via [ProblemCharacterKeyboard]'s heat-map color) without
  // silently joining what actually trains next -- only a character the
  // learner has actually tapped there does that now.
  Future<void> _persistMissedCharacters() async {
    final flagged = {
      for (final entry in _sessionMisses.entries)
        if (entry.value > (_sessionHits[entry.key] ?? 0)) entry.key,
    };
    if (flagged.isEmpty) return;
    try {
      final existing = await _problemCharacterStore.loadAutoFlagged();
      await _problemCharacterStore.saveAutoFlagged({...existing, ...flagged});
    } catch (e) {
      logDebug('stop: problem-character auto-flag failed: $e');
    }
  }

  // Folds this session's per-character correct-answer tally
  // ([_sessionHits]) into the persisted, all-time win score that drives
  // [ProblemCharacterKeyboard]'s heat-map chip coloring. Additive across
  // sessions, unlike [_sessionHits] itself which resets at every Start --
  // a no-op when recognition wasn't active this session, since
  // [_sessionHits]/[_sessionMisses] are only ever populated while
  // [_recognitionActiveThisSession] is true.
  //
  // Every character *attempted* this session -- [_sessionHits] union
  // [_sessionMisses], not just [_sessionHits] -- gets an entry in the
  // saved map, defaulting to 0 if it's never been credited a hit at all.
  // [ProblemCharacterKeyboard] treats "has an entry" (even a 0) as "was
  // actually trained" and "no entry" as "never trained" -- on-device
  // testing (2026-08-25) found that keying presence off [_sessionHits]
  // alone left every character the learner always got wrong (a real,
  // meaningful all-red result) looking identical to one that was never
  // part of any session at all (correctly transparent), since both read
  // as score 0 with no way to tell them apart.
  Future<void> _persistCharacterScores() async {
    final attempted = {..._sessionHits.keys, ..._sessionMisses.keys};
    if (attempted.isEmpty) return;
    try {
      final scores = {...await _problemCharacterStore.loadScores()};
      // Cumulative attempt count (hits + misses) alongside the existing
      // cumulative hit count -- together they let
      // [ProblemCharacterKeyboard] compute an all-time "X% Correct"
      // summary (morse_icr_spec.md's Focus Characters screen, 2026-08-31)
      // without which only the numerator (hits) would ever be known.
      final attempts = {...await _problemCharacterStore.loadAttempts()};
      for (final character in attempted) {
        final hits = _sessionHits[character] ?? 0;
        final misses = _sessionMisses[character] ?? 0;
        scores[character] = (scores[character] ?? 0) + hits;
        attempts[character] = (attempts[character] ?? 0) + hits + misses;
      }
      await _problemCharacterStore.saveScores(scores);
      await _problemCharacterStore.saveAttempts(attempts);
    } catch (e) {
      logDebug('stop: character-score persist failed: $e');
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
    _runCountdownTicker();
  }

  // Restarts the countdown from wherever [_countdownRemaining] was frozen
  // at when Pause cancelled the previous ticker (see [_pauseUnguarded]) --
  // a no-op if there's no active timer memory to resume (the Timer row
  // was "Off" for this whole session).
  void _resumeCountdownTicker() {
    if (_countdownRemaining == null) return;
    _runCountdownTicker();
  }

  void _runCountdownTicker() {
    // Read fresh rather than closing over a value captured back at
    // [_startCountdownTicker] -- the Timer row is disabled for the whole
    // session (including while paused), so this can't actually change
    // mid-session, but re-reading means [_resumeCountdownTicker] doesn't
    // need its own copy threaded through a pause/resume boundary to log
    // the timer's original full duration correctly on eventual expiry.
    final fullDuration = _countdownTimerConfig.selectedDuration;
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
        // here. [fullDuration] (not the possibly-short-by-a-tick
        // wall-clock elapsed time) is what gets logged -- see
        // [_toggleTraining]'s [recordedDuration] doc.
        unawaited(_toggleTraining(recordedDuration: fullDuration));
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

  // Milestone 13 step 5 (morse_icr_spec.md section 38): opens voice
  // enrollment, reached via Settings' "Personalize Recognition" button
  // (Bill's placement decision -- it configures Speech Recognition, so
  // it lives with that toggle rather than as a standalone entry point).
  Future<void> _openEnrollmentScreen() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EnrollmentScreen(store: _enrollmentStore),
      ),
    );
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
    _persistMainScreenSettings();
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
      unawaited(
        answerSpeaker.setPreferredVoice(
          name: settings.selectedVoiceName.isEmpty
              ? null
              : settings.selectedVoiceName,
          locale: settings.selectedVoiceLocale.isEmpty
              ? null
              : settings.selectedVoiceLocale,
        ),
      );
    }
    _trainingEngine.randomCharacterOrder = settings.randomCharacterOrder;
  }

  // Persists, applies, and reflects in this screen's own state one
  // change from the Settings screen -- shared by every `on...Changed`
  // callback [_openSettings] wires up below.
  void _updateAppSettings(AppSettings settings) {
    setState(() => _appSettings = settings);
    _applyAppSettings(settings);
    unawaited(_appSettingsStore.save(settings));
  }

  // Persists whichever of this screen's own live-adjustable controls
  // (Character Speed, Recognition Time, Extra Gap, Character Set, Voice,
  // Speech Recognition) aren't already routed through [_updateAppSettings]
  // -- called after every `setState` that touches one of those fields, so
  // a force quit never silently reverts the main screen to its hardcoded
  // defaults (Bill, 2026-08-30).
  void _persistMainScreenSettings() {
    _appSettings = _appSettings.copyWith(
      characterSpeedWpm: _wpm,
      recognitionTimeMs: _recognitionTimeMs,
      extraGapMs: _extraGapMs,
      selectedCharacterSetNames: [
        for (final type in _selectedCharacterSets) type.name,
      ],
      voiceEnabled: _voiceEnabled,
      recognitionEnabled: _recognitionEnabled,
    );
    unawaited(_appSettingsStore.save(_appSettings));
  }

  void _openHelp() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
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
          randomCharacterOrder: _appSettings.randomCharacterOrder,
          voiceOptions: _availableVoices,
          selectedVoiceName: _appSettings.selectedVoiceName,
          selectedVoiceLocale: _appSettings.selectedVoiceLocale,
          onVoiceChanged: (value) {
            setState(() => _voiceEnabled = value);
            _persistMainScreenSettings();
          },
          onRecognitionChanged: _onRecognitionChanged,
          onOpenVoiceSetup: _openEnrollmentScreen,
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
          onRandomCharacterOrderChanged: (value) => _updateAppSettings(
            _appSettings.copyWith(randomCharacterOrder: value),
          ),
          onSpeechVoiceChanged: (name, locale) => _updateAppSettings(
            _appSettings.copyWith(
              selectedVoiceName: name,
              selectedVoiceLocale: locale,
            ),
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
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Morse ICR Trainer'),
        ),
        leading: IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Training Log',
          onPressed: _openTrainingLog,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Help',
            onPressed: _openHelp,
          ),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                            _persistMainScreenSettings();
                          },
                        ),
                        const SizedBox(height: 8),
                        SteppedIntControl(
                          label: 'Recognition Time',
                          value: _recognitionTimeMs,
                          min: 50,
                          max: 2500,
                          step: 1,
                          suffix: 'ms',
                          onChanged: (v) {
                            setState(() => _recognitionTimeMs = v);
                            _trainingEngine.updateSettings(
                              recognitionTime: Duration(milliseconds: v),
                            );
                            _persistMainScreenSettings();
                          },
                        ),
                        const SizedBox(height: 8),
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
                            _persistMainScreenSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _isTraining ? null : _openCountdownTimerSettings,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              color: colorScheme.primary,
                              size: 24,
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
                              size: 24,
                              color: _isTraining
                                  ? Theme.of(context).disabledColor
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    title: 'Character Set',
                    child: Column(
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            // Word (whole-word recognition) is a future
                            // mode with no implementation behind it yet
                            // (see [CharacterSetType.words]'s own doc
                            // comment) -- hidden here until it's built
                            // (Bill, 2026-08-31), not removed from the
                            // enum, so nothing else that iterates
                            // [CharacterSetType.values] needs to change.
                            for (final type in CharacterSetType.values.where(
                              (type) => type != CharacterSetType.words,
                            ))
                              FilterChip(
                                label: Text(type.label),
                                showCheckmark: false,
                                selected: _selectedCharacterSets.contains(type),
                                selectedColor: colorScheme.primaryContainer,
                                // Explicit for both states -- Material 3's
                                // default FilterChip only outlines the
                                // unselected state and drops the border
                                // entirely once selected, which read as
                                // an inconsistent border between chips
                                // once Word left only three of them
                                // (Bill, 2026-08-31). A visible border on
                                // every chip regardless of selection
                                // matches the Focus button's own
                                // consistent-outline treatment below.
                                side: BorderSide(
                                  color: _selectedCharacterSets.contains(type)
                                      ? colorScheme.primary
                                      : colorScheme.outline,
                                ),
                                onSelected: _isTraining
                                    ? null
                                    : (selected) {
                                        setState(() {
                                          if (selected) {
                                            _selectedCharacterSets.add(type);
                                          } else {
                                            _selectedCharacterSets.remove(type);
                                          }
                                          // Selecting a chip at all --
                                          // even just deselecting one --
                                          // supersedes an active problem-
                                          // character set (morse_icr_spec.md
                                          // section 39).
                                          _problemCharacters = null;
                                        });
                                        _persistMainScreenSettings();
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
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
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 4,
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
                  const SizedBox(height: 6),
                  if (_isTraining)
                    Row(
                      children: [
                        Expanded(
                          child: _TrainingActionButton(
                            color: _isPaused ? Colors.green : Colors.red,
                            label: _isPaused ? 'Resume' : 'Stop',
                            onPressed: _isPaused
                                ? _togglePause
                                : _toggleTraining,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TrainingActionButton(
                            color: _isPaused ? Colors.red : Colors.orange,
                            label: _isPaused ? 'Stop' : 'Pause',
                            onPressed: _isPaused
                                ? _toggleTraining
                                : _togglePause,
                          ),
                        ),
                      ],
                    )
                  else
                    _TrainingActionButton(
                      color: Colors.green,
                      label: 'Start',
                      onPressed: _hasSelectedCharacters
                          ? _toggleTraining
                          : null,
                    ),
                  // 2026-08-30: hidden now that Milestone 13's on-device
                  // debugging is done -- see lib/debug_log.dart's own
                  // note. Flip _showDebugLogPanel back on (logging itself
                  // also needs re-enabling there) if a future hard-to-
                  // diagnose bug needs it again.
                  if (_showDebugLogPanel) ...[
                    const SizedBox(height: 16),
                    _DebugLogPanel(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the main screen's Start/Stop/Pause/Resume buttons -- shared
/// styling (color, size, shape) so the single full-width Start button and
/// the side-by-side Stop+Pause / Resume+Stop pair all read as the same
/// kind of control.
class _TrainingActionButton extends StatelessWidget {
  const _TrainingActionButton({
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final Color color;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onPressed,
      child: Text(label),
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
    this.padding = const EdgeInsets.all(10),
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
              const SizedBox(height: 8),
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
