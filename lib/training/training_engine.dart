import 'dart:async';

import '../audio/morse_character_player.dart';
import '../morse/morse_event.dart';
import 'character_selector.dart';

/// Drives the character-generation training loop
/// (morse_icr_spec.md section 26 "training engine"): while running,
/// repeatedly selects a character from the active set, plays it, then
/// waits out the character's audio plus the recognition time (section 6:
/// the interval between the end of the Morse character and the computer
/// speaking the answer) before generating the next one.
///
/// The recognition timer only governs pacing here -- it doesn't yet
/// gate on a learner response (Milestone 8), announce the answer
/// (Milestone 7), or score anything (Milestone 9).
class TrainingEngine {
  TrainingEngine({required this._audioPlayer, CharacterSelector? selector})
    : _selector = selector ?? CharacterSelector();

  final MorseCharacterPlayer _audioPlayer;
  final CharacterSelector _selector;

  bool _running = false;
  Future<void>? _loopFuture;
  Completer<void>? _wakeCompleter;
  Timer? _timer;
  double _wpm = 0;
  Duration _recognitionTime = Duration.zero;

  bool get isRunning => _running;

  /// Called with each character just before it plays.
  ///
  /// Never surfaced in the UI (morse_icr_spec.md section 24 forbids
  /// displaying the character); intended for future milestones
  /// (recognition timing, logging, statistics) and for tests.
  void Function(String character)? onCharacterGenerated;

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
    _wakeCompleter?.complete();
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
      onCharacterGenerated?.call(character);
      try {
        await _audioPlayer.playCharacter(character, wpm);
      } catch (_) {
        // A playback failure shouldn't kill the training loop -- audio
        // output is an external boundary (device/plugin issues) the
        // learner can't control mid-session.
      }
      if (!_running) break;
      await _wait(_characterDuration(character, wpm));
      if (!_running) break;
      await _wait(_recognitionTime);
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
