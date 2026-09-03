import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/problem_character_keyboard.dart';
import 'package:morse_icr/training/character_set.dart';
import 'package:morse_icr/training/problem_character_store.dart';

class _FakeProblemCharacterStore implements ProblemCharacterStore {
  _FakeProblemCharacterStore([
    this.saved,
    this.savedAutoFlagged = const {},
    this.savedScores = const {},
    this.savedAttempts = const {},
  ]);

  List<String>? saved;
  Set<String> savedAutoFlagged;
  Map<String, int> savedScores;
  Map<String, int> savedAttempts;

  @override
  Future<List<String>?> load() async => saved;

  @override
  Future<void> save(List<String> characters) async {
    saved = characters;
  }

  @override
  Future<Set<String>> loadAutoFlagged() async => savedAutoFlagged;

  @override
  Future<void> saveAutoFlagged(Set<String> characters) async {
    savedAutoFlagged = characters;
  }

  @override
  Future<Map<String, int>> loadScores() async => savedScores;

  @override
  Future<void> saveScores(Map<String, int> scores) async {
    savedScores = scores;
  }

  @override
  Future<Map<String, int>> loadAttempts() async => savedAttempts;

  @override
  Future<void> saveAttempts(Map<String, int> attempts) async {
    savedAttempts = attempts;
  }
}

// Mirrors ProblemCharacterKeyboard._heatMapColor's HSV-based gradient
// (2026-08-30: switched from a straight RGB lerp, which produced a dull,
// muddy midpoint, to a full-saturation hue sweep).
const _heatMapRedHsv = HSVColor.fromAHSV(1, 0, 1, 1);
const _heatMapGreenHsv = HSVColor.fromAHSV(1, 120, 1, 0.85);
final Color _heatMapRed = _heatMapRedHsv.toColor();
final Color _heatMapGreen = _heatMapGreenHsv.toColor();

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  // A selected chip's highlight ring is a separate overlay keyed
  // 'focus-highlight-<character>' (see ProblemCharacterKeyboard's own
  // comment on why it's not FilterChip's own [side] any more), rather
  // than something readable off the [FilterChip] itself.
  bool isHighlighted(WidgetTester tester, String character) =>
      find.byKey(Key('focus-highlight-$character')).evaluate().isNotEmpty;

  testWidgets(
    'chips fill their grid cell -- 35% taller than wide, per-column width, '
    'not sized to their own label',
    (tester) async {
      await tester.pumpWidget(
        wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
      );
      await tester.pump();

      final size = tester.getSize(find.widgetWithText(FilterChip, 'A'));
      // Chip size is entirely grid-driven, not content-driven (2026-09-02:
      // chips moved from a [Wrap], which sized each chip to its own label,
      // to a fixed 6-column grid so every chip -- not just chips with the
      // same label length -- is identically sized). Width is whatever one
      // of 6 equal columns comes out to across the 432-logical-pixel
      // content area ([ConstrainedBox]'s 480 max width minus the screen's
      // 24-a-side padding) with 5 8-pixel gaps between them. Height
      // (mainAxisExtent) is a fixed 58.3 -- 35% taller than the chip's own
      // former unconstrained height of 43.2 -- deliberately taller than
      // wide so the two-line label (character plus tally number) has
      // enough room without the cell reading as a cramped square (Bill,
      // 2026-09-02).
      expect(size.height, closeTo(58.3, 0.5));
      expect(size.width, closeTo((432 - 5 * 8) / 6, 0.5));
    },
  );

  testWidgets(
    'the trailing partial row is centered -- shifted one column right so '
    'it leaves one empty cell on each side, rather than left-aligned '
    'against the six full rows above it',
    (tester) async {
      await tester.pumpWidget(
        wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
      );
      await tester.pump();

      // allCharacters is 26 letters + 10 numbers + 4 punctuation, so the
      // trailing (7th) row is exactly the punctuation set ('.', ',', '?',
      // '/') -- '.' is that row's own first (leftmost) character, and
      // 'B' is column 1 (the second column) of the very first row.
      // Centering the short row should put '.' in that same column, one
      // in from the left edge rather than flush against it.
      expect(
        tester.getTopLeft(find.widgetWithText(FilterChip, '.')).dx,
        tester.getTopLeft(find.widgetWithText(FilterChip, 'B')).dx,
      );
      // '/' is the trailing row's last character; 'E' (the 5th letter) is
      // column 4 of the first row -- the same column '/' should land in
      // once the row is centered (column 1 through column 4).
      expect(
        tester.getTopLeft(find.widgetWithText(FilterChip, '/')).dx,
        tester.getTopLeft(find.widgetWithText(FilterChip, 'E')).dx,
      );
    },
  );

  testWidgets(
    'selecting a chip never changes its own size, and selecting every '
    'chip never changes the grids overall size -- regression: chips '
    'used to reflow onto an extra row once a few were selected, and the '
    'whole grid grew once every chip was selected, because the old '
    'selection border grew the chips own layout box',
    (tester) async {
      await tester.pumpWidget(
        wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
      );
      await tester.pump();

      final chipSizeBefore = tester.getSize(
        find.widgetWithText(FilterChip, 'A'),
      );
      final gridSizeBefore = tester.getSize(find.byType(GridView));

      for (final character in allCharacters) {
        await tester.tap(
          find.widgetWithText(FilterChip, character),
          warnIfMissed: false,
        );
      }
      await tester.pump();

      // Every character is now selected.
      final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
      expect(chips.every((chip) => chip.selected), isTrue);

      expect(
        tester.getSize(find.widgetWithText(FilterChip, 'A')),
        chipSizeBefore,
      );
      expect(tester.getSize(find.byType(GridView)), gridSizeBefore);
    },
  );

  testWidgets("a selected chip's highlight ring exactly matches the chip's own "
      'outer size -- regression: an earlier version inset the ring by '
      "half the border width (reasoning from BorderSide's centered-stroke "
      "behavior, which doesn't apply to a plain Border), leaving the "
      'highlight visibly smaller than the chip', (tester) async {
    await tester.pumpWidget(
      wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore(['A']))),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byKey(const Key('focus-highlight-A'))),
      tester.getSize(find.widgetWithText(FilterChip, 'A')),
    );
  });

  testWidgets('shows every letter, digit, and the minimum punctuation set, '
      'none selected, when nothing was previously saved', (tester) async {
    await tester.pumpWidget(
      wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
    );
    await tester.pump();

    for (final character in ['A', 'Z', '0', '9', '.', ',', '?', '/']) {
      expect(find.widgetWithText(FilterChip, character), findsOneWidget);
    }
    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(chips.every((chip) => !chip.selected), isTrue);
  });

  testWidgets('pre-selects whatever was previously saved', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(['K', 'R', 'F']),
        ),
      ),
    );
    await tester.pump();

    for (final character in ['K', 'R', 'F']) {
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, character))
            .selected,
        isTrue,
      );
    }
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'A')).selected,
      isFalse,
    );
  });

  testWidgets('chips are transparent, not red, when no score has ever been '
      'recorded for any character', (tester) async {
    await tester.pumpWidget(
      wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
    );
    await tester.pump();

    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(
      chips.every((chip) => chip.backgroundColor == Colors.transparent),
      isTrue,
    );
  });

  testWidgets('chips with a score entry are heat-map colored -- red at zero, '
      'greener the higher the score, scaled against the highest score on '
      'the board -- regardless of whether they happen to be selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(null, const {}, {'K': 10, 'F': 0}),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
          .backgroundColor,
      _heatMapGreen,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
          .backgroundColor,
      _heatMapRed,
    );
    // Never trained at all -- no entry, so transparent, unlike F's
    // explicit 0 above.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'A'))
          .backgroundColor,
      Colors.transparent,
    );
  });

  testWidgets('coloring depends only on having a score, not on selection -- an '
      'unselected character that was actually trained (e.g. training a '
      'whole character set like A-Z without ever using the Focus picker) '
      'colors the same as a selected one with the same score', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(
            ['K'],
            const {},
            {'K': 10, 'F': 10},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
          .backgroundColor,
      _heatMapGreen,
    );
    // F has the same score as K, and colors identically, even though
    // it was never selected on this screen.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
          .backgroundColor,
      _heatMapGreen,
    );
  });

  testWidgets('the heat map scales against the highest score anywhere on the '
      'board, including an unselected character\'s', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(['K'], const {}, {'K': 2, 'F': 10}),
        ),
      ),
    );
    await tester.pump();

    // F (unselected) has the board's highest score -- full green, and
    // what K's own, much lower score is scaled against.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
          .backgroundColor,
      _heatMapGreen,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
          .backgroundColor,
      HSVColor.lerp(_heatMapRedHsv, _heatMapGreenHsv, 2 / 10)!.toColor(),
    );
  });

  testWidgets('shows an all-time "X% Correct" summary at the bottom once any '
      'character has a recorded attempt, totaled across every character', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(
            null,
            const {},
            {'K': 8, 'F': 2},
            {'K': 10, 'F': 10},
          ),
        ),
      ),
    );
    await tester.pump();

    // 10 correct out of 20 attempted, across both characters combined.
    expect(find.text('50% Correct'), findsOneWidget);
  });

  testWidgets('hides the "Correct" summary until at least one character has '
      'a recorded attempt', (tester) async {
    await tester.pumpWidget(
      wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
    );
    await tester.pump();

    expect(find.textContaining('Correct'), findsNothing);
  });

  testWidgets(
    'Clear hides the "Correct" summary immediately, and Done commits that '
    'reset',
    (tester) async {
      final store = _FakeProblemCharacterStore(
        null,
        const {},
        {'K': 5},
        {'K': 5},
      );
      await tester.pumpWidget(wrap(ProblemCharacterKeyboard(store: store)));
      await tester.pump();
      expect(find.text('100% Correct'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.textContaining('Correct'), findsNothing);

      // Not persisted merely by tapping Clear...
      expect(store.savedAttempts, {'K': 5});

      await tester.tap(find.text('Done'));
      await tester.pump();

      // ...but Done commits the reset, same as it does for scores.
      expect(store.savedAttempts, isEmpty);
    },
  );

  testWidgets('selecting a chip toggles only its border -- its heat-map fill, '
      'driven purely by score, is unaffected by selection', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(null, const {}, {'K': 5}),
        ),
      ),
    );
    await tester.pump();

    expect(isHighlighted(tester, 'K'), isFalse);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
          .backgroundColor,
      _heatMapGreen,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    expect(isHighlighted(tester, 'K'), isTrue);
    // A fixed, vivid color/width (2026-09-02) -- not the theme's own
    // primary -- so the selection highlight reads clearly against any
    // heat-map fill in both light and dark mode.
    final decoratedBox = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const Key('focus-highlight-K')),
        matching: find.byType(DecoratedBox),
      ),
    );
    final border = (decoratedBox.decoration as BoxDecoration).border as Border;
    expect(border.top.color, Colors.cyanAccent);
    expect(border.top.width, 4.0);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
          .backgroundColor,
      _heatMapGreen,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    expect(isHighlighted(tester, 'K'), isFalse);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
          .backgroundColor,
      _heatMapGreen,
    );
  });

  testWidgets(
    'a character that is both a previously-saved (manual) selection and '
    'currently auto-flagged still borders -- auto-flagging is a '
    'suggestion layered on top of, not a substitute for, an actual '
    'selection',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ProblemCharacterKeyboard(
            store: _FakeProblemCharacterStore(['K'], {'K'}, {'K': 5}),
          ),
        ),
      );
      await tester.pump();

      // K was manually selected and saved in an earlier visit to this
      // screen (`saved: ['K']`) -- a *later* training session having
      // since flagged it too (`savedAutoFlagged: {'K'}`, e.g. it started
      // being missed again) doesn't take that selection away.
      expect(isHighlighted(tester, 'K'), isTrue);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .backgroundColor,
        _heatMapGreen,
      );

      // Tapping it off then back on reviews it either way (clears the
      // auto-flag), landing back at the same selected+bordered state.
      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      expect(isHighlighted(tester, 'K'), isTrue);
    },
  );

  testWidgets(
    'an auto-flagged-only character (never manually selected/saved) is '
    'not pre-selected and does not border on load -- one tap selects it '
    'cleanly, not two',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ProblemCharacterKeyboard(
            store: _FakeProblemCharacterStore(null, {'K'}, {'K': 5}),
          ),
        ),
      );
      await tester.pump();

      expect(isHighlighted(tester, 'K'), isFalse);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isFalse,
      );

      // One tap selects and highlights it -- not two.
      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isTrue,
      );
      expect(isHighlighted(tester, 'K'), isTrue);
    },
  );

  testWidgets(
    'Done persists whatever auto-flagged characters remain unreviewed',
    (tester) async {
      final store = _FakeProblemCharacterStore(['K', 'F'], {'K', 'F'});
      await tester.pumpWidget(wrap(ProblemCharacterKeyboard(store: store)));
      await tester.pump();

      // Review K by tapping it off then back on -- F stays unreviewed.
      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(store.savedAutoFlagged, {'F'});
    },
  );

  testWidgets('backing out without Done leaves the persisted auto-flagged set '
      'untouched', (tester) async {
    final store = _FakeProblemCharacterStore(['K'], {'K'});
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push<List<String>>(
              MaterialPageRoute(
                builder: (_) => ProblemCharacterKeyboard(store: store),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Reviewing K locally, then backing out instead of tapping Done.
    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(store.savedAutoFlagged, {'K'});
  });

  testWidgets('tapping a character toggles its selection', (tester) async {
    await tester.pumpWidget(
      wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isFalse,
    );
  });

  testWidgets('Clear deselects every character without closing the keyboard '
      'or touching the persisted set', (tester) async {
    final store = _FakeProblemCharacterStore(['K', 'R']);
    await tester.pumpWidget(wrap(ProblemCharacterKeyboard(store: store)));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'F'));
    await tester.pump();
    await tester.tap(find.text('Clear'));
    await tester.pump();

    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(chips.every((chip) => !chip.selected), isTrue);
    expect(find.byType(ProblemCharacterKeyboard), findsOneWidget);
    expect(store.saved, ['K', 'R']);
  });

  testWidgets(
    'Clear also removes the local auto-flagged set (and every selection '
    'border with it), without persisting that until Done',
    (tester) async {
      final store = _FakeProblemCharacterStore(['K'], {'K'});
      await tester.pumpWidget(wrap(ProblemCharacterKeyboard(store: store)));
      await tester.pump();

      await tester.tap(find.text('Clear'));
      await tester.pump();

      // K was selected (so highlighted); Clear deselects it, removing the
      // highlight along with the selection.
      expect(isHighlighted(tester, 'K'), isFalse);
      expect(store.savedAutoFlagged, {'K'});
    },
  );

  testWidgets(
    'Clear also resets every chip to transparent, not just deselected -- '
    'and Done commits that score reset',
    (tester) async {
      final store = _FakeProblemCharacterStore(
        ['K'],
        const {},
        {'K': 8, 'F': 8},
      );
      await tester.pumpWidget(wrap(ProblemCharacterKeyboard(store: store)));
      await tester.pump();

      // Both colored before Clear -- K because it's scored and selected,
      // F because coloring doesn't depend on selection.
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .backgroundColor,
        _heatMapGreen,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
            .backgroundColor,
        _heatMapGreen,
      );

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .backgroundColor,
        Colors.transparent,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
            .backgroundColor,
        Colors.transparent,
      );

      // Not persisted merely by tapping Clear...
      expect(store.savedScores, {'K': 8, 'F': 8});

      await tester.tap(find.text('Done'));
      await tester.pump();

      // ...but Done commits the reset, same as it does for the
      // selection and auto-flagged set.
      expect(store.savedScores, isEmpty);
    },
  );

  testWidgets('Done persists the selection and returns it to the caller', (
    tester,
  ) async {
    final store = _FakeProblemCharacterStore();
    List<String>? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => ProblemCharacterKeyboard(store: store),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.tap(find.widgetWithText(FilterChip, 'R'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // [_allCharacters]' own order, not tap order.
    expect(store.saved, ['K', 'R']);
    expect(result, ['K', 'R']);
  });

  testWidgets('Done with nothing selected -- e.g. after Clear -- persists and '
      'returns an empty list, rather than leaving the previous save intact', (
    tester,
  ) async {
    final store = _FakeProblemCharacterStore(['K']);
    List<String>? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => ProblemCharacterKeyboard(store: store),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(result, isEmpty);
    expect(store.saved, isEmpty);
  });

  testWidgets('backing out without ever tapping Done leaves the persisted '
      'set untouched and returns no result', (tester) async {
    final store = _FakeProblemCharacterStore(['K']);
    List<String>? result;
    var pushReturned = false;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<String>>(
                MaterialPageRoute(
                  builder: (_) => ProblemCharacterKeyboard(store: store),
                ),
              );
              pushReturned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'K')); // deselect
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(pushReturned, isTrue);
    expect(result, isNull);
    expect(store.saved, ['K']);
  });

  testWidgets('titles the AppBar "Focus" and shows an italic "Focusizer N" '
      'label -- N being the current selection count -- with red-/green+ '
      'buttons on its slider', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(['K', 'R'], const {}, {'K': 5}),
        ),
      ),
    );
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Focus'), findsOneWidget);
    final label = tester.widget<Text>(find.text('Focusizer 2'));
    expect(label.style?.fontStyle, FontStyle.italic);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

    // The count tracks selection changes, both manual...
    await tester.tap(find.widgetWithText(FilterChip, 'F'));
    await tester.pump();
    expect(find.text('Focusizer 3'), findsOneWidget);

    // ...and slider-driven.
    tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
    await tester.pump();
    expect(find.text('Focusizer 0'), findsOneWidget);
  });

  testWidgets(
    'the Focusizer slider and its -/+ buttons are disabled when nothing '
    'has been scored yet',
    (tester) async {
      await tester.pumpWidget(
        wrap(ProblemCharacterKeyboard(store: _FakeProblemCharacterStore())),
      );
      await tester.pump();

      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.remove_circle_outline),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.add_circle_outline),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'the - and + buttons step the Focusizer slider by one worst-scoring '
    'character at a time',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ProblemCharacterKeyboard(
            store: _FakeProblemCharacterStore(null, const {}, {'F': 0, 'K': 5}),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isFalse,
      );

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isTrue,
      );

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isFalse,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'F'))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets(
    'dragging the Focusizer slider to its leftmost value selects nothing, '
    'even overriding a previously-saved selection',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          ProblemCharacterKeyboard(
            store: _FakeProblemCharacterStore(['K'], const {}, {'K': 5}),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isTrue,
      );

      tester.widget<Slider>(find.byType(Slider)).onChanged!(0);
      await tester.pump();

      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isFalse,
      );
    },
  );

  testWidgets('the Focusizer slider selects characters worst-score-first as it '
      'moves right, tie-breaking equal scores by allCharacters order, and '
      'never auto-selects a character with no recorded score', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(null, const {}, {
            'R': 0,
            'F': 0,
            'K': 5,
          }),
        ),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1);
    await tester.pump();
    // F sorts before R in allCharacters, so at value 1 (worst-of-1) F
    // is the tie-break winner between the two 0-scored characters.
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'F')).selected,
      isTrue,
    );
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'R')).selected,
      isFalse,
    );
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isFalse,
    );

    slider.onChanged!(3);
    await tester.pump();
    for (final character in ['F', 'R', 'K']) {
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, character))
            .selected,
        isTrue,
      );
    }
    // Never trained at all -- no score to rank by, so a tap is the
    // only way to select it, even at the slider's rightmost value.
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'A')).selected,
      isFalse,
    );
  });

  testWidgets('a manual tap after moving the Focusizer slider overrides its '
      'selection until the slider moves again', (tester) async {
    await tester.pumpWidget(
      wrap(
        ProblemCharacterKeyboard(
          store: _FakeProblemCharacterStore(null, const {}, {'F': 0, 'K': 5}),
        ),
      ),
    );
    await tester.pump();

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(1); // selects F only
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isTrue,
    );

    // Moving the slider again recomputes selection from scratch,
    // discarding the manual override.
    slider.onChanged!(1);
    await tester.pump();
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isFalse,
    );
  });
}
