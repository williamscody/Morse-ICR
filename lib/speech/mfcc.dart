import 'dart:math' as math;
import 'dart:typed_data';

import 'fft.dart';

const int _frameLength = 400; // 25ms at 16kHz
const int _hopLength = 160; // 10ms at 16kHz
const int _fftSize = 512; // next power of two >= _frameLength
const int _melFilterCount = 26;
const int _coefficientCount = 13;
const int _deltaWindow = 2; // frames each side, standard regression delta

/// How many static coefficients lead each feature vector before its
/// delta counterparts -- public so callers that need to distinguish the
/// two (e.g. weighting them separately in a distance calculation) don't
/// have to duplicate this as a magic number.
const int mfccStaticCoefficientCount = _coefficientCount;

/// [extractMfcc]'s return shape -- one feature vector per analysis
/// frame -- named so callers holding several of these (e.g.
/// `VoiceCharacterMatcher`'s multiple enrolled takes per character)
/// don't have to spell out the doubly-nested `List<List<double>>`.
typedef MfccSequence = List<List<double>>;

/// Extracts MFCC (mel-frequency cepstral coefficient) features from a
/// raw PCM16 mono clip (morse_icr_spec.md section 38's "dynamic time
/// warping over MFCC/mel-spectrogram features" approach): one
/// 26-value vector per ~25ms analysis frame -- 13 static coefficients
/// (cepstral-mean-normalized) plus their 13 delta (rate-of-change)
/// counterparts.
///
/// Deltas were added after on-device data (Milestone 13, 2026-08-21)
/// showed the matcher's specific errors were classic confusable
/// consonant pairs (B/V, K/Q, L/R) -- ones that mostly differ in how a
/// sound *transitions*, not its static per-frame shape, which is
/// exactly what a static-only feature vector misses. Still simple --
/// no delta-delta, no pre-emphasis tuning -- since section 38 flags
/// matching as needing on-device investigation rather than a finished
/// design. [sampleRate] defaults to 16000Hz to match the capture rate
/// established in Milestone 13 step 1's on-device mic spike.
///
/// [_coefficientCount] was tried at 20 (Milestone 13, 2026-08-22) to
/// capture finer spectral detail for confusable pairs (M/N, I/Y, P/Q)
/// still surviving CMN plus magnitude-weighted deltas, then reverted:
/// on-device accuracy got *worse* (1/9 vs. 2/8 at 13), with static
/// coefficient magnitudes visibly smaller across the board (~4.2-4.7
/// vs. ~6-7) -- the higher-order coefficients carry little energy and
/// are more sensitive to take-to-take recording variation (mic
/// distance, background noise) than to phonetic content, which single-
/// take enrollment can't average out. More coefficients only helps once
/// references are robust to that variation -- multi-take enrollment
/// (Milestone 13, 2026-08-22: `EnrollmentStore.saveRecordings`) is that
/// fix, adding them first just added noise.
MfccSequence extractMfcc(Uint8List pcm16, {int sampleRate = 16000}) {
  final samples = _decodePcm16(pcm16);
  if (samples.length < _frameLength) return [];

  final filterbank = _melFilterbankFor(sampleRate);
  final window = _hammingWindow;
  final frameCount = 1 + (samples.length - _frameLength) ~/ _hopLength;

  final frames = [
    for (var frame = 0; frame < frameCount; frame++)
      _mfccForFrame(samples, frame * _hopLength, window, filterbank),
  ];
  final normalized = _cepstralMeanNormalize(frames);
  return _addDeltas(normalized);
}

// On-device measurement (Milestone 13, 2026-08-21) found delta
// coefficients average ~6-7x smaller in magnitude than static ones
// (deltas are frame-to-frame *differences*, statics are raw post-CMN
// values) -- in DTW's unweighted per-frame Euclidean distance, that
// made deltas contribute roughly 1/50th as much as statics to the
// total, a near no-op despite being computed correctly. Scaling deltas
// by this ratio so they actually influence matching the way they're
// meant to -- still an empirically-derived placeholder like every
// other threshold in this file, not a tuned final value.
const double _deltaWeight = 7.0;

// Standard regression-based delta (rate-of-change) computation over a
// +-[_deltaWindow]-frame neighborhood, appended to each frame's static
// coefficients. Edge frames clamp to the nearest valid frame rather
// than padding with zeros, so the clip's actual start/end still
// contributes real (if asymmetric) derivative information.
List<List<double>> _addDeltas(List<List<double>> frames) {
  if (frames.isEmpty) return frames;
  final frameCount = frames.length;
  final coefficientCount = frames.first.length;
  var denominator = 0;
  for (var n = 1; n <= _deltaWindow; n++) {
    denominator += n * n;
  }
  denominator *= 2;

  return [
    for (var t = 0; t < frameCount; t++)
      [
        ...frames[t],
        for (var c = 0; c < coefficientCount; c++)
          _deltaWeight * _delta(frames, t, c, frameCount, denominator),
      ],
  ];
}

double _delta(
  List<List<double>> frames,
  int t,
  int c,
  int frameCount,
  int denominator,
) {
  var sum = 0.0;
  for (var n = 1; n <= _deltaWindow; n++) {
    final after = frames[math.min(t + n, frameCount - 1)][c];
    final before = frames[math.max(t - n, 0)][c];
    sum += n * (after - before);
  }
  return sum / denominator;
}

/// Subtracts each coefficient's mean (across every frame of this one
/// clip) from every frame -- cepstral mean normalization, a standard
/// speech-recognition preprocessing step. Removes systematic per-clip
/// bias (e.g. differing gain/distance-from-mic between Bill's
/// enrollment session and a later live query) before DTW ever compares
/// two clips, rather than leaving that bias baked into every
/// coefficient. Added after on-device data (Milestone 13, 2026-08-21)
/// showed matches were confidently wrong as often as confidently right
/// -- distance alone wasn't separating correct from incorrect matches,
/// suggesting exactly this kind of systematic offset.
List<List<double>> _cepstralMeanNormalize(List<List<double>> frames) {
  if (frames.isEmpty) return frames;
  final coefficientCount = frames.first.length;
  final means = List<double>.filled(coefficientCount, 0);
  for (final frame in frames) {
    for (var i = 0; i < coefficientCount; i++) {
      means[i] += frame[i];
    }
  }
  for (var i = 0; i < coefficientCount; i++) {
    means[i] /= frames.length;
  }
  return [
    for (final frame in frames)
      [for (var i = 0; i < coefficientCount; i++) frame[i] - means[i]],
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

// Depends only on [_frameLength], which never varies -- computed once
// and reused, rather than rebuilt per clip.
final List<double> _hammingWindow = [
  for (var n = 0; n < _frameLength; n++)
    0.54 - 0.46 * math.cos(2 * math.pi * n / (_frameLength - 1)),
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

  return _dct(logMelEnergies);
}

double _dot(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += a[i] * b[i];
  }
  return sum;
}

// The DCT-II basis matrix depends only on [_melFilterCount] and
// [_coefficientCount], both fixed constants -- computed once for the
// process lifetime rather than rebuilt (with a fresh `cos()` call per
// cell) on every single frame of every clip. On-device profiling
// (Milestone 13, 2026-08-21) found this rebuild-per-frame was the
// dominant cost in `VoiceCharacterMatcher.match()` at a 40-character
// enrollment -- ~440ms of a ~510ms match, versus ~24ms for DTW itself.
final List<List<double>> _dctBasis = [
  for (var k = 0; k < _coefficientCount; k++)
    [
      for (var m = 0; m < _melFilterCount; m++)
        math.cos(math.pi / _melFilterCount * (m + 0.5) * k),
    ],
];

/// DCT-II of [input] (one log-mel-energy value per filter), keeping the
/// first [_coefficientCount] coefficients -- the standard log-mel-energy
/// -> cepstral-coefficient step.
List<double> _dct(List<double> input) => [
  for (final basisRow in _dctBasis) _dot(input, basisRow),
];

// The filterbank depends only on [sampleRate], which is always 16000 in
// this app -- cached so repeated [extractMfcc] calls (once per enrolled
// character per match, potentially dozens of clips) don't rebuild it
// from scratch every time.
final Map<int, List<List<double>>> _filterbankCache = {};

List<List<double>> _melFilterbankFor(int sampleRate) =>
    _filterbankCache.putIfAbsent(sampleRate, () => _melFilterbank(sampleRate));

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
