import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/training/training_log_formatting.dart';
import 'package:morse_icr/training/training_session_record.dart';

void main() {
  group('formatSessionDate', () {
    test('pads month, day, and 2-digit year', () {
      expect(formatSessionDate(DateTime(2026, 3, 5)), '03/05/26');
    });
  });

  group('formatSessionTime', () {
    test('formats morning times as AM', () {
      expect(formatSessionTime(DateTime(2026, 1, 1, 9, 5)), '09:05 AM');
    });

    test('formats midnight as 12:00 AM', () {
      expect(formatSessionTime(DateTime(2026, 1, 1, 0, 0)), '12:00 AM');
    });

    test('formats noon as 12:00 PM', () {
      expect(formatSessionTime(DateTime(2026, 1, 1, 12, 0)), '12:00 PM');
    });

    test('formats afternoon times as PM', () {
      expect(formatSessionTime(DateTime(2026, 1, 1, 14, 45)), '02:45 PM');
    });
  });

  group('formatSessionDuration', () {
    test('formats sub-hour durations', () {
      expect(formatSessionDuration(const Duration(minutes: 5)), '00:05:00');
    });

    test('formats durations past an hour', () {
      expect(
        formatSessionDuration(const Duration(hours: 1, minutes: 23)),
        '01:23:00',
      );
    });

    test('includes seconds precision', () {
      expect(
        formatSessionDuration(const Duration(minutes: 5, seconds: 30)),
        '00:05:30',
      );
    });
  });

  group('buildTrainingLogCsv', () {
    test('produces a header row when there are no records', () {
      expect(
        buildTrainingLogCsv([]),
        'Date,Time,Duration,Focus,WPM,Recognition (ms),Gap (ms),Notes\n',
      );
    });

    test('formats one record per row', () {
      final csv = buildTrainingLogCsv([
        TrainingSessionRecord(
          id: '1',
          startedAt: DateTime(2026, 3, 5, 9, 0),
          duration: const Duration(minutes: 5),
          focusSummary: 'A-Z',
          wpm: 90,
          recognitionTimeMs: 500,
          extraGapMs: 100,
          notes: 'went well',
        ),
      ]);

      expect(
        csv,
        'Date,Time,Duration,Focus,WPM,Recognition (ms),Gap (ms),Notes\n'
        '03/05/26,09:00 AM,00:05:00,A-Z,90,500,100,went well\n',
      );
    });

    test('quotes and escapes notes containing commas, quotes, or newlines', () {
      final csv = buildTrainingLogCsv([
        TrainingSessionRecord(
          id: '1',
          startedAt: DateTime(2026, 3, 5, 9, 0),
          duration: const Duration(minutes: 5),
          focusSummary: 'A-Z',
          wpm: 90,
          recognitionTimeMs: 500,
          extraGapMs: 100,
          notes: 'K, R "hard" today\nretry tomorrow',
        ),
      ]);

      expect(
        csv,
        'Date,Time,Duration,Focus,WPM,Recognition (ms),Gap (ms),Notes\n'
        '03/05/26,09:00 AM,00:05:00,A-Z,90,500,100,'
        '"K, R ""hard"" today\nretry tomorrow"\n',
      );
    });
  });
}
