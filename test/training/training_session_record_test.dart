import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/training/training_session_record.dart';

void main() {
  test('toJson/fromJson round-trips every field', () {
    final record = TrainingSessionRecord(
      id: '12345',
      startedAt: DateTime(2026, 8, 21, 14, 30),
      duration: const Duration(minutes: 5, seconds: 30),
      focusSummary: 'K R F',
      wpm: 90,
      recognitionTimeMs: 500,
      extraGapMs: 100,
      notes: 'Had trouble with K and R.',
    );

    final roundTripped = TrainingSessionRecord.fromJson(record.toJson());

    expect(roundTripped.id, record.id);
    expect(roundTripped.startedAt, record.startedAt);
    expect(roundTripped.duration, record.duration);
    expect(roundTripped.focusSummary, record.focusSummary);
    expect(roundTripped.wpm, record.wpm);
    expect(roundTripped.recognitionTimeMs, record.recognitionTimeMs);
    expect(roundTripped.extraGapMs, record.extraGapMs);
    expect(roundTripped.notes, record.notes);
  });

  test('fromJson defaults notes and settings to empty/zero when absent -- '
      'a record saved before those fields existed', () {
    final record = TrainingSessionRecord.fromJson({
      'id': '1',
      'startedAt': DateTime(2026, 8, 21).toIso8601String(),
      'durationMs': 1000,
      'focusSummary': 'A-Z',
    });

    expect(record.notes, '');
    expect(record.wpm, 0);
    expect(record.recognitionTimeMs, 0);
    expect(record.extraGapMs, 0);
  });

  test('copyWith replaces only notes', () {
    final record = TrainingSessionRecord(
      id: '1',
      startedAt: DateTime(2026, 8, 21),
      duration: const Duration(minutes: 1),
      focusSummary: 'A-Z',
      wpm: 90,
      recognitionTimeMs: 500,
      extraGapMs: 100,
      notes: 'original',
    );

    final updated = record.copyWith(notes: 'updated');

    expect(updated.notes, 'updated');
    expect(updated.id, record.id);
    expect(updated.startedAt, record.startedAt);
    expect(updated.duration, record.duration);
    expect(updated.focusSummary, record.focusSummary);
    expect(updated.wpm, record.wpm);
    expect(updated.recognitionTimeMs, record.recognitionTimeMs);
    expect(updated.extraGapMs, record.extraGapMs);
  });
}
