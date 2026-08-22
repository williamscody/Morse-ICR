import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/enrollment_screen.dart';
import 'package:morse_icr/speech/enrollment_store.dart';

class _FakeEnrollmentStore implements EnrollmentStore {
  _FakeEnrollmentStore([Set<String>? enrolled])
    : recordings = {
        for (final character in enrolled ?? {}) character: Uint8List(0),
      };

  final Map<String, Uint8List> recordings;

  @override
  Future<Set<String>> enrolledCharacters() async => recordings.keys.toSet();

  @override
  Future<void> saveRecording(String character, Uint8List pcm16) async {
    recordings[character] = pcm16;
  }

  @override
  Future<Uint8List?> loadRecording(String character) async =>
      recordings[character];
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  Future<Uint8List> fakeRecordClip() async => Uint8List.fromList([1, 2, 3]);

  testWidgets('shows every letter, digit, and the minimum punctuation set, '
      'none selected, when nothing was previously enrolled', (tester) async {
    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: _FakeEnrollmentStore(),
          recordClip: fakeRecordClip,
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
          recordClip: fakeRecordClip,
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

  testWidgets('tapping a character records and persists a clip for it', (
    tester,
  ) async {
    final store = _FakeEnrollmentStore();
    await tester.pumpWidget(
      wrap(EnrollmentScreen(store: store, recordClip: fakeRecordClip)),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();

    expect(store.recordings.containsKey('K'), isTrue);
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).selected,
      isTrue,
    );
  });

  testWidgets('re-tapping an already-enrolled character re-records it', (
    tester,
  ) async {
    final store = _FakeEnrollmentStore({'K'});
    var calls = 0;
    Future<Uint8List> countingRecordClip() async {
      calls++;
      return Uint8List.fromList([calls]);
    }

    await tester.pumpWidget(
      wrap(EnrollmentScreen(store: store, recordClip: countingRecordClip)),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();

    expect(calls, 1);
    expect(store.recordings['K'], Uint8List.fromList([1]));
  });
}
