import 'dart:io' show File;

import 'package:path_provider/path_provider.dart';

import 'problem_character_store.dart';

/// Persists the problem-character set as a single space-separated text
/// file in the app's documents directory (morse_icr_spec.md section 11
/// example format: "K R F L Y Q") -- the same [path_provider]-backed
/// approach [TtsAnswerSpeaker] already uses for its cached audio files,
/// so this needs no new dependency beyond what's already in the project
/// (morse_icr_spec.md section 32).
class FileProblemCharacterStore implements ProblemCharacterStore {
  static const _fileName = 'problem_characters.txt';

  @override
  Future<List<String>?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final characters = (await file.readAsString())
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    return characters.isEmpty ? null : characters;
  }

  @override
  Future<void> save(List<String> characters) async {
    final file = await _file();
    await file.writeAsString(characters.join(' '));
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
