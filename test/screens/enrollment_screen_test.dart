import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/enrollment_screen.dart';
import 'package:morse_icr/speech/character_recorder.dart';
import 'package:morse_icr/speech/enrollment_store.dart';
import 'package:morse_icr/speech/response_listener.dart';

/// Lets Test-mode tests trigger a "recognized" callback directly, the
/// same fake-listener pattern `training_screen_test.dart` uses, without
/// touching a real microphone.
class _FakeResponseListener implements ResponseListener {
  final List<String> stopListeningCalls = [];
  ResponseCallback? onRecognized;

  @override
  Future<void> startListening(ResponseCallback onRecognized) async {
    this.onRecognized = onRecognized;
  }

  @override
  Future<void> restart() async {}

  @override
  Future<void> stopListening() async {
    onRecognized = null;
    stopListeningCalls.add('stop');
  }
}

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

  testWidgets('the Audition toggle changes what tapping a character chip does, '
      "rather than a small per-chip button that's easy to mis-tap", (
    tester,
  ) async {
    final store = _FakeEnrollmentStore({'K'});
    final played = <String>[];
    var enrollCalls = 0;
    Future<void> recordingPlayTakes(
      List<Uint8List> pcm16Takes, {
      void Function(int takeNumber)? onTakePlaying,
    }) async {
      played.add('played');
    }

    Future<List<Uint8List>> countingRecordTakes(
      int count, {
      void Function(int takeNumber)? onTakeRecorded,
    }) async {
      enrollCalls++;
      return fakeRecordTakes(count, onTakeRecorded: onTakeRecorded);
    }

    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: store,
          recordTakes: countingRecordTakes,
          playTakes: recordingPlayTakes,
        ),
      ),
    );
    await tester.pump();

    // Off by default -- tapping 'K' still (re-)enrolls it, unchanged
    // from before this control existed.
    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();
    expect(enrollCalls, 1);
    expect(played, isEmpty);

    // Once toggled on, the same tap plays it back instead.
    await tester.tap(find.widgetWithText(FilterChip, 'Audition'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();
    expect(played, ['played']);
    expect(enrollCalls, 1);
  });

  testWidgets(
    'in Audition mode, an unenrolled character does nothing when tapped -- '
    'nothing has been saved for it to play back',
    (tester) async {
      final store = _FakeEnrollmentStore();
      var played = false;
      Future<void> recordingPlayTakes(
        List<Uint8List> pcm16Takes, {
        void Function(int takeNumber)? onTakePlaying,
      }) async {
        played = true;
      }

      await tester.pumpWidget(
        wrap(
          EnrollmentScreen(
            store: store,
            recordTakes: fakeRecordTakes,
            playTakes: recordingPlayTakes,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'Audition'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilterChip, 'A'));
      await tester.pump();
      await tester.pump();

      expect(played, isFalse);
    },
  );

  testWidgets("tapping an enrolled character in Audition mode plays back every "
      'saved take, in order, without re-recording it', (tester) async {
    final store = _FakeEnrollmentStore()
      ..recordings['K'] = [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
        Uint8List.fromList([3]),
      ];
    final played = <List<Uint8List>>[];
    Future<void> recordingPlayTakes(
      List<Uint8List> pcm16Takes, {
      void Function(int takeNumber)? onTakePlaying,
    }) async {
      played.add(pcm16Takes);
      for (var i = 1; i <= pcm16Takes.length; i++) {
        onTakePlaying?.call(i);
      }
    }

    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: store,
          recordTakes: fakeRecordTakes,
          playTakes: recordingPlayTakes,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'Audition'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();

    expect(played, [store.recordings['K']]);
    // Never re-recorded -- the store's original takes are untouched.
    expect(store.recordings['K'], [
      Uint8List.fromList([1]),
      Uint8List.fromList([2]),
      Uint8List.fromList([3]),
    ]);
  });

  testWidgets('shows which take is currently playing while auditioning', (
    tester,
  ) async {
    final store = _FakeEnrollmentStore()
      ..recordings['K'] = [Uint8List(0), Uint8List(0), Uint8List(0)];
    final unblock = Completer<void>();
    Future<void> blockingPlayTakes(
      List<Uint8List> pcm16Takes, {
      void Function(int takeNumber)? onTakePlaying,
    }) async {
      onTakePlaying?.call(2);
      await unblock.future;
    }

    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: store,
          recordTakes: fakeRecordTakes,
          playTakes: blockingPlayTakes,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'Audition'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Playing K, take 2 of 3...'), findsOneWidget);

    unblock.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('Playing K, take 2 of 3...'), findsNothing);
  });

  testWidgets('turning Test mode on starts listening, and each recognized '
      'character outlines its chip', (tester) async {
    final listener = _FakeResponseListener();
    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: _FakeEnrollmentStore({'K', 'F'}),
          recordTakes: fakeRecordTakes,
          responseListener: listener,
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).side,
      isNull,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'Test'));
    await tester.pump();

    expect(listener.onRecognized, isNotNull);
    listener.onRecognized!('K');
    await tester.pump();

    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).side,
      isNotNull,
    );
    // Not recognized -- no outline.
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'F')).side,
      isNull,
    );
  });

  testWidgets('a second recognized character outlines its chip too, without '
      'removing the outline from the first', (tester) async {
    final listener = _FakeResponseListener();
    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: _FakeEnrollmentStore({'K', 'F'}),
          recordTakes: fakeRecordTakes,
          responseListener: listener,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'Test'));
    await tester.pump();

    listener.onRecognized!('K');
    await tester.pump();
    listener.onRecognized!('F');
    await tester.pump();

    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).side,
      isNotNull,
    );
    expect(
      tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'F')).side,
      isNotNull,
    );
  });

  testWidgets(
    'turning Test mode off stops listening and clears every outline',
    (tester) async {
      final listener = _FakeResponseListener();
      await tester.pumpWidget(
        wrap(
          EnrollmentScreen(
            store: _FakeEnrollmentStore({'K'}),
            recordTakes: fakeRecordTakes,
            responseListener: listener,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'Test'));
      await tester.pump();
      listener.onRecognized!('K');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilterChip, 'Test'));
      await tester.pump();

      expect(listener.stopListeningCalls, ['stop']);
      expect(
        tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'K')).side,
        isNull,
      );
      // The chip's enrolled/selected state is untouched by Test mode.
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'K'))
            .selected,
        isTrue,
      );
    },
  );

  testWidgets('Test mode disables tapping the character grid and the Audition '
      'toggle, and Audition disables the Test toggle', (tester) async {
    final listener = _FakeResponseListener();
    var enrollCalls = 0;
    Future<List<Uint8List>> countingRecordTakes(
      int count, {
      void Function(int takeNumber)? onTakeRecorded,
    }) async {
      enrollCalls++;
      return fakeRecordTakes(count, onTakeRecorded: onTakeRecorded);
    }

    await tester.pumpWidget(
      wrap(
        EnrollmentScreen(
          store: _FakeEnrollmentStore(),
          recordTakes: countingRecordTakes,
          responseListener: listener,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, 'Test'));
    await tester.pump();

    // Grid tap does nothing while Test mode is on.
    await tester.tap(find.widgetWithText(FilterChip, 'K'));
    await tester.pump();
    expect(enrollCalls, 0);

    // Audition can't be turned on while Test mode is on.
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Audition'))
          .onSelected,
      isNull,
    );

    await tester.tap(find.widgetWithText(FilterChip, 'Test'));
    await tester.pump();

    // And the reverse: Test can't be turned on while Audition is on.
    await tester.tap(find.widgetWithText(FilterChip, 'Audition'));
    await tester.pump();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Test'))
          .onSelected,
      isNull,
    );
  });

  testWidgets('leaving the screen while Test mode is on stops listening', (
    tester,
  ) async {
    final listener = _FakeResponseListener();
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EnrollmentScreen(
                  store: _FakeEnrollmentStore(),
                  recordTakes: fakeRecordTakes,
                  responseListener: listener,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, 'Test'));
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(listener.stopListeningCalls, ['stop']);
  });
}
