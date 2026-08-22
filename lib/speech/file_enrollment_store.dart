import 'dart:io' show Directory, File;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'enrollment_store.dart';
import 'spoken_character.dart';

/// Persists each character's reference takes as raw-PCM16 files in its
/// own subdirectory of the app documents directory (morse_icr_spec.md
/// section 38) -- the same [path_provider]-backed approach
/// `FileProblemCharacterStore` already uses.
///
/// Characters can't always be used as filenames directly (`/` isn't
/// valid in a filename on any platform this app targets), so filenames
/// reuse [spokenNames] (e.g. `.` -> "dot", `/` -> "slash") rather than
/// inventing a second character-to-string mapping. Each take is its own
/// file, `{name}_{index}.pcm16` (0-based) -- moved from one file per
/// character (Milestone 13, 2026-08-22) alongside [EnrollmentStore]'s
/// interface change to multiple takes. A previous single-take
/// enrollment's `{name}.pcm16` file (no index suffix) is simply
/// orphaned by this change, not migrated -- it's unread by the new
/// `_0`/`_1`/... lookup, and re-enrolling is needed anyway to benefit
/// from multiple takes.
class FileEnrollmentStore implements EnrollmentStore {
  static const _dirName = 'enrollment';

  @override
  Future<Set<String>> enrolledCharacters() async {
    final directory = await _directory();
    if (!await directory.exists()) return {};
    final result = <String>{};
    for (final character in spokenNames.keys) {
      if (await (await _file(character, 0)).exists()) result.add(character);
    }
    return result;
  }

  @override
  Future<void> saveRecordings(
    String character,
    List<Uint8List> pcm16Takes,
  ) async {
    final directory = await _directory();
    if (!await directory.exists()) await directory.create(recursive: true);
    // Clears any previously-saved takes first, so re-enrolling with
    // fewer takes than before (e.g. after _takesPerCharacter changes)
    // never leaves a stale extra file behind for [loadRecordings]'s
    // scan-until-missing to pick up.
    for (var index = 0; ; index++) {
      final file = await _file(character, index);
      if (!await file.exists()) break;
      await file.delete();
    }
    for (var index = 0; index < pcm16Takes.length; index++) {
      await (await _file(character, index)).writeAsBytes(pcm16Takes[index]);
    }
  }

  @override
  Future<List<Uint8List>> loadRecordings(String character) async {
    final takes = <Uint8List>[];
    for (var index = 0; ; index++) {
      final file = await _file(character, index);
      if (!await file.exists()) break;
      takes.add(await file.readAsBytes());
    }
    return takes;
  }

  Future<Directory> _directory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory('${documents.path}/$_dirName');
  }

  Future<File> _file(String character, int index) async {
    final directory = await _directory();
    final name = spokenNames[character.toUpperCase()] ?? character;
    return File('${directory.path}/${name}_$index.pcm16');
  }
}
