import 'dart:typed_data' show Uint8List;

import 'package:just_audio/just_audio.dart';

/// Plays a WAV buffer already held in memory, with no disk I/O.
///
/// package:just_audio has no built-in equivalent to package:audioplayers'
/// `BytesSource` -- this is the documented pattern for one, shared by
/// [TurnAudioEngine] and [TtsAnswerSpeaker] rather than each
/// reinventing it.
class InMemoryAudioSource extends StreamAudioSource {
  InMemoryAudioSource(this._bytes);

  final Uint8List _bytes;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
