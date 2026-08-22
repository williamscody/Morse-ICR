import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

const int _frameLength = 400; // 25ms at 16kHz
const int _hopLength = 160; // 10ms at 16kHz
const int _fftSize = 512; // next power of two >= _frameLength
const int _melFilterCount = 26;
const int _coefficientCount = 13;

/// Extracts MFCC (mel-frequency cepstral coefficient) features from a
/// raw PCM16 mono clip (morse_icr_spec.md section 38's "dynamic time
/// warping over MFCC/mel-spectrogram features" approach), one 13-value
/// coefficient vector per ~25ms analysis frame.
///
/// Deliberately simple -- no deltas, no pre-emphasis tuning beyond the
/// standard framing/windowing -- since section 38 flags matching as
/// needing on-device investigation rather than a finished design.
/// [sampleRate] defaults to 16000Hz to match the capture rate
/// established in Milestone 13 step 1's on-device mic spike.
List<List<double>> extractMfcc(Uint8List pcm16, {int sampleRate = 16000}) {
  final samples = _decodePcm16(pcm16);
  if (samples.length < _frameLength) return [];

  final filterbank = _melFilterbank(sampleRate);
  final window = _hammingWindow(_frameLength);
  final frameCount = 1 + (samples.length - _frameLength) ~/ _hopLength;

  return [
    for (var frame = 0; frame < frameCount; frame++)
      _mfccForFrame(samples, frame * _hopLength, window, filterbank),
  ];
}

List<double> _decodePcm16(Uint8List bytes) {
  final byteData = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  return [
    for (var i = 0; i < sampleCount; i++)
      byteData.getInt16(i * 2, Endian.little) / 32768.0,
  ];
}

List<double> _hammingWindow(int length) => [
  for (var n = 0; n < length; n++)
    0.54 - 0.46 * math.cos(2 * math.pi * n / (length - 1)),
];

List<double> _mfccForFrame(
  List<double> samples,
  int start,
  List<double> window,
  List<List<double>> filterbank,
) {
  final real = List<double>.filled(_fftSize, 0);
  final imag = List<double>.filled(_fftSize, 0);
  for (var i = 0; i < _frameLength; i++) {
    real[i] = samples[start + i] * window[i];
  }
  fft(real, imag);

  final magnitude = [
    for (var k = 0; k <= _fftSize ~/ 2; k++)
      math.sqrt(real[k] * real[k] + imag[k] * imag[k]),
  ];

  final logMelEnergies = [
    for (final filter in filterbank)
      math.log(math.max(_dot(filter, magnitude), 1e-10)),
  ];

  return _dct(logMelEnergies, _coefficientCount);
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

/// DCT-II of [input], keeping the first [coefficientCount] coefficients
/// -- the standard log-mel-energy -> cepstral-coefficient step.
List<double> _dct(List<double> input, int coefficientCount) {
  final n = input.length;
  return [
    for (var k = 0; k < coefficientCount; k++)
      _dot(input, [
        for (var m = 0; m < n; m++) math.cos(math.pi / n * (m + 0.5) * k),
      ]),
  ];
}

/// A bank of [_melFilterCount] overlapping triangular filters spanning
/// 0Hz to the Nyquist frequency, evenly spaced on the mel scale --
/// standard MFCC front-end, giving the frequency resolution that
/// roughly matches human pitch perception.
List<List<double>> _melFilterbank(int sampleRate) {
  final binCount = _fftSize ~/ 2 + 1;
  final nyquist = sampleRate / 2;
  final melLow = _hzToMel(0);
  final melHigh = _hzToMel(nyquist);

  final melPoints = [
    for (var i = 0; i < _melFilterCount + 2; i++)
      melLow + (melHigh - melLow) * i / (_melFilterCount + 1),
  ];
  final fftBins = [
    for (final mel in melPoints)
      (_melToHz(mel) / nyquist * (binCount - 1)).round(),
  ];

  return [
    for (var m = 1; m <= _melFilterCount; m++)
      [
        for (var k = 0; k < binCount; k++)
          _triangle(k, fftBins[m - 1], fftBins[m], fftBins[m + 1]),
      ],
  ];
}

double _triangle(int x, int left, int center, int right) {
  if (x <= left || x >= right) return 0;
  if (x <= center) {
    return center == left ? 0 : (x - left) / (center - left);
  }
  return center == right ? 0 : (right - x) / (right - center);
}

double _hzToMel(double hz) => 2595 * math.log(1 + hz / 700) / math.ln10;

double _melToHz(double mel) => 700 * (math.exp(mel / 2595 * math.ln10) - 1);
