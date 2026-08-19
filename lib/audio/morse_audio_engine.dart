import 'package:just_audio/just_audio.dart';

import '../debug_log.dart';
import '../morse/morse_event.dart';
import 'in_memory_audio_source.dart';
import 'morse_character_player.dart';
import 'tone_synthesizer.dart';

/// Plays Morse characters as 600 Hz tone bursts.
///
/// Keeps the "Morse generator" (character -> timed elements) and the
/// "audio engine" (render + play) as separate concerns per
/// morse_icr_spec.md section 26, so each stays independently testable.
class MorseAudioEngine implements MorseCharacterPlayer {
  MorseAudioEngine({
    this._synthesizer = const ToneSynthesizer(),
    AudioPlayer? player,
  }) : _player = player ?? AudioPlayer();

  final ToneSynthesizer _synthesizer;
  AudioPlayer _player;

  /// Renders [character] at [wpm] to a WAV buffer and plays it.
  ///
  /// Only covers the character's own dit/dah/gap envelope. Waiting for
  /// the recognition deadline after playback is the training engine's
  /// job (section 6), not the audio engine's.
  ///
  /// [AudioPlayer.play]'s future resolves once the native platform has
  /// acknowledged the play request, not once the clip finishes -- so
  /// this method already returns promptly once the tone has been told
  /// to play. TrainingEngine paces itself with its own computed
  /// duration wait after this returns (section 25), not by waiting for
  /// actual playback completion.
  @override
  Future<void> playCharacter(String character, double wpm) async {
    final elements = morseElementsForCharacter(character, wpm);
    final wavBytes = _synthesizer.synthesizeWav(elements);
    logDebug(
      'playCharacter($character): setAudioSource '
      '(playerState=${_player.playerState}, playing=${_player.playing})',
    );
    await _player.setAudioSource(InMemoryAudioSource(wavBytes));
    logDebug(
      'playCharacter($character): play() '
      '(playerState=${_player.playerState})',
    );
    await _player.play();
    logDebug(
      'playCharacter($character): play() returned '
      '(playerState=${_player.playerState}, playing=${_player.playing})',
    );
  }

  /// Recreates the underlying [AudioPlayer], discarding the old one.
  ///
  /// [InMemoryAudioSource]'s [StreamAudioSource] support is backed by a
  /// local loopback HTTP server that package:just_audio creates once per
  /// [AudioPlayer] instance and only re-binds if its own internal
  /// "running" flag is false. On-device testing confirmed that server
  /// can go silently unreachable across an iOS background+lock+resume
  /// cycle -- every subsequent [playCharacter] call then fails with
  /// native error -1004 ("Could not connect to the server") -- without
  /// that flag ever getting reset, so just_audio's own self-healing
  /// never kicks in. A fresh [AudioPlayer] gets a fresh proxy server,
  /// sidestepping the problem entirely; call this on app resume.
  Future<void> resetPlayer() async {
    final old = _player;
    _player = AudioPlayer();
    await old.dispose();
  }

  Future<void> dispose() => _player.dispose();
}
