import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'enrollment_store.dart';
import 'spoken_character.dart';

/// Persists each character's reference recording as a raw-PCM16 file in
/// its own subdirectory of the app documents directory (morse_icr_spec.md
/// section 38) -- the same [path_provider]-backed approach
/// `FileProblemCharacterStore` already uses.
///
/// Characters can't always be used as filenames directly (`/` isn't
/// valid in a filename on any platform this app targets), so filenames
/// reuse [spokenNames] (e.g. `.` -> "dot.pcm16", `/` -> "slash.pcm16")
/// rather than inventing a second character-to-string mapping.
class FileEnrollmentStore implements EnrollmentStore {
  static const _dirName = 'enrollment';

  @override
  Future<Set<String>> enrolledCharacters() async {
    final directory = await _directory();
    if (!await directory.exists()) return {};
    final result = <String>{};
    for (final character in spokenNames.keys) {
      if (await (await _file(character)).exists()) result.add(character);
    }
    return result;
  }

  @override
  Future<void> saveRecording(String character, Uint8List pcm16) async {
    final directory = await _directory();
    if (!await directory.exists()) await directory.create(recursive: true);
    await (await _file(character)).writeAsBytes(pcm16);
  }

  @override
  Future<Uint8List?> loadRecording(String character) async {
    final file = await _file(character);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/$_dirName');
  }

  Future<File> _file(String character) async {
    final directory = await _directory();
    final name = spokenNames[character.toUpperCase()] ?? character;
    return File('${directory.path}/$name.pcm16');
  }
}
