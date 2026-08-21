import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/training/countdown_timer_config.dart';

void main() {
  group('formatCountdown', () {
    test('pads minutes and seconds to two digits', () {
      expect(formatCountdown(Duration.zero), '00:00');
      expect(formatCountdown(const Duration(seconds: 5)), '00:05');
      expect(formatCountdown(const Duration(minutes: 5)), '05:00');
    });

    test('formats minutes past 9 without truncating', () {
      expect(formatCountdown(const Duration(minutes: 12, seconds: 34)), '12:34');
    });

    test('rounds a partial second down', () {
      expect(
        formatCountdown(const Duration(seconds: 59, milliseconds: 900)),
        '00:59',
      );
    });
  });

  group('CountdownTimerConfig.selectedDuration', () {
    test('is null when no memory is selected', () {
      const config = CountdownTimerConfig(slotSeconds: [300, 180, 120]);
      expect(config.selectedDuration, isNull);
    });

    test('is null when the selected memory has never been stored', () {
      const config = CountdownTimerConfig(
        slotSeconds: [null, 180, 120],
        selectedSlot: 0,
      );
      expect(config.selectedDuration, isNull);
    });

    test('is the selected memory\'s stored duration', () {
      const config = CountdownTimerConfig(
        slotSeconds: [300, 180, 120],
        selectedSlot: 1,
      );
      expect(config.selectedDuration, const Duration(seconds: 180));
    });
  });
}
