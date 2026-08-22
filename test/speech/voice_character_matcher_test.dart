import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/enrollment_store.dart';
import 'package:morse_icr/speech/voice_character_matcher.dart';

import 'test_audio.dart';

class _FakeEnrollmentStore implements EnrollmentStore {
  _FakeEnrollmentStore([Map<String, Uint8List>? recordings])
    : recordings = recordings ?? {};

  final Map<String, Uint8List> recordings;

  @override
  Future<Set<String>> enrolledCharacters() async => recordings.keys.toSet();

  @override
  Future<void> saveRecording(String character, Uint8List pcm16) async {
    recordings[character] = pcm16;
  }

  @override
  Future<Uint8List?> loadRecording(String character) async =>
      recordings[character];
}

void main() {
  group('VoiceCharacterMatcher', () {
    test('matches the query to the closest enrolled character', () async {
      final store = _FakeEnrollmentStore({
        'A': sineWavePcm16(300),
        'B': sineWavePcm16(900),
      });
      final matcher = VoiceCharacterMatcher(store);

      // A near-copy of A's tone, slightly time-stretched -- stands in
      // for a second take of the same spoken character.
      final query = sineWavePcm16(300, durationSeconds: 0.55);

      final result = await matcher.match(query, maxDistance: 1000);

      expect(result, 'A');
    });

    test('returns null when nothing enrolled is close enough', () async {
      final store = _FakeEnrollmentStore({'A': sineWavePcm16(300)});
      final matcher = VoiceCharacterMatcher(store);

      final query = whiteNoisePcm16();

      final result = await matcher.match(query, maxDistance: 0.0001);

      expect(result, isNull);
    });

    test('returns null when nothing is enrolled', () async {
      final matcher = VoiceCharacterMatcher(_FakeEnrollmentStore());

      final result = await matcher.match(sineWavePcm16(300));

      expect(result, isNull);
    });
  });
}
