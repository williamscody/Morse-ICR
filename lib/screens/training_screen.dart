import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../audio/audio_session_setup.dart';
import '../audio/keep_alive_audio_loop.dart';
import '../audio/turn_audio_engine.dart';
import '../debug_log.dart';
import '../speech/answer_speaker.dart';
import '../speech/response_listener.dart';
import '../speech/speech_to_text_response_listener.dart';
import '../speech/tts_answer_speaker.dart';
import '../training/character_set.dart';
import '../training/training_engine.dart';
import 'settings_screen.dart';
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
    Future<bool> Function() headphonesConnectedCheck = hasNonSpeakerAudioOutput,
    Future<void> Function() reconfigureAudioSessionOnStart =
        configureAudioSession,
    Future<void> Function() activateAudioSessionOnStart = activateAudioSession,
    Future<void> Function() deactivateAudioSessionOnStop =
        deactivateAudioSession,
  }) : _injectedTrainingEngine = trainingEngine,
       _injectedAnswerSpeaker = answerSpeaker,
       _injectedResponseListener = responseListener,
       _headphonesConnectedCheck = headphonesConnectedCheck,
       _reconfigureAudioSessionOnStart = reconfigureAudioSessionOnStart,
       _activateAudioSessionOnStart = activateAudioSessionOnStart,
       _deactivateAudioSessionOnStop = deactivateAudioSessionOnStop;

  final TrainingEngine? _injectedTrainingEngine;
  final AnswerSpeaker? _injectedAnswerSpeaker;
  final ResponseListener? _injectedResponseListener;
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
  bool _isTraining = false;
  // Not shown in the UI -- tracked ahead of session logging
  // (Milestone 10), which will need a played-character count.
  int _charactersPlayed = 0;
  bool _voiceEnabled = true;
  bool _voicePreparing = false;
  bool _recognitionEnabled = true;
  bool _lastResponseCorrect = false;

  TurnAudioEngine? _turnAudioEngine;
  KeepAliveAudioLoop? _keepAliveLoop;
  late final TrainingEngine _trainingEngine;
  late final AnswerSpeaker _answerSpeaker;
  late final ResponseListener _responseListener;

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

  Future<void> _toggleTraining() async {
    if (_togglingTraining) return;
    _togglingTraining = true;
    try {
      await _toggleTrainingUnguarded();
    } finally {
      _togglingTraining = false;
    }
  }

  Future<void> _toggleTrainingUnguarded() async {
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
      setState(() => _isTraining = false);
      logDebug('stop: done');
      return;
    }

    logDebug('start: tapped');
    final characters = charactersForSelection(_selectedCharacterSets);
    if (characters.isEmpty) return;

    if (_recognitionEnabled && !await widget._headphonesConnectedCheck()) {
      if (!mounted) return;
      _showHeadphonesRequiredMessage();
      return;
    }

    setState(() {
      _isTraining = true;
      _charactersPlayed = 0;
    });
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

  bool get _hasSelectedCharacters =>
      charactersForSelection(_selectedCharacterSets).isNotEmpty;

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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          voiceEnabled: _voiceEnabled,
          voicePreparing: _voicePreparing,
          recognitionEnabled: _recognitionEnabled,
          onVoiceChanged: (value) => setState(() => _voiceEnabled = value),
          onRecognitionChanged: _onRecognitionChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Morse ICR'),
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
                  SteppedIntControl(
                    label: 'Character Speed',
                    value: _wpm,
                    min: 15,
                    max: 150,
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
                  const SizedBox(height: 24),
                  Text(
                    'Character Set',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final type in CharacterSetType.values)
                        FilterChip(
                          label: Text(type.label),
                          showCheckmark: false,
                          selected: _selectedCharacterSets.contains(type),
                          onSelected: _isTraining
                              ? null
                              : (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedCharacterSets.add(type);
                                    } else {
                                      _selectedCharacterSets.remove(type);
                                    }
                                  });
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _isTraining ? 'Training…' : 'Idle',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_isTraining) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: SizedBox(
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
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _isTraining ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
