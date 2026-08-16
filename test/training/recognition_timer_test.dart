import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/training/recognition_timer.dart';

void main() {
  group('RecognitionTimer', () {
    test('is not running before start is called', () {
      final timer = RecognitionTimer();
      expect(timer.isRunning, isFalse);
    });

    test('reports running once started', () {
      final timer = RecognitionTimer();
      timer.start(const Duration(milliseconds: 50), () {});
      expect(timer.isRunning, isTrue);
      timer.cancel();
    });

    test('does not fire onExpired before the duration elapses', () async {
      final timer = RecognitionTimer();
      var expired = false;
      timer.start(const Duration(milliseconds: 100), () => expired = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(expired, isFalse);
      timer.cancel();
    });

    test('fires onExpired after the duration elapses', () async {
      final timer = RecognitionTimer();
      var expired = false;
      timer.start(const Duration(milliseconds: 20), () => expired = true);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(expired, isTrue);
      expect(timer.isRunning, isFalse);
    });

    test('cancel before expiry prevents onExpired from firing', () async {
      final timer = RecognitionTimer();
      var expired = false;
      timer.start(const Duration(milliseconds: 20), () => expired = true);

      timer.cancel();
      expect(timer.isRunning, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(expired, isFalse);
    });

    test('cancel is a no-op when not running', () {
      final timer = RecognitionTimer();
      expect(() => timer.cancel(), returnsNormally);
    });

    test('starting again cancels the previous countdown', () async {
      final timer = RecognitionTimer();
      var firstExpired = false;
      var secondExpired = false;

      timer.start(const Duration(milliseconds: 20), () => firstExpired = true);
      timer.start(const Duration(milliseconds: 20), () => secondExpired = true);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(firstExpired, isFalse);
      expect(secondExpired, isTrue);
    });
  });
}
