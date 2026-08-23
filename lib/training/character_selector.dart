import 'dart:math' as math;

/// Selects random characters from an active character set.
///
/// Uniform random selection, independent from call to call -- weighted
/// and problem-character-biased selection are future work per
/// morse_icr_spec.md section 15.
///
/// Previously avoided immediately repeating the last selection, per an
/// earlier version of section 15. Reverted (Milestone 13, 2026-08-22):
/// on-device use showed that rule visibly distorting output at small
/// active-set sizes -- a 2-character focus set, for instance, was
/// forced into perfect strict alternation (H, S, H, S, ...) every
/// single time, which reads as far less random than genuine uniform
/// selection actually is, not more.
class CharacterSelector {
  CharacterSelector({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;

  /// When false, [next] cycles through [characters] in the order given
  /// instead of drawing uniformly at random -- a diagnostic-only mode
  /// (2026-08-23) added at Bill's request, so a repeatable, predictable
  /// sequence can isolate whether an accuracy issue is confusion between
  /// specific characters or noise from random draw order. Defaults to
  /// true (random), preserving existing behavior for anyone who never
  /// touches the Settings toggle this backs.
  bool randomOrder = true;

  int _sequentialIndex = 0;

  /// Returns the next character from [characters] -- uniformly at
  /// random when [randomOrder] is true, or the next one in [characters]'
  /// own order (wrapping around) when it's false.
  ///
  /// Throws [ArgumentError] if [characters] is empty.
  String next(List<String> characters) {
    if (characters.isEmpty) {
      throw ArgumentError('Cannot select from an empty character set');
    }
    if (!randomOrder) {
      final character = characters[_sequentialIndex % characters.length];
      _sequentialIndex++;
      return character;
    }
    return characters[_random.nextInt(characters.length)];
  }
}
