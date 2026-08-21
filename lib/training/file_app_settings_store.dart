import 'dart:convert';
import 'dart:io' show File;

import 'package:path_provider/path_provider.dart';

import 'app_settings.dart';
import 'app_settings_store.dart';

/// Persists [AppSettings] as a JSON object in the app's documents
/// directory -- the same [path_provider]-backed approach the project's
/// other file stores use (morse_icr_spec.md section 32).
class FileAppSettingsStore implements AppSettingsStore {
  static const _fileName = 'app_settings.json';

  @override
  Future<AppSettings> load() async {
    final file = await _file();
    if (!await file.exists()) return const AppSettings();
    final decoded = jsonDecode(await file.readAsString());
    return AppSettings.fromJson(decoded as Map<String, Object?>);
  }

  @override
  Future<void> save(AppSettings settings) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(settings.toJson()));
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }
}
