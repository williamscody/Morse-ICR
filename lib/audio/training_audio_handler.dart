import 'package:audio_service/audio_service.dart';

/// Set once at app startup (main.dart, iOS only) and read by
/// [TrainingScreen] -- global rather than passed down through the widget
/// tree because it's constructed before any widget exists, by
/// [AudioService.init] itself.
TrainingAudioHandler? trainingAudioHandler;

/// Minimal re-introduction of the lock-screen presence spec section 37
/// reverted (morse_icr project memory): the earlier version registered
/// full Play/Stop remote controls and was found fighting
/// `speech_to_text`'s own AVAudioSession category churn. This version
/// asks for far less -- just enough that a "Morse ICR" card with a
/// Play/Pause toggle appears on the lock screen while training runs, and
/// tapping the card (not the toggle) opens the app, which iOS provides
/// automatically for any active Now Playing session. It never touches
/// AVAudioSession itself (confirmed against package:audio_service's own
/// native iOS source -- it only ever reads the shared instance, never
/// sets its category or activation), so [configureAudioSession] and
/// friends remain the sole owner of that lifecycle, same as before.
///
/// iOS's MPRemoteCommandCenter always enables a Play/Pause toggle the
/// moment a Now Playing session starts playing -- unlike every other
/// transport control, this one can't be hidden by leaving [controls]
/// empty (confirmed against the native source: it's a hard-coded
/// "automatically enabled" case). An earlier version of this handler
/// wired the toggle to [TrainingScreen]'s own Start/Stop handler, but
/// on-device testing (2026-08-21) showed that tapping it stops training
/// *and* immediately drops the card itself (correctly -- audio really
/// does stop), defeating the actual goal of a lock-screen card that
/// stays put as a quick way back into the app. [play] and [pause] are
/// deliberately left as no-ops: the toggle is an unavoidable dead
/// button, and tapping the card *body* (not the toggle) is what opens
/// the app, which iOS provides automatically for any active Now Playing
/// session. A true pause/resume that keeps the card alive through a real
/// stop would need [TrainingEngine] to grow an actual paused state
/// distinct from stopped (keeping the audio session and keep-alive tone
/// running while the character loop itself halts) -- not attempted here,
/// since it reopens the state-machine complexity that motivated
/// section 37's original revert.
class TrainingAudioHandler extends BaseAudioHandler {
  static const _mediaItem = MediaItem(
    id: 'morse_icr_training',
    title: 'Morse ICR',
    artist: 'Training in progress',
  );

  /// Call when a training session starts.
  void reportTraining() {
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

  /// Call when a training session stops -- drops the lock-screen card
  /// (mirrors the underlying audio actually going silent once
  /// [deactivateAudioSession] runs).
  void reportIdle() {
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}
}
