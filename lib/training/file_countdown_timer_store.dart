import 'dart:io' show File;

import 'package:path_provider/path_provider.dart';

import 'countdown_timer_config.dart';
import 'countdown_timer_store.dart';

/// Persists [CountdownTimerConfig] as a single ';'-separated text file in
/// the app's documents directory -- "selectedSlot;slot0;slot1;slot2",
/// each field empty when null -- the same [path_provider]-backed approach
/// [FileProblemCharacterStore] already uses, so this needs no new
/// dependency beyond what's already in the project (morse_icr_spec.md
/// section 32).
class FileCountdownTimerStore implements CountdownTimerStore {
  static const _fileName = 'countdown_timer.txt';

  @override
  Future<CountdownTimerConfig> load() async {
    final file = await _file();
    if (!await file.exists()) return const CountdownTimerConfig();
    final parts = (await file.readAsString()).split(';');
    if (parts.length != 4) return const CountdownTimerConfig();
    int? parse(String s) => s.isEmpty ? null : int.tryParse(s);
    return CountdownTimerConfig(
      selectedSlot: parse(parts[0]),
      slotSeconds: [parse(parts[1]), parse(parts[2]), parse(parts[3])],
    );
  }

  @override
  Future<void> save(CountdownTimerConfig config) async {
    final file = await _file();
    final fields = [
      config.selectedSlot?.toString() ?? '',
      for (final seconds in config.slotSeconds) seconds?.toString() ?? '',
    ];
    await file.writeAsString(fields.join(';'));
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
