import 'dart:typed_data';

/// Trims trailing near-silence from [samples], leaving [marginSamples]
/// of quiet after the last sample whose magnitude exceeds
/// [thresholdAmplitude].
///
/// Written for [TtsAnswerSpeaker]'s cached answer clips: pulling the
/// actual on-device cached files and analyzing their amplitude envelope
/// found ~209ms of trailing silence on average -- 36.3% of total clip
/// duration, remarkably consistent across every character (morse_icr
/// project memory). Folding an untrimmed clip into a pre-mixed turn
/// buffer would bake that wasted silence into every turn on top of the
/// learner's own configured recognition time. [thresholdAmplitude]
/// defaults to roughly 1% of full scale, matching the amplitude analysis
/// that found it; [marginSamples] defaults to ~15ms at 44100Hz so the
/// trim doesn't clip the natural decay of the spoken word itself.
Int16List trimTrailingSilence(
  Int16List samples, {
  int thresholdAmplitude = 328,
  int marginSamples = 662,
}) {
  var lastLoud = -1;
  for (var i = samples.length - 1; i >= 0; i--) {
    if (samples[i].abs() > thresholdAmplitude) {
      lastLoud = i;
      break;
    }
  }
  if (lastLoud == -1) return samples;
  final end = (lastLoud + 1 + marginSamples).clamp(0, samples.length);
  return samples.sublist(0, end);
}
