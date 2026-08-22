import 'dart:math' as math;

/// In-place iterative radix-2 Cooley-Tukey FFT, computed directly rather
/// than via a new pub dependency -- a self-contained, well-known
/// algorithm, and `mfcc.dart`'s whole point (morse_icr_spec.md section
/// 38) is avoiding a heavier ML/DSP dependency for character matching.
///
/// [real] and [imag] must have the same power-of-two length; both are
/// overwritten in place with the transform's real and imaginary parts.
void fft(List<double> real, List<double> imag) {
  final n = real.length;
  assert(imag.length == n);
  assert(n > 0 && (n & (n - 1)) == 0, 'FFT size must be a power of two');
  if (n <= 1) return;

  // Bit-reversal permutation, so the butterfly stages below can work
  // in place.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tempReal = real[i];
      real[i] = real[j];
      real[j] = tempReal;
      final tempImag = imag[i];
      imag[i] = imag[j];
      imag[j] = tempImag;
    }
  }

  for (var len = 2; len <= n; len <<= 1) {
    final half = len >> 1;
    final angle = -2 * math.pi / len;
    final stepReal = math.cos(angle);
    final stepImag = math.sin(angle);
    for (var i = 0; i < n; i += len) {
      var twiddleReal = 1.0;
      var twiddleImag = 0.0;
      for (var j = 0; j < half; j++) {
        final evenIndex = i + j;
        final oddIndex = evenIndex + half;
        final oddReal =
            real[oddIndex] * twiddleReal - imag[oddIndex] * twiddleImag;
        final oddImag =
            real[oddIndex] * twiddleImag + imag[oddIndex] * twiddleReal;
        final evenReal = real[evenIndex];
        final evenImag = imag[evenIndex];
        real[evenIndex] = evenReal + oddReal;
        imag[evenIndex] = evenImag + oddImag;
        real[oddIndex] = evenReal - oddReal;
        imag[oddIndex] = evenImag - oddImag;
        final nextTwiddleReal = twiddleReal * stepReal - twiddleImag * stepImag;
        final nextTwiddleImag = twiddleReal * stepImag + twiddleImag * stepReal;
        twiddleReal = nextTwiddleReal;
        twiddleImag = nextTwiddleImag;
      }
    }
  }
}
