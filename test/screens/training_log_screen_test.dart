import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/screens/training_log_screen.dart';
import 'package:morse_icr/training/training_log_store.dart';
import 'package:morse_icr/training/training_session_record.dart';

class _FakeTrainingLogStore implements TrainingLogStore {
  _FakeTrainingLogStore([this.saved = const []]);

  List<TrainingSessionRecord> saved;

  @override
  Future<List<TrainingSessionRecord>> load() async => saved;

  @override
  Future<void> save(List<TrainingSessionRecord> records) async {
    saved = records;
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  final earlier = TrainingSessionRecord(
    id: 'earlier',
    startedAt: DateTime(2026, 8, 20, 9, 0),
    duration: const Duration(minutes: 5),
    focusSummary: 'A-Z',
    wpm: 90,
    recognitionTimeMs: 500,
    extraGapMs: 0,
    notes: 'first session',
  );
  final later = TrainingSessionRecord(
    id: 'later',
    startedAt: DateTime(2026, 8, 21, 10, 30),
    duration: const Duration(minutes: 3),
    focusSummary: 'K R F',
    wpm: 100,
    recognitionTimeMs: 250,
    extraGapMs: 50,
  );

  testWidgets('shows an empty-state message and zero total time when '
      'nothing has been recorded', (tester) async {
    await tester.pumpWidget(
      wrap(TrainingLogScreen(store: _FakeTrainingLogStore())),
    );
    await tester.pump();

    expect(find.text('No training sessions recorded yet.'), findsOneWidget);
    expect(find.text('Total Time: 00:00'), findsOneWidget);
  });

  testWidgets('shows the sum of every recorded session\'s duration as the '
      'total, not a separately-tracked counter', (tester) async {
    await tester.pumpWidget(
      wrap(
        TrainingLogScreen(
          store: _FakeTrainingLogStore([earlier, later]),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Total Time: 00:08'), findsOneWidget);
  });

  testWidgets('shows each session\'s date, time, duration, and focus in one '
      'row, newest first', (tester) async {
    await tester.pumpWidget(
      wrap(
        TrainingLogScreen(
          store: _FakeTrainingLogStore([earlier, later]),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('08/21/26'), findsOneWidget);
    expect(find.text('10:30 AM'), findsOneWidget);
    expect(find.text('00:03'), findsOneWidget);
    expect(find.text('K R F'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('250 ms'), findsOneWidget);
    expect(find.text('50 ms'), findsOneWidget);

    // Newest (later) first: its date should sit above earlier's.
    expect(
      tester.getTopLeft(find.text('08/21/26')).dy <
          tester.getTopLeft(find.text('08/20/26')).dy,
      isTrue,
    );
  });

  testWidgets('pre-fills each row\'s notes field with its saved notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(TrainingLogScreen(store: _FakeTrainingLogStore([earlier]))),
    );
    await tester.pump();

    expect(find.text('first session'), findsOneWidget);
  });

  testWidgets('submitting a note (keyboard Done) persists it to the store', (
    tester,
  ) async {
    final store = _FakeTrainingLogStore([later]);
    await tester.pumpWidget(wrap(TrainingLogScreen(store: store)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'good progress');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(store.saved.single.notes, 'good progress');
  });

  testWidgets('losing focus without submitting also persists the note', (
    tester,
  ) async {
    final store = _FakeTrainingLogStore([later]);
    await tester.pumpWidget(wrap(TrainingLogScreen(store: store)));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'good progress');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(store.saved.single.notes, 'good progress');
  });

  testWidgets('Clear does nothing until confirmed in the dialog', (
    tester,
  ) async {
    final store = _FakeTrainingLogStore([earlier]);
    await tester.pumpWidget(wrap(TrainingLogScreen(store: store)));
    await tester.pump();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear training log?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('08/20/26'), findsOneWidget);
    expect(store.saved, [earlier]);
  });

  testWidgets('Clear, once confirmed, empties the log and persists that', (
    tester,
  ) async {
    final store = _FakeTrainingLogStore([earlier, later]);
    await tester.pumpWidget(wrap(TrainingLogScreen(store: store)));
    await tester.pump();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Clear').last);
    await tester.pumpAndSettle();

    expect(find.text('No training sessions recorded yet.'), findsOneWidget);
    expect(store.saved, isEmpty);
  });

  testWidgets('Clear and Export are disabled when the log is empty', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(TrainingLogScreen(store: _FakeTrainingLogStore())),
    );
    await tester.pump();

    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Clear')).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byIcon(Icons.ios_share),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Export hands the built CSV to the injected export function', (
    tester,
  ) async {
    String? exportedCsv;
    await tester.pumpWidget(
      wrap(
        TrainingLogScreen(
          store: _FakeTrainingLogStore([earlier]),
          exportCsv: (csv, origin) async {
            exportedCsv = csv;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.ios_share));
    await tester.pump();

    expect(
      exportedCsv,
      contains('Date,Time,Duration,Focus,WPM,Recognition (ms),Gap (ms),Notes'),
    );
    expect(
      exportedCsv,
      contains('08/20/26,09:00 AM,00:05,A-Z,90,500,0,first session'),
    );
  });
}
