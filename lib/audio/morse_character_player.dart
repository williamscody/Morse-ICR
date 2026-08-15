/// Anything that can play a single Morse character's audio.
///
/// Lets the training engine drive playback without depending on the
/// concrete [package:audioplayers]-backed engine, so the loop can be
/// tested without real audio (morse_icr_spec.md section 7: the
/// audio/timing engine should be testable independently).
abstract class MorseCharacterPlayer {
  Future<void> playCharacter(String character, double wpm);
}
