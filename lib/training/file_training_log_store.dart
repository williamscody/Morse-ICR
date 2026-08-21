import 'dart:convert';
import 'dart:io' show File;

import 'package:path_provider/path_provider.dart';

import 'training_log_store.dart';
import 'training_session_record.dart';

/// Persists the training log as a JSON array in the app's documents
/// directory -- the same [path_provider]-backed approach
/// [FileProblemCharacterStore] and [FileCountdownTimerStore] already use
/// (morse_icr_spec.md section 32), but JSON rather than a delimited
/// string: unlike a character set or a duration, a session record
/// includes free-form learner notes that can contain any character,
/// including whatever delimiter a simpler format might otherwise pick.
/// `dart:convert` is part of the Dart SDK, not a new dependency.
class FileTrainingLogStore implements TrainingLogStore {
  static const _fileName = 'training_log.json';

  @override
  Future<List<TrainingSessionRecord>> load() async {
    final file = await _file();
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString()) as List<Object?>;
    return [
      for (final entry in decoded)
        TrainingSessionRecord.fromJson(entry as Map<String, Object?>),
    ];
  }

  @override
  Future<void> save(List<TrainingSessionRecord> records) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode([for (final record in records) record.toJson()]),
    );
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
