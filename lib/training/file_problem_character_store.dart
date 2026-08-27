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
  // Separate file, not folded into the main one -- keeps the existing
  // persisted format and every existing load()/save() call site untouched.
  static const _autoFlaggedFileName = 'problem_characters_auto.txt';
  static const _scoresFileName = 'problem_characters_scores.txt';
  static const _attemptsFileName = 'problem_characters_attempts.txt';

  @override
  Future<List<String>?> load() async {
    final file = await _file(_fileName);
    if (!await file.exists()) return null;
    final characters = (await file.readAsString())
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    return characters.isEmpty ? null : characters;
  }

  @override
  Future<void> save(List<String> characters) async {
    final file = await _file(_fileName);
    await file.writeAsString(characters.join(' '));
  }

  @override
  Future<Set<String>> loadAutoFlagged() async {
    final file = await _file(_autoFlaggedFileName);
    if (!await file.exists()) return {};
    return (await file.readAsString())
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  @override
  Future<void> saveAutoFlagged(Set<String> characters) async {
    final file = await _file(_autoFlaggedFileName);
    await file.writeAsString(characters.join(' '));
  }

  @override
  Future<Map<String, int>> loadScores() => _loadCounts(_scoresFileName);

  @override
  Future<void> saveScores(Map<String, int> scores) =>
      _saveCounts(_scoresFileName, scores);

  @override
  Future<Map<String, int>> loadAttempts() => _loadCounts(_attemptsFileName);

  @override
  Future<void> saveAttempts(Map<String, int> attempts) =>
      _saveCounts(_attemptsFileName, attempts);

  Future<Map<String, int>> _loadCounts(String fileName) async {
    final file = await _file(fileName);
    if (!await file.exists()) return {};
    final counts = <String, int>{};
    for (final entry in (await file.readAsString()).split(' ')) {
      final parts = entry.split(':');
      if (parts.length != 2) continue;
      final count = int.tryParse(parts[1]);
      if (count != null) counts[parts[0]] = count;
    }
    return counts;
  }

  Future<void> _saveCounts(String fileName, Map<String, int> counts) async {
    final file = await _file(fileName);
    await file.writeAsString(
      counts.entries.map((entry) => '${entry.key}:${entry.value}').join(' '),
    );
  }

  Future<File> _file(String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$fileName');
  }
}
