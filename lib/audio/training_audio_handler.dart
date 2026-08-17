import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import 'training_session_reporter.dart';

/// Mirrors the training loop's running/stopped state into the OS media
/// session so the lock screen, Control Center, Dynamic Island, and (on
/// Android) the foreground-service notification show a "Morse
/// Training" card while a session is active.
///
/// Deliberately thin: [TrainingEngine] fires a rapid stream of short
/// Morse-tone and spoken-word bursts, not one continuous track, so
/// there's no per-character [MediaItem] to publish -- only a single
/// session-level one whose `playing` state tracks
/// [TrainingEngine.isRunning]. This handler owns no playback itself;
/// [TrainingScreen] still drives [TrainingEngine] directly and calls
/// [reportStarted]/[reportStopped] alongside it.
class TrainingAudioHandler extends BaseAudioHandler
    implements TrainingSessionReporter {
  static final _sessionItem = MediaItem(
    id: 'morse_training_session',
    title: 'Morse Training',
    artist: 'ICR',
  );

  void Function()? _onStopRequested;
  void Function()? _onPlayRequested;

  @override
  set onStopRequested(void Function()? callback) =>
      _onStopRequested = callback;

  @override
  set onPlayRequested(void Function()? callback) =>
      _onPlayRequested = callback;

  @override
  void reportStarted() {
    mediaItem.add(_sessionItem);
    playbackState.add(
      playbackState.value.copyWith(
        controls: [MediaControl.pause, MediaControl.stop],
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
    unawaited(_setSessionActive(true));
  }

  @override
  void reportStopped() {
    // Leaves the MediaItem in place (rather than clearing it) so the
    // card stays visible in a resumable "paused" state instead of
    // vanishing -- matters when this is reached via the lock screen's
    // own Play/Pause toggle (see [pause] below), which would otherwise
    // make tapping pause look like it broke the card.
    playbackState.add(
      playbackState.value.copyWith(
        controls: [MediaControl.play],
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
    unawaited(_setSessionActive(false));
  }

  Future<void> _setSessionActive(bool active) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(active);
    } catch (_) {
      // Not fatal to the training loop -- audio output is an external
      // boundary the learner can't control mid-session.
    }
  }

  // Called when the learner taps Play/Stop on the lock screen, Control
  // Center, Dynamic Island, or Android notification -- forwarded to
  // whatever [TrainingScreen] wired up, which decides whether resuming
  // (with the most recently used settings) or stopping actually makes
  // sense right now.
  @override
  Future<void> play() async => _onPlayRequested?.call();

  @override
  Future<void> stop() async => _onStopRequested?.call();

  // The system's own Play/Pause toggle (the prominent button on the
  // lock screen/Control Center/Dynamic Island) doesn't call play()/
  // stop() -- it sends a click, whose default BaseAudioHandler
  // implementation calls pause() when playbackState.playing is true.
  // TrainingEngine has no partial-pause state, only running/stopped,
  // so pausing here means the same thing stopping does.
  @override
  Future<void> pause() async => _onStopRequested?.call();
}
