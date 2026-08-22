import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/enrollment_screen.dart';
import 'package:morse_icr/speech/character_recorder.dart';
import 'package:morse_icr/speech/enrollment_store.dart';

class _FakeEnrollmentStore implements EnrollmentStore {
  _FakeEnrollmentStore([Set<String>? enrolled])
    : recordings = {
        for (final character in enrolled ?? {}) character: [Uint8List(0)],
      };

  final Map<String, List<Uint8List>> recordings;

  @override
  Future<Set<String>> enrolledCharacters() async => recordings.keys.toSet();

  @override
  Future<void> saveRecordings(
    String character,
    List<Uint8List> pcm16Takes,
  ) async {
    recordings[character] = pcm16Takes;
  }

  @override
  Future<List<Uint8List>> loadRecordings(String character) async =>
      recordings[character] ?? [];
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  Future<List<Uint8List>> fakeRecordTakes(
    int count, {
    void Function(int takeNumber)? onTakeRecorded,
  }) async {
    final takes = <Uint8List>[];
    for (var i = 1; i <= count; i++) {
      takes.add(Uint8List.fromList([1, 2, 3]));
      onTakeRecorded?.call(i);
    }
    return takes;
  }

  testWidgets('shows every letter, digit, and the minimum punctuation set, '
      'none selected, when nothing was previously enrolled', (tester) async {
    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: _FakeEnrollmentStore(),
          recordTakes: fakeRecordTakes,
        ),
      ),
    );
    await tester.pump();

    for (final character in ['A', 'Z', '0', '9', '.', ',', '?', '/']) {
      expect(find.widgetWithText(FilterChip, character), findsOneWidget);
    }
    final chips = tester.widgetList<FilterChip>(find.byType(FilterChip));
    expect(chips.every((chip) => !chip.selected), isTrue);
  });

  testWidgets('shows previously-enrolled characters as selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: _FakeEnrollmentStore({'K', 'R', 'F'}),
          recordTakes: fakeRecordTakes,
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

  testWidgets('tapping a character records and persists 3 takes for it', (
    tester,
  ) async {
    final store = _FakeEnrollmentStore();
    await tester.pumpWidget(
      wrap(EnrollmentScreen(store: store, recordTakes: fakeRecordTakes)),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();

    expect(store.recordings['K']?.length, 3);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isTrue,
    );
  });

  testWidgets('re-tapping an already-enrolled character re-records all '
      'takes', (tester) async {
    final store = _FakeEnrollmentStore({'K'});
    var calls = 0;
    Future<List<Uint8List>> countingRecordTakes(
      int count, {
      void Function(int takeNumber)? onTakeRecorded,
    }) async {
      final takes = <Uint8List>[];
      for (var i = 1; i <= count; i++) {
        calls++;
        takes.add(Uint8List.fromList([calls]));
        onTakeRecorded?.call(i);
      }
      return takes;
    }

    await tester.pumpWidget(
      wrap(EnrollmentScreen(store: store, recordTakes: countingRecordTakes)),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();

    expect(calls, 3);
    expect(store.recordings['K'], [
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
      Uint8List.fromList([3]),
    ]);
  });

  testWidgets(
    'a later take failing leaves the character\'s previous enrollment '
    'untouched (all-or-nothing)',
    (tester) async {
      final store = _FakeEnrollmentStore({'K'});
      final previousTakes = store.recordings['K'];
      var calls = 0;
      Future<List<Uint8List>> failOnSecondTake(
        int count, {
        void Function(int takeNumber)? onTakeRecorded,
      }) async {
        final takes = <Uint8List>[];
        for (var i = 1; i <= count; i++) {
          calls++;
          if (calls == 2) throw NoSpeechDetected();
          takes.add(Uint8List.fromList([calls]));
          onTakeRecorded?.call(i);
        }
        return takes;
      }

      await tester.pumpWidget(
        wrap(EnrollmentScreen(store: store, recordTakes: failOnSecondTake)),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      await tester.pump();

      // The 3rd take is never attempted, and the character's previous
      // takes are exactly as they were -- a partial re-recording is
      // never saved over a working enrollment.
      expect(calls, 2);
      expect(store.recordings['K'], previousTakes);
      expect(
        find.text(
          "Didn't catch that -- speak right after tapping, then try again.",
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'shows a message and leaves the character unenrolled when no speech '
    'is detected',
    (tester) async {
      final store = _FakeEnrollmentStore();
      Future<List<Uint8List>> silentRecordTakes(
        int count, {
        void Function(int takeNumber)? onTakeRecorded,
      }) async => throw NoSpeechDetected();

      await tester.pumpWidget(
        wrap(EnrollmentScreen(store: store, recordTakes: silentRecordTakes)),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'K'));
      await tester.pump();
      await tester.pump();

      expect(store.recordings.containsKey('K'), isFalse);
      expect(
        find.text(
          "Didn't catch that -- speak right after tapping, then try again.",
        ),
        findsOneWidget,
      );
    },
  );
}
