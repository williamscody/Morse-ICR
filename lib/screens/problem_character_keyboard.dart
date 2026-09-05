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
  // Position of the Focusizer slider, 0 to [_rankedByScore]'s length --
  // purely transient UI state, reset to 0 (leftmost, per its own doc
  // comment) every time this screen opens rather than persisted, since
  // the intended flow is "open Focus fresh after a session, then drag
  // left-to-right." Only [_onFocusSliderChanged] ever touches [_selected]
  // because of this value; it plays no other part in what's selected.
  double _focusSliderValue = 0;

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

  // Every character with a recorded score ([_scores]' keys -- see that
  // field's own doc comment for why absence means "never trained"),
  // worst-scoring first. This is the order the Focusizer slider fills
  // selection in as it moves left to right (see
  // [_onFocusSliderChanged]) -- a character that's never been trained
  // has no score to rank by, so it never gets selected by the slider,
  // only by a direct tap. Ties break on [allCharacters]' own order (not
  // sort stability, which Dart's [List.sort] doesn't guarantee) so the
  // ranking -- and therefore what the slider selects at a given value --
  // stays deterministic across rebuilds.
  List<String> get _rankedByScore {
    final ranked = [
      for (final character in allCharacters)
        if (_scores.containsKey(character)) character,
    ];
    ranked.sort((a, b) {
      final scoreCompare = _scores[a]!.compareTo(_scores[b]!);
      if (scoreCompare != 0) return scoreCompare;
      return allCharacters.indexOf(a).compareTo(allCharacters.indexOf(b));
    });
    return ranked;
  }

  // Column count for the character grid below (see [_gridSlots] and the
  // [GridView.builder] itself in [build]) -- a single source shared by
  // both so they can never disagree on how wide a row is.
  static const _crossAxisCount = 6;

  // [allCharacters] padded with `null`s so the grid below can pass this
  // straight to [GridView.builder] as its item list: a `null` renders as
  // an empty cell (see the `itemBuilder` in [build]). [allCharacters] is
  // 40 long, so 40 % 6 leaves a trailing row of just 4 -- left-aligned by
  // default, since a grid simply places items left-to-right with nothing
  // to fill the row's remaining 2 columns. Centering that row means
  // leaving 1 empty cell before it and 1 after; the `null`s inserted here
  // supply the leading one (the trailing one needs nothing -- the grid
  // already stops there once it runs out of items). (Bill, 2026-09-02:
  // "center the last row of chips by moving them all to the right by one
  // location.")
  List<String?> get _gridSlots {
    final lastRowCount = allCharacters.length % _crossAxisCount;
    if (lastRowCount == 0) return allCharacters;
    final fullRowsCount = allCharacters.length - lastRowCount;
    final leadingGap = (_crossAxisCount - lastRowCount) ~/ 2;
    return [
      ...allCharacters.take(fullRowsCount),
      for (var i = 0; i < leadingGap; i++) null,
      ...allCharacters.skip(fullRowsCount),
    ];
  }

  // Recomputes [_selected] from scratch as the worst-scoring
  // [value.round()] characters in [_rankedByScore] -- not a merge with
  // whatever was selected before, so dragging all the way left really
  // does select nothing (per [_focusSliderValue]'s doc comment), even if
  // some characters were manually selected or pre-populated from a prior
  // save. A direct chip tap after this still works exactly as before
  // ([onSelected] below) and is not overwritten again unless the slider
  // itself moves.
  void _onFocusSliderChanged(double value) {
    final ranked = _rankedByScore;
    final count = value.round().clamp(0, ranked.length);
    setState(() {
      _focusSliderValue = value;
      _selected
        ..clear()
        ..addAll(ranked.take(count));
    });
  }

  // Backs the Focusizer's -/+ buttons (2026-09-02, replacing the earlier
  // Bad/Good sentiment icons to match [SteppedIntControl]'s own +/-
  // step pattern elsewhere in the app) -- one step at a time through
  // [_onFocusSliderChanged], same clamping and recompute-from-scratch
  // behavior as dragging the slider itself.
  void _stepFocusSlider(int delta) {
    final newValue = (_focusSliderValue.round() + delta).clamp(
      0,
      _rankedByScore.length,
    );
    _onFocusSliderChanged(newValue.toDouble());
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
        title: const Text('Focus'),
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
        // [LayoutBuilder]+[SingleChildScrollView] rather than a bare
        // [Center], so this still centers everything vertically on any
        // normal device -- where it fits comfortably, same as before --
        // but scrolls instead of hard-overflowing (Flutter's yellow/black
        // error stripes, clipped content) on a device short enough, or
        // with large-enough accessibility text scaling, that it doesn't
        // fit. The [ConstrainedBox]'s `minHeight` is what makes the
        // [Center] below still center a shorter-than-viewport child;
        // without it, [SingleChildScrollView] would top-align its child
        // instead of centering it whenever content fits with room to
        // spare, since a plain scroll view sizes to fill the viewport
        // rather than to its own content. The 40-chip grid's own row
        // height grew 35% (2026-09-02, taller rectangles instead of
        // squares -- Bill: "need to be rectangles large enough to hold
        // the letter and the tally number"), eating into a vertical
        // budget this screen never had much slack in to begin with.
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Padding(
                      // Less padding above the chips than to the
                      // sides/below -- with the chips now the first thing
                      // in the column (the Focusizer moved below them,
                      // 2026-09-01), the old uniform 24 on every side left
                      // the whole screen sitting noticeably lower than it
                      // needed to (Bill, on-device).
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: _loaded
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // A fixed-column-count grid rather than [Wrap] --
                                // [Wrap] sizes each chip to its own natural width
                                // (narrower for a single-digit score, wider for a
                                // double-digit one) and only wraps once a row runs
                                // out of room, so rows didn't line up into a clean
                                // grid and how many chips landed per row depended
                                // on which chips happened to be next to each other
                                // (Bill, 2026-09-02: "align all the chips... evenly
                                // spaced and distributed"). [allCharacters] is 40
                                // long (26 letters + 10 numbers + 4 punctuation),
                                // so 6 columns gives exactly six full rows plus one
                                // trailing row of 4 -- [SliverGridDelegateWithFixedCrossAxisCount]
                                // gives every one of those 40 cells the exact same
                                // width and height regardless of device width (the
                                // grid divides whatever space is available evenly
                                // across 6 columns), and forces each [FilterChip]
                                // to fill its cell rather than sizing to its own
                                // label, so every chip -- first row or last -- ends
                                // up identically sized. [mainAxisExtent] is 35%
                                // taller than the chip's own natural unconstrained
                                // height (43.2, see the padding comment below) --
                                // forcing chips into a perfect square read as too
                                // cramped for a label that's two lines (character
                                // plus tally number) rather than one (Bill,
                                // 2026-09-02: "need to be rectangles large enough
                                // to hold the letter and the tally number").
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _gridSlots.length,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: _crossAxisCount,
                                        crossAxisSpacing: 8,
                                        mainAxisSpacing: 8,
                                        mainAxisExtent: 58.3,
                                      ),
                                  itemBuilder: (context, index) {
                                    final character = _gridSlots[index];
                                    // A null slot is one of the empty cells
                                    // [_gridSlots] pads the trailing partial
                                    // row with to center it (Bill,
                                    // 2026-09-02: "center the last row of
                                    // chips by moving them all to the right
                                    // by one location") -- nothing to render
                                    // there.
                                    if (character == null) {
                                      return const SizedBox.shrink();
                                    }
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
                                    final chip = FilterChip(
                                      label: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            character,
                                            // 'W' is noticeably wider than
                                            // every other single-character
                                            // label -- without these, its
                                            // glyph sat right at the edge of
                                            // the available label width and
                                            // rendered with its trailing edge
                                            // clipped off, reading as a faint,
                                            // partial letter rather than
                                            // wrapping (Bill, on-device,
                                            // 2026-09-04). Same fix as the
                                            // tally [RichText] below.
                                            softWrap: false,
                                            overflow: TextOverflow.visible,
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
                                            // A tally in the high teens/twenties
                                            // is exactly as wide as the chip's
                                            // available label width for some
                                            // digit pairs but not others (font
                                            // metrics vary per digit) --
                                            // without these, [RichText]'s
                                            // default wrapping would break
                                            // right between the two digits,
                                            // pushing the second one out past
                                            // the chip's own rounded bounds
                                            // instead of keeping the tally on
                                            // one line.
                                            softWrap: false,
                                            maxLines: 1,
                                            overflow: TextOverflow.visible,
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
                                      // Trims the chip's own default vertical
                                      // padding (7 a side) down to 5.6 a
                                      // side -- 8 horizontal is the
                                      // (unchanged) default, kept explicit
                                      // only because [padding] is one
                                      // EdgeInsets -- for a precise 10%
                                      // reduction in overall chip height
                                      // (48 -> 43.2 logical pixels, measured
                                      // via [tester.getSize] on an 'A' chip)
                                      // with the width untouched (Bill,
                                      // 2026-09-02). [shrinkWrap] is required
                                      // alongside it: Material's default tap
                                      // target enforces a 48-tall minimum
                                      // that would otherwise silently
                                      // re-inflate the chip back to its old
                                      // height regardless of this padding.
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 5.6,
                                      ),
                                      backgroundColor: color,
                                      selectedColor: color,
                                      selected: isSelected,
                                      // A training session's own missed-
                                      // character auto-flagging never selects
                                      // a character by itself (see [_selected]'s
                                      // doc comment) -- [isSelected] here is
                                      // only ever true for one the learner
                                      // actually tapped, so the highlight
                                      // below stays exactly "you picked
                                      // this."
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
                                    if (!isSelected) return chip;
                                    // A selected chip's highlight is painted
                                    // as a separate overlay exactly matching
                                    // the chip's own bounds, rather than
                                    // through [FilterChip.side] (2026-09-02)
                                    // -- [side] draws its stroke centered on
                                    // the chip's own shape boundary, which
                                    // grows the chip's actual layout box by
                                    // the border width. That growth used to
                                    // push the old [Wrap] layout into an
                                    // extra row once enough chips were
                                    // selected at once (Bill, on-device:
                                    // "three chips selected and they start
                                    // wrapping"); the grid cells below are
                                    // fixed-size regardless, but this overlay
                                    // approach is kept rather than [side] so
                                    // the border still can't affect layout.
                                    // This overlay instead fills exactly the
                                    // unselected chip's
                                    // own bounds ([Positioned.fill] inside a
                                    // [Stack] whose size comes only from the
                                    // non-positioned [chip] above it) --
                                    // purely painted, so it can never change
                                    // layout. No inset is added around the
                                    // [DecoratedBox]: unlike [BorderSide],
                                    // [Border.paint] draws each side flush
                                    // with its own box's edge and extends
                                    // inward by the stroke width, so the
                                    // highlight's outer edge lands exactly
                                    // on the chip's outer edge with no
                                    // manual half-width compensation needed
                                    // (Bill, on-device, 2026-09-02: an
                                    // earlier version that did add that inset
                                    // -- reasoning from [BorderSide]'s
                                    // centered-stroke behavior -- left the
                                    // highlight visibly smaller than the
                                    // chip). [IgnorePointer] passes taps
                                    // through to the chip below so tapping
                                    // the highlighted ring still (de)selects
                                    // it. Painted last (the front layer),
                                    // on top of [chip] -- a brief attempt at
                                    // the opposite order (2026-09-04, to keep
                                    // the ring from cutting across tally text
                                    // that spilled past the chip's own
                                    // bounds) instead left the ring looking
                                    // "too thin" top and bottom: the chip's
                                    // own Material shape is more rounded at
                                    // its left/right ends than this ring's
                                    // fixed 8px corner radius, so with the
                                    // opaque chip on top it covered nearly
                                    // all of the ring except slivers peeking
                                    // out near the corners (Bill, on-device).
                                    // That spill is now prevented at the
                                    // source instead (the [RichText] above no
                                    // longer wraps), so the ring can safely
                                    // go back to being the top layer, drawing
                                    // a clean, uniform 4px border on all four
                                    // sides regardless of the chip's own
                                    // shape underneath.
                                    return Stack(
                                      // [StackFit.expand] rather than the default
                                      // loose -- a grid tile forces this whole
                                      // [Stack] to its exact cell size, but [Stack]
                                      // by default only gives *loose* constraints
                                      // to a non-positioned child like [chip],
                                      // which then sizes itself to its own natural
                                      // (label-driven) width instead of filling
                                      // the cell -- so a selected chip rendered
                                      // narrower than an unselected one in the
                                      // same grid. [StackFit.expand] makes every
                                      // non-positioned child fill the [Stack]'s
                                      // size too, keeping selected and unselected
                                      // chips identically sized.
                                      fit: StackFit.expand,
                                      children: [
                                        chip,
                                        Positioned.fill(
                                          key: Key(
                                            'focus-highlight-$character',
                                          ),
                                          child: IgnorePointer(
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: _selectedBorderColor(
                                                    context,
                                                  ),
                                                  width: _selectedBorderWidth,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'Focusizer ${_selected.length}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                                // Shrinks the slider's default touch-target
                                // overlay/thumb, and its own reserved top/bottom
                                // padding (`padding: EdgeInsets.zero`, matching
                                // [SteppedIntControl]'s identical slider elsewhere
                                // in the app), so the visible track sits right
                                // under the label above instead of leaving a gap
                                // (Bill, on-device, 2026-09-01/02) -- a stock
                                // [Slider] reserves extra invisible padding around
                                // its track for the thumb's tap/ripple area.
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 3,
                                    padding: EdgeInsets.zero,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 8,
                                    ),
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                  ),
                                  child: Row(
                                    children: [
                                      IconButton(
                                        visualDensity: const VisualDensity(
                                          horizontal: -2,
                                          vertical: -2,
                                        ),
                                        iconSize: 26,
                                        icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: _heatMapRedColor,
                                        ),
                                        onPressed: _rankedByScore.isEmpty
                                            ? null
                                            : () => _stepFocusSlider(-1),
                                      ),
                                      Expanded(
                                        child: Slider(
                                          value: _focusSliderValue.clamp(
                                            0,
                                            _rankedByScore.length.toDouble(),
                                          ),
                                          min: 0,
                                          // A max/divisions of 0 (nothing trained
                                          // yet, see [_rankedByScore]) would be a
                                          // degenerate, unusable [Slider] -- fall
                                          // back to a disabled 0-to-1 slider
                                          // rather than dividing by zero.
                                          max: _rankedByScore.isEmpty
                                              ? 1
                                              : _rankedByScore.length
                                                    .toDouble(),
                                          divisions: _rankedByScore.isEmpty
                                              ? null
                                              : _rankedByScore.length,
                                          onChanged: _rankedByScore.isEmpty
                                              ? null
                                              : _onFocusSliderChanged,
                                        ),
                                      ),
                                      IconButton(
                                        visualDensity: const VisualDensity(
                                          horizontal: -2,
                                          vertical: -2,
                                        ),
                                        iconSize: 26,
                                        icon: Icon(
                                          Icons.add_circle_outline,
                                          color: _heatMapGreenColor,
                                        ),
                                        onPressed: _rankedByScore.isEmpty
                                            ? null
                                            : () => _stepFocusSlider(1),
                                      ),
                                    ],
                                  ),
                                ),
                                // In-column, directly under the Focusizer, rather
                                // than detached at the physical bottom of the
                                // screen (e.g. via `bottomNavigationBar`) -- Bill
                                // found the detached placement read as floating
                                // in the middle of the screen whenever the
                                // content above didn't fill the available height,
                                // since [Center] above vertically centers this
                                // whole column (2026-08-31). Hidden until there's
                                // at least one recorded attempt (see
                                // [_correctPercentage]).
                                if (_correctPercentage != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    '$_correctPercentage% Correct',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
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
          },
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
    if (maxScore == 0) return _heatMapRedColor;
    final t = (score / maxScore).clamp(0.0, 1.0);
    return HSVColor.lerp(_heatMapRedHsv, _heatMapGreenHsv, t)!.toColor();
  }

  // Backing values for [_heatMapColor] plus the Focusizer slider's own
  // Bad/Good end icons (2026-09-01) -- shared so the icons read as
  // exactly the same red/green the chips themselves use.
  static const _heatMapRedHsv = HSVColor.fromAHSV(1, 0, 1, 1);
  static const _heatMapGreenHsv = HSVColor.fromAHSV(1, 120, 1, 0.85);
  static final Color _heatMapRedColor = _heatMapRedHsv.toColor();
  static final Color _heatMapGreenColor = _heatMapGreenHsv.toColor();

  // A selected chip's border -- fixed rather than [ColorScheme.primary]
  // (2026-09-02: the app's teal primary read too close to the heat map's
  // own green end, and too dim generally, to reliably stand out in
  // either light or dark mode, Bill on-device). Cyan is red's direct
  // hue-wheel opposite (180 deg from red's 0, versus green's 120) --
  // pink, tried first, still read too close to red for Bill on-device --
  // so it stays legible against any chip color; a bit thicker than the
  // old 2.5 for the same reason.
  //
  // Cyan alone stopped being enough once this ring also had to read
  // against the screen's own light-mode background (2026-09-04, Bill:
  // "light teal color is too hard to differentiate from the light
  // background") -- a pale, unsaturated cyan sits too close to an
  // off-white background even though it still pops against a dark one.
  // Dark mode keeps the original cyan; light mode switches to a deep
  // indigo, which is both far darker than the light background and, on
  // the hue wheel, still well clear of every heat-map color from red
  // through green.
  Color _selectedBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.cyanAccent
        : Colors.indigo.shade900;
  }

  static const _selectedBorderWidth = 4.0;

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
