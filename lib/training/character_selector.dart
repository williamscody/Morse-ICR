import 'dart:math' as math;

/// Selects random characters from an active character set.
///
/// Avoids immediately repeating the previous selection
/// (morse_icr_spec.md section 15). Kept intentionally simple -- uniform
/// random selection only; weighted and problem-character-biased
/// selection are future work per the same section.
class CharacterSelector {
  CharacterSelector({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  String? _previous;

  /// Returns a random character from [characters].
  ///
  /// If [characters] has more than one entry, the result never
  /// immediately repeats the character returned by the previous call.
  /// Throws [ArgumentError] if [characters] is empty.
  String next(List<String> characters) {
    if (characters.isEmpty) {
      throw ArgumentError('Cannot select from an empty character set');
    }
    if (characters.length == 1) {
      _previous = characters.first;
      return _previous!;
    }
    String candidate;
    do {
      candidate = characters[_random.nextInt(characters.length)];
    } while (candidate == _previous);
    _previous = candidate;
    return candidate;
  }

  /// Clears repeat-avoidance history so the next call may return any
  /// character, including one identical to the last selection.
  void reset() => _previous = null;
}
