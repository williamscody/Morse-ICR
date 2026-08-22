import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/fft.dart';

void main() {
  group('fft', () {
    test('impulse transforms to a flat spectrum', () {
      final real = <double>[1.0, 0, 0, 0, 0, 0, 0, 0];
      final imag = List<double>.filled(8, 0);

      fft(real, imag);

      for (var i = 0; i < 8; i++) {
        expect(real[i], closeTo(1.0, 1e-9));
        expect(imag[i], closeTo(0.0, 1e-9));
      }
    });

    test('DC signal concentrates all energy in bin 0', () {
      final real = List<double>.filled(8, 1.0);
      final imag = List<double>.filled(8, 0);

      fft(real, imag);

      expect(real[0], closeTo(8.0, 1e-9));
      expect(imag[0], closeTo(0.0, 1e-9));
      for (var i = 1; i < 8; i++) {
        expect(real[i], closeTo(0.0, 1e-9));
        expect(imag[i], closeTo(0.0, 1e-9));
      }
    });

    test('a pure sinusoid peaks at its own frequency bin', () {
      const n = 8;
      const cyclesOverWindow = 2; // -> bin 2 (and its mirror, bin 6)
      final real = [
        for (var i = 0; i < n; i++)
          math.cos(2 * math.pi * cyclesOverWindow * i / n),
      ];
      final imag = List<double>.filled(n, 0);

      fft(real, imag);

      final magnitude = [
        for (var i = 0; i < n; i++)
          math.sqrt(real[i] * real[i] + imag[i] * imag[i]),
      ];

      for (var i = 0; i < n; i++) {
        if (i == cyclesOverWindow || i == n - cyclesOverWindow) {
          expect(magnitude[i], greaterThan(3.0));
        } else {
          expect(magnitude[i], closeTo(0.0, 1e-9));
        }
      }
    });
  });
}
