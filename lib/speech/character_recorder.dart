import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// Thrown when [recordCharacterClip] can't record because microphone
/// permission has been denied.
class MicPermissionDenied implements Exception {}

/// Records a fixed-duration raw PCM16 clip of the learner speaking a
/// single character (morse_icr_spec.md section 38's enrollment step),
/// at the same 16kHz mono format confirmed clean by Milestone 13 step
/// 1's on-device capture spike.
///
/// A fixed duration rather than silence/VAD-based endpointing -- section
/// 38 explicitly defers endpointing to the real-time recognition step;
/// enrollment only needs one clean take per character. 1.5s comfortably
/// covers even the longest spoken forms (e.g. "double-u").
Future<Uint8List> recordCharacterClip({
  Duration duration = const Duration(milliseconds: 1500),
}) async {
  final recorder = AudioRecorder();
  try {
    if (!await recorder.hasPermission()) throw MicPermissionDenied();
    const sampleRate = 16000;
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
    );

    final bytes = BytesBuilder();
    final subscription = stream.listen(bytes.add);

    await Future<void>.delayed(duration);
    await recorder.stop();
    await subscription.cancel();

    return bytes.toBytes();
  } finally {
    await recorder.dispose();
  }
}
