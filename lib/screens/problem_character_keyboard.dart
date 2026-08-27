import 'package:flutter/material.dart';

import '../training/character_set.dart';
import '../training/problem_character_store.dart';

/// Lets the learner build a problem-character set by tapping characters
/// on and off (morse_icr_spec.md sections 11, 12, 39): one-tap toggle
/// per character, with a visual indication (the same selected-chip
/// styling [TrainingScreen] already uses for its character-set chips) of
/// what's currently in the set. Persists the result via [store] and
/// returns it to the caller once Done is tapped -- [TrainingScreen] is
/// what actually makes it the active training set (section 39's flow
/// step 3), this screen only edits and persists the list itself.
///
/// Every chip [_scores] has an entry for -- i.e. every character that's
/// actually been *attempted* in some training session, regardless of
/// whether it's currently selected here -- is heat-map colored from red
/// (few correct answers) to green (many), with the count itself printed
/// below the character (see [_heatMapColor]). A character with no entry
/// at all (never trained) stays transparent. This coloring is entirely
/// independent of [_selected] (the border below is what shows that):
/// training a full character set like A-Z on the main screen, without
/// ever touching this screen's Focus picker, still colors every one of
/// those 26 chips here once a session records their scores. This is also
/// how a training session's own missed-character auto-flagging
/// (Milestone 13's voice recognizer, see [_autoFlagged]) surfaces: a
/// character that's mostly being missed reads red from its low score, so
/// no separate red-border treatment is needed -- and, per [_selected]'s
/// own doc comment, auto-flagging never selects/borders a chip by
/// itself, only the learner's own tap does that.
///
/// The bottom of the screen shows an all-time "X% Correct" summary
/// (2026-08-31) once any character has a recorded attempt -- total
/// correct over total attempted, across every character, recomputed
/// from [_scores]/[_attempts]' latest persisted totals every time this
/// screen opens. See [_correctPercentage].
class ProblemCharacterKeyboard extends StatefulWidget {
  const ProblemCharacterKeyboard({super.key, required this.store});

  final ProblemCharacterStore store;

  @override
  State<ProblemCharacterKeyboard> createState() =>
      _ProblemCharacterKeyboardState();
}

class _ProblemCharacterKeyboardState extends State<ProblemCharacterKeyboard> {
  // Populated at load from [widget.store.load]'s persisted result, which
  // is itself only ever written by this screen's own [_done] -- a
  // training session's missed-character auto-flagging (see
  // [_autoFlagged]) never touches it (morse_icr_spec.md section 39;
  // reversed 2026-08-26 from an earlier version that did merge auto-
  // flagged characters in here, silently expanding both what actually
  // trains next and this screen's own "Focus (n active)" count with
  // characters the learner never chose -- on-device testing found that
  // needed two taps to actually select such a character, since the
  // first tap deselected the invisible pre-existing selection). So
  // membership in this set means "the learner tapped this," full stop,
  // and the border below can mean exactly that too.
  final Set<String> _selected = {};
  // Characters a training session flagged automatically (morse_icr_spec.md
  // section 39) that the learner hasn't reviewed yet -- a suggestion,
  // not a selection (see [_selected]'s own doc comment: this set never
  // adds to that one). Any tap on a chip, on or off, counts as reviewing
  // it and removes it from this set; [_done] persists whatever remains.
  final Set<String> _autoFlagged = {};
  // The learner's all-time per-character win count, keyed by character --
  // absent keys are treated as zero. Drives each chip's heat-map color;
  // see [_heatMapColor].
  Map<String, int> _scores = {};
  // The learner's all-time per-character attempt count (hits + misses),
  // keyed by character -- absent keys are treated as zero. Only used
  // alongside [_scores] to compute [_correctPercentage]; not shown on
  // the chips themselves.
  Map<String, int> _attempts = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Pre-populates the keyboard with whatever was saved last time, so
    // re-opening it to make a small edit doesn't start from a blank
    // slate (section 11: "The user should be able to edit... the list
    // at any time").
    Future.wait([
      widget.store.load(),
      widget.store.loadAutoFlagged(),
      widget.store.loadScores(),
      widget.store.loadAttempts(),
    ]).then((results) {
      if (!mounted) return;
      final characters = results[0] as List<String>?;
      final autoFlagged = results[1] as Set<String>;
      final scores = results[2] as Map<String, int>;
      final attempts = results[3] as Map<String, int>;
      setState(() {
        if (characters != null) _selected.addAll(characters);
        _autoFlagged.addAll(autoFlagged);
        _scores = scores;
        _attempts = attempts;
        _loaded = true;
      });
    });
  }

  Future<void> _done() async {
    // [allCharacters]' own order, not selection order, so the
    // persisted/returned list is always in a stable, predictable order
    // regardless of which order the learner tapped characters in. Saved
    // (and returned) even when empty -- Clear-then-Done is how the
    // learner explicitly clears the problem-character set entirely,
    // not just for the rest of this session (on-device testing:
    // treating an empty Done as a plain cancel left Clear looking
    // broken, since neither the persisted list nor TrainingScreen's own
    // active-count indicator ever actually changed). [TrainingScreen]
    // is what turns an empty list back into "no problem set active."
    final characters = [
      for (final character in allCharacters)
        if (_selected.contains(character)) character,
    ];
    await widget.store.save(characters);
    await widget.store.saveAutoFlagged(_autoFlagged);
    // [_scores] is only ever what [loadScores] returned or (after Clear)
    // an empty map -- this screen has no way to edit an individual
    // character's score -- so re-saving it here is a no-op unless Clear
    // wiped it, in which case this is what actually commits that wipe.
    await widget.store.saveScores(_scores);
    // [_attempts] follows the exact same re-save/no-op-unless-Clear rule
    // as [_scores] just above -- see that call's own comment.
    await widget.store.saveAttempts(_attempts);
    if (!mounted) return;
    Navigator.of(context).pop(characters);
  }

  void _clear() {
    setState(() {
      _selected.clear();
      _autoFlagged.clear();
      // Resets every chip to transparent, not just deselected -- Clear
      // is the learner's "start over" action for this whole screen, and
      // a still-colored chip after Clear read as broken (the color is
      // the only visible state left once nothing's selected anymore).
      // Local-only until Done, same as [_selected]/[_autoFlagged] above.
      // Reassigned rather than [Map.clear]-ed in place: [loadScores]
      // is free to hand back an unmodifiable map (a const `{}` default
      // in particular, as the test fake does), which [clear] would
      // throw on.
      _scores = {};
      // Resets [_correctPercentage] to hidden along with it -- same
      // reasoning and same unmodifiable-map caveat as [_scores] above.
      _attempts = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Default AppBar title is single-line-ellipsis; taller toolbar
        // plus an explicit line count gives "Focus Characters" room to
        // wrap instead of truncating to "Focus C..." (Bill, on-device).
        toolbarHeight: 72,
        title: const Text(
          'Focus\nCharacters',
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
        actions: [
          TextButton(
            onPressed: _loaded ? _clear : null,
            child: const Text('Clear'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _loaded ? _done : null,
              child: const Text('Done'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _loaded
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final character in allCharacters)
                              Builder(
                                builder: (context) {
                                  final isSelected = _selected.contains(
                                    character,
                                  );
                                  // A missing entry means never trained
                                  // (transparent); a present one -- even a 0,
                                  // for a character that's always been missed
                                  // -- means it has, and gets colored (see
                                  // [TrainingScreen._persistCharacterScores]
                                  // for why presence and value are tracked
                                  // separately).
                                  final hasScore = _scores.containsKey(
                                    character,
                                  );
                                  final score = _scores[character] ?? 0;
                                  final color = hasScore
                                      ? _heatMapColor(score, _maxScore)
                                      : Colors.transparent;
                                  final textColor = _readableTextColor(color);
                                  return FilterChip(
                                    label: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          character,
                                          style: TextStyle(color: textColor),
                                        ),
                                        // RichText, not Text -- a bare Text
                                        // here would make the score digits
                                        // ambiguous with the digit *chips*
                                        // ('0'-'9' are themselves characters
                                        // in [allCharacters]) for any test or
                                        // tooling that finds chips by their
                                        // label text.
                                        RichText(
                                          textScaler: MediaQuery.textScalerOf(
                                            context,
                                          ),
                                          text: TextSpan(
                                            text: '$score',
                                            style: TextStyle(
                                              color: textColor,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    showCheckmark: false,
                                    backgroundColor: color,
                                    selectedColor: color,
                                    selected: isSelected,
                                    // A training session's own missed-
                                    // character auto-flagging never selects
                                    // a character by itself (see [_selected]'s
                                    // doc comment) -- [isSelected] here is
                                    // only ever true for one the learner
                                    // actually tapped, so the border stays
                                    // exactly "you picked this."
                                    side: isSelected
                                        ? BorderSide(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            width: 2.5,
                                          )
                                        : null,
                                    onSelected: (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selected.add(character);
                                        } else {
                                          _selected.remove(character);
                                        }
                                        _autoFlagged.remove(character);
                                      });
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                        // Directly under the chip grid rather than
                        // detached at the physical bottom of the screen
                        // (e.g. via `bottomNavigationBar`) -- Bill found
                        // the detached placement read as floating in the
                        // middle of the screen whenever the grid didn't
                        // fill the available height, since [Center]
                        // above vertically centers this whole column
                        // (2026-08-31). Hidden until there's at least one
                        // recorded attempt (see [_correctPercentage]).
                        if (_correctPercentage != null) ...[
                          const SizedBox(height: 24),
                          Text(
                            '$_correctPercentage% Correct',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
    );
  }

  // All-time accuracy across every character that's ever been attempted
  // -- total correct answers ([_scores]' values) over total attempts
  // ([_attempts]' values), as a rounded percentage. Null (hidden, per
  // [build]) until at least one character has recorded an attempt, the
  // same "nothing to show yet" gate [_maxScore]/[_heatMapColor] use.
  // Recomputed from these fields' latest load every time this screen
  // opens, so consecutive sessions that keep adding to the persisted
  // tallies (Clear not tapped in between) always reflect the newest
  // cumulative total, not a stale snapshot from an earlier visit.
  int? get _correctPercentage {
    final totalAttempts = _attempts.values.fold<int>(0, (sum, v) => sum + v);
    if (totalAttempts == 0) return null;
    final totalCorrect = _scores.values.fold<int>(0, (sum, v) => sum + v);
    return ((totalCorrect / totalAttempts) * 100).round();
  }

  // The highest score among every character that's ever been trained
  // (i.e. every value in [_scores], which -- see
  // [TrainingScreen._persistCharacterScores] -- only holds entries for
  // characters actually attempted at least once). This is exactly the
  // population that gets colored at all, so scaling against it means the
  // single best-performing trained character always reads full green,
  // whatever "best" happens to be.
  int get _maxScore {
    var max = 0;
    for (final score in _scores.values) {
      if (score > max) max = score;
    }
    return max;
  }

  // Red (few/no correct answers) to green (many), scaled against
  // [maxScore] -- see [_maxScore]. Before any character has ever
  // recorded a correct answer (every score, including the max, is 0),
  // there's nothing to scale against -- every trained-but-always-missed
  // character reads the same base red rather than a meaningless
  // division.
  //
  // Interpolated through HSV hue (red at 0 deg through orange/yellow to
  // green at 120 deg) rather than [Color.lerp]'s straight RGB blend --
  // RGB-lerping red toward green crosses through a muddy, desaturated
  // brownish-gray at the midpoint, which Bill flagged on-device as
  // "colors appear too dull" (2026-08-30). A hue sweep at full
  // saturation/value stays vivid across the whole range.
  Color _heatMapColor(int score, int maxScore) {
    const heatMapRed = HSVColor.fromAHSV(1, 0, 1, 1);
    const heatMapGreen = HSVColor.fromAHSV(1, 120, 1, 0.85);
    if (maxScore == 0) return heatMapRed.toColor();
    final t = (score / maxScore).clamp(0.0, 1.0);
    return HSVColor.lerp(heatMapRed, heatMapGreen, t)!.toColor();
  }

  // Keeps the character and its score legible against any heat-map
  // color the chip lands on -- null (the chip's own default label color)
  // for a transparent chip, since [ThemeData.estimateBrightnessForColor]
  // would otherwise read transparent's black RGB as "dark" and pick white
  // text regardless of what's actually behind it.
  Color? _readableTextColor(Color background) {
    if (background == Colors.transparent) return null;
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }
}
