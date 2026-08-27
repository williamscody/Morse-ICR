import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../audio/in_memory_audio_source.dart';
import '../audio/pcm16_wav.dart';
import 'character_recorder.dart' show enrollmentSampleRate;

/// Plays back [pcm16Takes] (raw PCM16 mono at [enrollmentSampleRate], the
/// format [EnrollmentStore] persists) one after another, in order -- the
/// playback counterpart to `recordCharacterTakes`, letting a saved
/// enrollment be auditioned exactly as captured rather than needing the
/// files pulled off the device by hand. [onTakePlaying], if given, fires
/// with the 1-based take number just before each one starts.
///
/// A fresh [AudioPlayer] per call, not a shared/injected one -- this
/// screen has no background-execution or keep-alive session concerns of
/// its own (unlike TrainingScreen's TurnAudioEngine), so there's nothing
/// to gain from keeping one alive between auditions.
Future<void> playCharacterTakes(
  List<Uint8List> pcm16Takes, {
  void Function(int takeNumber)? onTakePlaying,
}) async {
  final player = AudioPlayer();
  try {
    for (var index = 0; index < pcm16Takes.length; index++) {
      onTakePlaying?.call(index + 1);
      final bytes = pcm16Takes[index];
      final samples = bytes.buffer.asInt16List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 2,
      );
      // Pausing before loading each new take is required, not just
      // tidy -- TurnAudioEngine hit the same just_audio/iOS quirk first
      // (see its own playTurn comment): setAudioSource() auto-starts the
      // newly loaded source immediately if the player's own `playing`
      // flag is still true from the *previous* take's natural
      // completion, so without this, only the first take's play() call
      // genuinely started and awaited playback -- every take after it
      // raced ahead instead of actually being heard.
      await player.pause();
      await player.setAudioSource(
        InMemoryAudioSource(
          pcm16WavBytes(samples, sampleRate: enrollmentSampleRate),
        ),
      );
      await player.play();
    }
  } finally {
    await player.dispose();
  }
}
