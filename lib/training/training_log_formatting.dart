import 'training_session_record.dart';

/// "MM/DD/YY", matching [TrainingLogScreen]'s sketch.
String formatSessionDate(DateTime dateTime) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dateTime.month)}/${two(dateTime.day)}/'
      '${two(dateTime.year % 100)}';
}

/// "HH:MM AM/PM" in 12-hour form, matching [TrainingLogScreen]'s sketch.
String formatSessionTime(DateTime dateTime) {
  final hour24 = dateTime.hour;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final period = hour24 < 12 ? 'AM' : 'PM';
  return '${hour12.toString().padLeft(2, '0')}:'
      '${dateTime.minute.toString().padLeft(2, '0')} $period';
}

/// "HH:MM" -- hours and minutes, not [formatCountdown]'s minutes/seconds:
/// a training session is measured in minutes at the shortest, and can run
/// well past an hour, matching [TrainingLogScreen]'s sketch.
String formatSessionDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

/// Builds the training log's CSV export (morse_icr_spec.md section 21),
/// oldest session first regardless of [TrainingLogScreen]'s newest-first
/// display order -- chronological order is the conventional expectation
/// for a spreadsheet export. Hand-rolled RFC 4180 quoting rather than a
/// `csv` package dependency: the only field that can contain a comma,
/// quote, or newline is free-form notes, and escaping that is a few
/// lines (morse_icr_spec.md section 32: avoid unnecessary dependencies).
String buildTrainingLogCsv(List<TrainingSessionRecord> records) {
  String escape(String field) {
    if (!field.contains(',') && !field.contains('"') && !field.contains('\n')) {
      return field;
    }
    return '"${field.replaceAll('"', '""')}"';
  }

  final buffer = StringBuffer()..writeln(
    'Date,Time,Duration,Focus,WPM,Recognition (ms),Gap (ms),Notes',
  );
  for (final record in records) {
    buffer.writeln(
      [
        formatSessionDate(record.startedAt),
        formatSessionTime(record.startedAt),
        formatSessionDuration(record.duration),
        escape(record.focusSummary),
        record.wpm.toString(),
        record.recognitionTimeMs.toString(),
        record.extraGapMs.toString(),
        escape(record.notes),
      ].join(','),
    );
  }
  return buffer.toString();
}
