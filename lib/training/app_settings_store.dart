import 'app_settings.dart';

/// Persists [AppSettings] (morse_icr_spec.md section 35) across app
/// launches (section 23), the same interface+fake pattern the project's
/// other stores already use.
abstract class AppSettingsStore {
  /// The persisted settings, or all-default values if nothing has ever
  /// been saved.
  Future<AppSettings> load();

  /// Persists [settings], overwriting whatever was saved before.
  Future<void> save(AppSettings settings);
}
