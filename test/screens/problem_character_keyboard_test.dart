import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/problem_character_keyboard.dart';
import 'package:morse_icr/training/problem_character_store.dart';

class _FakeProblemCharacterStore implements ProblemCharacterStore {
  _FakeProblemCharacterStore([this.saved]);

  List<String>? saved;

  @override
  Future<List<String>?> load() async => saved;

  @override
  Future<void> save(List<String> characters) async {
    saved = characters;
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

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
}
