import 'package:flutter/foundation.dart';

/// Temporary diagnostic logging for hard on-device bugs -- `--release`
/// builds on this project's test device have no readable console
/// output (see project memory: no Dart VM service in AOT release
/// builds, and no working device-console tooling either), so
/// [entries] backs an on-screen copyable log instead of relying on
/// [debugPrint] alone. Remove once whatever's being investigated is
/// confirmed fixed on-device.
final ValueNotifier<List<String>> debugLogEntries = ValueNotifier([]);

void logDebug(String message) {
  final now = DateTime.now();
  final timestamp =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}.'
      '${now.millisecond.toString().padLeft(3, '0')}';
  final line = '$timestamp $message';
  debugPrint('[morse_icr] $line');
  debugLogEntries.value = [...debugLogEntries.value, line];
}
