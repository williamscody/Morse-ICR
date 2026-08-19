import 'dart:async';

import '../audio/morse_character_player.dart';
import '../debug_log.dart';
import '../morse/morse_event.dart';
import 'character_selector.dart';
import 'recognition_timer.dart';

/// Drives the character-generation training loop
/// (morse_icr_spec.md section 26 "training engine"): while running,
/// repeatedly selects a character from the active set, plays it, waits
/// out the character's audio, then starts a [RecognitionTimer] for the
/// recognition time (section 6: the interval between the end of the
/// Morse character and the computer speaking the answer) before
/// generating the next one.
///
/// The recognition timer starts only once playback has finished (section
/// 29) and, once it expires, awaits [onRecognitionTimeout] before moving
/// on -- so if the hook speaks the answer (section 28), the next
/// character doesn't begin until that finishes; [submitResponse] does
/// not cancel or delay this (Milestone 8's product-scope clarification:
/// the computer always announces the answer). Nothing yet scores a
/// response (Milestone 9).
class TrainingEngine {
  TrainingEngine({required this._audioPlayer, CharacterSelector? selector})
    : _selector = selector ?? CharacterSelector();

  final MorseCharacterPlayer _audioPlayer;
  final CharacterSelector _selector;
  final RecognitionTimer _recognitionTimer = RecognitionTimer();

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _wakeCompleter;
  Timer? _timer;
  double _wpm = 0;
  Duration _recognitionTime = Duration.zero;
  String? _awaitingResponseFor;
  String? _respondedTo;

  bool get isRunning => _running;

  /// Called with each character just before it plays.
  ///
  /// Never surfaced in the UI (morse_icr_spec.md section 24 forbids
  /// displaying the character); intended for future milestones
  /// (recognition timing, logging, statistics) and for tests.
  void Function(String character)? onCharacterGenerated;

  /// Called when a character's recognition deadline expires without
  /// being cancelled first -- the "MISS" path of morse_icr_spec.md
  /// section 29's timeline. Fires once per character, after that
  /// character's Morse audio has finished playing. The training loop
  /// awaits the returned future -- e.g. for the computer's spoken
  /// answer to finish (section 28) -- before generating the next
  /// character.
  Future<void> Function(String character)? onRecognitionTimeout;

  /// Called (at most once per character) when [submitResponse]
  /// recognizes the correct character -- the "SUCCESS" path of
  /// morse_icr_spec.md section 29's timeline, parallel to
  /// [onRecognitionTimeout]'s "MISS" path.
  ///
  /// Deliberately does *not* currently suppress [onRecognitionTimeout]
  /// -- the computer still announces the answer regardless, since
  /// speech-recognition accuracy is still being verified and Bill
  /// wants the voice kept on for debugging until a future settings
  /// toggle exists for it. Scoring/statistics (Milestone 9) and
  /// problem-character capture (Milestone 14) aren't wired up yet
  /// either; this only exists so later work can hook in without
  /// further changes here.
  void Function(String character)? onCorrectResponse;

  /// Call when the learner is recognized as having said a character
  /// aloud (morse_icr_spec.md section 27). Only credited while
  /// [character]'s own recognition deadline is still running -- this is
  /// "beat the computer" (section 7): a response that arrives after the
  /// deadline has already lost, even if it's otherwise correct, so it
  /// must not light the green dot. (An earlier version credited a
  /// response any time up until the next character superseded it, to
  /// tolerate ASR's 700ms-1.5s result lag -- on-device testing showed
  /// that made the dot meaningless as a "did I beat the computer"
  /// signal, since most credited responses were actually late.) No-ops
  /// for a mismatched, stale (already-superseded), repeat, or
  /// deadline-expired response.
  void submitResponse(String character) {
    logDebug(
      'submitResponse($character) awaiting=$_awaitingResponseFor '
      'respondedTo=$_respondedTo running=${_recognitionTimer.isRunning}',
    );
    if (character != _awaitingResponseFor || character == _respondedTo) {
      return;
    }
    if (!_recognitionTimer.isRunning) return;
    _respondedTo = character;
    onCorrectResponse?.call(character);
  }

  /// Starts generating and playing characters from [characters] at
  /// [wpm], pausing for [recognitionTime] after each one before playing
  /// the next, until [stop] is called. No-op if already running.
  void start({
    required List<String> characters,
    required double wpm,
    required Duration recognitionTime,
  }) {
    if (_running) return;
    if (characters.isEmpty) {
      throw ArgumentError('Cannot train with an empty character set');
    }
    _wpm = wpm;
    _recognitionTime = recognitionTime;
    _running = true;
    _loopFuture = _runLoop(characters);
  }

  /// Changes the character speed and/or recognition time used by
  /// characters generated from now on. The learner may adjust these
  /// live while training is running (they are not locked the way
  /// Personal Character Speed is once training is under way per
  /// morse_icr_spec.md section 17) -- a change never interrupts a
  /// character or gap already in progress, only ones not yet started.
  void updateSettings({double? wpm, Duration? recognitionTime}) {
    if (wpm != null) _wpm = wpm;
    if (recognitionTime != null) _recognitionTime = recognitionTime;
  }

  /// Stops the loop and waits for it to fully exit, interrupting any
  /// in-progress inter-character wait so callers can rely on the engine
  /// being idle -- with no timers left pending -- once this completes.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _recognitionTimer.cancel();
    _awaitingResponseFor = null;
    _respondedTo = null;
    // _wakeCompleter can already be completed here -- its owner (_wait
    // or _waitForRecognition) may have just resolved it naturally in
    // the same event-loop turn, before _runLoop's awaited continuation
    // got a chance to move _wakeCompleter on to the next one.
    final wakeCompleter = _wakeCompleter;
    if (wakeCompleter != null && !wakeCompleter.isCompleted) {
      wakeCompleter.complete();
    }
    _wakeCompleter = null;
    await _loopFuture;
    _loopFuture = null;
  }

  Future<void> _runLoop(List<String> characters) async {
    while (_running) {
      final character = _selector.next(characters);
      // Freeze this character's own speed for its own playback and
      // duration wait, even if [updateSettings] changes [_wpm] before
      // either finishes -- only the *next* character should speed up
      // or slow down.
      final wpm = _wpm;
      logDebug('generated: $character');
      onCharacterGenerated?.call(character);
      try {
        await _audioPlayer.playCharacter(character, wpm);
      } catch (e) {
        // A playback failure shouldn't kill the training loop -- audio
        // output is an external boundary (device/plugin issues) the
        // learner can't control mid-session. Logged rather than
        // silently swallowed -- this exact catch was hiding whatever
        // native error explains the "no audio after background+lock"
        // bug from every earlier debugging attempt this session.
        logDebug('playCharacter($character) failed: $e');
      }
      if (!_running) break;
      await _wait(_characterDuration(character, wpm));
      if (!_running) break;
      await _waitForRecognition(character);
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

  /// Starts the recognition timer for [character] -- only once playback
  /// has already finished, per the caller in [_runLoop] -- and resolves
  /// once it expires and [onRecognitionTimeout] (if any) has finished.
  Future<void> _waitForRecognition(String character) {
    final completer = Completer<void>();
    _wakeCompleter = completer;
    _awaitingResponseFor = character;
    _respondedTo = null;
    _recognitionTimer.start(_recognitionTime, () async {
      final hook = onRecognitionTimeout;
      if (hook != null) {
        try {
          await hook(character);
        } catch (_) {
          // A misbehaving hook (e.g. speech synthesis failure)
          // shouldn't kill the training loop.
        }
      }
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  Duration _characterDuration(String character, double wpm) {
    final seconds = morseElementsForCharacter(
      character,
      wpm,
    ).fold<double>(0, (sum, e) => sum + e.durationSeconds);
    return _toDuration(seconds);
  }

  Duration _toDuration(double seconds) =>
      Duration(microseconds: (seconds * 1e6).round());
}
