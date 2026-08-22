import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/speech/enrollment_store.dart';
import 'package:morse_icr/speech/voice_character_matcher.dart';

import 'test_audio.dart';

class _FakeEnrollmentStore implements EnrollmentStore {
  _FakeEnrollmentStore([Map<String, List<Uint8List>>? recordings])
    : recordings = recordings ?? {};

  final Map<String, List<Uint8List>> recordings;
  int loadRecordingsCalls = 0;

  @override
  Future<Set<String>> enrolledCharacters() async => recordings.keys.toSet();

  @override
  Future<void> saveRecordings(
    String character,
    List<Uint8List> pcm16Takes,
  ) async {
    recordings[character] = pcm16Takes;
  }

  @override
  Future<List<Uint8List>> loadRecordings(String character) async {
    loadRecordingsCalls++;
    return recordings[character] ?? [];
  }
}

void main() {
  group('VoiceCharacterMatcher', () {
    test('matches the query to the closest enrolled character', () async {
      final store = _FakeEnrollmentStore({
        'A': [sineWavePcm16(300)],
        'B': [sineWavePcm16(900)],
      });
      final matcher = VoiceCharacterMatcher(store);

      // A near-copy of A's tone, slightly time-stretched -- stands in
      // for a second take of the same spoken character.
      final query = sineWavePcm16(300, durationSeconds: 0.55);

      final result = await matcher.match(query, maxDistance: 1000);

      expect(result, 'A');
    });

    test('returns null when nothing enrolled is close enough', () async {
      final store = _FakeEnrollmentStore({
        'A': [sineWavePcm16(300)],
      });
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

    test(
      'candidates restricts matching to a subset of enrolled characters',
      () async {
        final store = _FakeEnrollmentStore({
          'A': [sineWavePcm16(300)],
          'B': [sineWavePcm16(900)],
        });
        final matcher = VoiceCharacterMatcher(store);
        // Closest to 'A', but 'A' isn't a candidate -- the active
        // training set doesn't include it (e.g. training digits, not
        // letters), so it should never be returned even though it's
        // the overall closest match.
        final query = sineWavePcm16(300, durationSeconds: 0.55);

        final restricted = await matcher.match(
          query,
          maxDistance: 1000,
          candidates: {'B'},
        );
        final unrestricted = await matcher.match(query, maxDistance: 1000);

        expect(restricted, 'B');
        expect(unrestricted, 'A');
      },
    );

    test(
      'caches reference recordings across matches, until invalidated',
      () async {
        final store = _FakeEnrollmentStore({
          'A': [sineWavePcm16(300)],
        });
        final matcher = VoiceCharacterMatcher(store);
        final query = sineWavePcm16(300, durationSeconds: 0.55);

        await matcher.match(query, maxDistance: 1000);
        await matcher.match(query, maxDistance: 1000);

        expect(store.loadRecordingsCalls, 1);

        matcher.invalidateCache();
        await matcher.match(query, maxDistance: 1000);

        expect(store.loadRecordingsCalls, 2);
      },
    );

    test('matches on the closest of a character\'s several enrolled takes, '
        'not just its first', () async {
      final store = _FakeEnrollmentStore({
        // 'A's first take is too short to produce any MFCC frames
        // (extractMfcc returns []), so dtwDistance against it is
        // always infinity -- a real match can only happen by
        // considering the second, genuinely close take too. Stands in
        // for "different takes of the same character legitimately
        // vary in quality/pace, and a query should only need to
        // resemble one of them."
        'A': [Uint8List(10), sineWavePcm16(300)],
      });
      final matcher = VoiceCharacterMatcher(store);
      final query = sineWavePcm16(300, durationSeconds: 0.55);

      final result = await matcher.match(query, maxDistance: 1000);

      expect(result, 'A');
    });
  });
}
