/// Pure Morse timing calculations.
///
/// One timing unit = 60 / (50 * wpm) seconds (morse_icr_spec.md section 4).
/// All values are exact doubles in seconds; conversion to sample counts
/// happens once, in the audio synthesizer, to avoid compounding rounding
/// error across multiple unit types.
class MorseTiming {
  const MorseTiming(this.wpm) : assert(wpm > 0);

  final double wpm;

  double get unitSeconds => 60.0 / (50.0 * wpm);

  double get ditSeconds => unitSeconds;
  double get dahSeconds => unitSeconds * 3;
  double get intraCharacterGapSeconds => unitSeconds;
  double get interCharacterGapSeconds => unitSeconds * 3;
  double get wordGapSeconds => unitSeconds * 7;
}
