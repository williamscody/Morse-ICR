import 'package:audio_service/audio_service.dart';

import '../debug_log.dart';

/// Set once at app startup (main.dart, iOS and Android) and read by
/// [TrainingScreen] -- global rather than passed down through the widget
/// tree because it's constructed before any widget exists, by
/// [AudioService.init] itself.
TrainingAudioHandler? trainingAudioHandler;

/// Drives the lock-screen/notification media card on both platforms:
/// iOS's Now Playing card (spec section 37) and Android's foreground-
/// service notification (section 42, Android background audio) -- the
/// same shared [BaseAudioHandler] Dart API produces both, without either
/// platform's own doc history below needing to change now that the other
/// one uses it too.
///
/// iOS history: an earlier version registered full Play/Stop remote
/// controls and was found fighting `speech_to_text`'s own AVAudioSession
/// category churn. This version asks for far less -- just enough that a
/// "Morse ICR Trainer" card with a working Play/Pause toggle appears while a
/// session is running or paused, and tapping the card body (not the
/// toggle) opens the app, which iOS provides automatically for any active
/// Now Playing session. It never touches AVAudioSession itself (confirmed
/// against package:audio_service's own native iOS source -- it only ever
/// reads the shared instance, never sets its category or activation), so
/// [configureAudioSession] and friends remain the sole owner of that
/// lifecycle. iOS's MPRemoteCommandCenter always enables a Play/Pause
/// toggle the moment a Now Playing session starts playing -- unlike every
/// other transport control, this one can't be hidden by leaving
/// [controls] empty (confirmed against the native source: it's a
/// hard-coded "automatically enabled" case).
///
/// An earlier version of this handler left [play]/[pause] as no-ops on
/// iOS because wiring the toggle to Start/Stop made tapping it drop the
/// Now Playing card entirely (audio really did stop), defeating the point
/// of a card that stays put as a quick way back into the app.
/// [TrainingScreen] growing a genuine paused state distinct from stopped
/// (Pause/Resume, keeping the session in place rather than tearing it
/// down) is what makes wiring these two real: [onPlayRequested]/
/// [onPauseRequested] both forward to [TrainingScreen]'s own pause/resume
/// toggle, which is itself bidirectional, so either callback driving it
/// produces the correct result regardless of which direction the lock
/// screen's/notification's single toggle was actually in. Android's own
/// foreground-service notification exposes the same Play/Pause toggle
/// through [MediaButtonReceiver] and its own transport-control UI, wired
/// to these same two callbacks -- no Android-specific override needed
/// here.
class TrainingAudioHandler extends BaseAudioHandler {
  static const _mediaItem = MediaItem(
    id: 'morse_icr_training',
    title: 'Morse ICR Trainer',
    artist: 'Training in progress',
  );

  /// Set by [TrainingScreen] to its own pause/resume toggle -- invoked
  /// when the lock screen's Play/Pause control is tapped while the
  /// session is, respectively, paused or running. Left null (a no-op)
  /// outside of a live [TrainingScreen], e.g. in widget tests.
  Future<void> Function()? onPlayRequested;
  Future<void> Function()? onPauseRequested;

  /// Call when a training session starts.
  void reportTraining() {
    // Temporary diagnostic logging (2026-09-02, see debug_log.dart's own
    // note) -- confirms this actually runs, separating "TrainingScreen
    // never called it" from "it ran but iOS/audio_service didn't
    // surface a Now Playing card for it" as the cause of a reported
    // missing lock-screen control.
    logDebug('TrainingAudioHandler.reportTraining()');
    mediaItem.add(_mediaItem);
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [MediaControl.pause],
        systemActions: const {MediaAction.playPause},
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  /// Call when the session is paused (not stopped) -- keeps the Now
  /// Playing card on-screen, showing a Play control, rather than dropping
  /// it the way [reportIdle] does. `playing: false` with
  /// [AudioProcessingState.ready] (not `idle`) is what keeps iOS treating
  /// this as a live, just-paused session instead of a finished one.
  void reportPaused() {
    logDebug('TrainingAudioHandler.reportPaused()');
    playbackState.add(
      playbackState.value.copyWith(
        controls: const [MediaControl.play],
        systemActions: const {MediaAction.playPause},
        playing: false,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  /// Call when a training session stops -- drops the lock-screen card
  /// (mirrors the underlying audio actually going silent once
  /// [deactivateAudioSession] runs).
  void reportIdle() {
    logDebug('TrainingAudioHandler.reportIdle()');
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> play() async {
    await onPlayRequested?.call();
  }

  @override
  Future<void> pause() async {
    await onPauseRequested?.call();
  }
}
