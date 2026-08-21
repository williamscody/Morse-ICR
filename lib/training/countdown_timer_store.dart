import 'countdown_timer_config.dart';

/// Persists the learner's three countdown-timer memory slots and which
/// one is active (morse_icr_spec.md section 9: "remember its configured
/// duration... persist its configured duration across application
/// launches") across app launches.
///
/// Lets [CountdownTimerSettings] and [TrainingScreen] read/write the
/// config without depending on a concrete storage mechanism, so both can
/// be tested without touching the real filesystem (morse_icr project
/// testing convention: plugin-backed classes get an interface and a
/// hand-written fake, no mocking library) -- the same pattern
/// [ProblemCharacterStore] already established.
abstract class CountdownTimerStore {
  /// The persisted config, or an all-unset, no-selection default if
  /// nothing has ever been saved.
  Future<CountdownTimerConfig> load();

  /// Persists [config], overwriting whatever was saved before.
  Future<void> save(CountdownTimerConfig config);
}
