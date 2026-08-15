import 'package:audioplayers/audioplayers.dart';

import '../morse/morse_event.dart';
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
  final AudioPlayer _player;

  /// Renders [character] at [wpm] to a WAV buffer and plays it.
  ///
  /// Only covers the character's own dit/dah/gap envelope. Waiting for
  /// the recognition deadline after playback is the training engine's
  /// job (section 6), not the audio engine's.
  @override
  Future<void> playCharacter(String character, double wpm) async {
    final elements = morseElementsForCharacter(character, wpm);
    final wavBytes = _synthesizer.synthesizeWav(elements);
    await _player.play(BytesSource(wavBytes, mimeType: 'audio/wav'));
  }

  Future<void> dispose() => _player.dispose();
}
