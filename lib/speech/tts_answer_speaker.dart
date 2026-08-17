import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../audio/in_memory_audio_source.dart';
import '../morse/morse_code.dart';
import 'answer_speaker.dart';
import 'spoken_character.dart';

/// Speaks characters aloud via on-device text-to-speech
/// (morse_icr_spec.md section 28's "computer voice").
///
/// Pre-renders every speakable character's word once (via
/// [FlutterTts.synthesizeToFile]), reads the result into memory, and
/// plays it back through [AudioPlayer] from in-memory bytes -- the same
/// mechanism already used for Morse tone playback -- rather than
/// calling [FlutterTts.speak] live during training or reading the
/// cached file from disk on every call. On-device testing found
/// audible clicks/distortion when speaking live from inside the app
/// that were absent from iOS's own "Speak Selection" feature given the
/// identical text, and separately found inconsistent (not tied to any
/// particular character) playback delay when the cached audio was
/// played directly from disk instead of in-memory bytes -- consistent
/// with per-call disk I/O timing variance. Both are absent from Morse
/// tone playback, which has always used in-memory bytes.
class TtsAnswerSpeaker implements AnswerSpeaker {
  TtsAnswerSpeaker({FlutterTts? tts, AudioPlayer? player})
    : _tts = tts ?? FlutterTts(),
      _player = player ?? AudioPlayer() {
    // [speak] awaits this before playing or falling back to live
    // speech, so an early announcement can never race a still-in-flight
    // setup/pre-render call below.
    _ready = _initialize();
  }

  final FlutterTts _tts;
  final AudioPlayer _player;
  late final Future<void> _ready;
  final Map<String, Uint8List> _cachedAudio = {};
  String _voiceIdentifier = 'default';

  static const Map<String, int> _voiceQualityRank = {
    'premium': 3,
    'enhanced': 2,
    'default': 1,
  };

  /// Resolves once setup (voice selection, audio session configuration)
  /// and pre-rendering have finished, so UI can show a "preparing"
  /// indicator in the meantime -- most noticeable right after the
  /// learner installs a higher-quality voice (section 36), since that
  /// triggers a fresh render pass for every character.
  Future<void> get ready => _ready;

  Future<void> _initialize() async {
    // Without these, speak()/synthesizeToFile()'s futures resolve as
    // soon as the request is *handed to* the platform TTS engine, not
    // when the utterance/file is actually finished -- TrainingEngine
    // relies on speak() resolving at actual completion so the next
    // character waits for the answer to finish (section 28), and
    // pre-rendering below relies on synthesizeToFile() resolving only
    // once the file is fully written.
    await _tts.awaitSpeakCompletion(true);
    await _tts.awaitSynthCompletion(true);

    if (!kIsWeb && Platform.isIOS) {
      // The AVAudioSession category (.playback, mixWithOthers) is
      // configured once, app-wide, in main.dart -- both this plugin's
      // AVSpeechSynthesizer and the Morse tone player
      // (package:audioplayers) would otherwise renegotiate the session
      // against each other on every play() call.

      // iOS's default "compact" voice has audible synthesis artifacts
      // that a higher-quality installed voice doesn't have. Only
      // switches if one is actually available -- Enhanced/Premium
      // voices are an opt-in download in iOS Settings, not guaranteed
      // present.
      await _useHighestQualityVoice();
    }

    await _prerenderAll();
  }

  Future<void> _useHighestQualityVoice() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null) return;

      Map<String, dynamic>? best;
      var bestRank = 1; // Only switch away from the default voice.
      for (final entry in voices) {
        final voice = Map<String, dynamic>.from(entry as Map);
        final locale = voice['locale'] as String? ?? '';
        if (!locale.startsWith('en')) continue;
        final quality = (voice['quality'] as String? ?? '').toLowerCase();
        final rank = _voiceQualityRank[quality] ?? 1;
        if (rank > bestRank) {
          bestRank = rank;
          best = voice;
        }
      }

      final chosen = best;
      if (chosen != null) {
        await _tts.setVoice({
          'name': chosen['name'] as String,
          'locale': chosen['locale'] as String,
        });
        _voiceIdentifier = '${chosen['name']}_${chosen['locale']}';
      }
    } catch (_) {
      // Voice discovery isn't guaranteed to succeed on every device --
      // fall back to whatever the platform default voice is rather
      // than blocking speech entirely.
    }
  }

  /// Renders every character in [morseCodeTable] to a file once, then
  /// reads it into memory so nothing needs live synthesis or per-call
  /// disk I/O during an actual training session. The rendered files
  /// persist on disk across launches (skipped if already present)
  /// since nothing about a character's spoken form changes between
  /// runs -- except that the file name is derived from both the spoken
  /// text and the chosen voice, so a future change to [spokenTextFor]'s
  /// mapping, or the learner installing a higher-quality voice (section
  /// 36) that changes which voice [_useHighestQualityVoice] picks,
  /// naturally invalidates any stale cached file instead of it silently
  /// continuing to play the old pronunciation/voice.
  Future<void> _prerenderAll() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      for (final character in morseCodeTable.keys) {
        final spokenText = spokenTextFor(character);
        final path = '${directory.path}/${_fileNameFor(character, spokenText)}';
        final file = File(path);
        if (!await file.exists()) {
          await _tts.synthesizeToFile(spokenText, path, true);
        }
        if (await file.exists()) {
          _cachedAudio[character] = await file.readAsBytes();
        }
      }
    } catch (_) {
      // Pre-rendering isn't guaranteed to succeed on every device --
      // speak() falls back to live synthesis for anything not cached.
    }
  }

  // Encodes as the character's code unit rather than the character
  // itself, since some characters (e.g. "/") aren't valid in a file
  // name; includes a hash of the spoken text and chosen voice so a
  // changed spelling or a newly installed higher-quality voice gets a
  // new file name instead of reusing a stale cached recording.
  String _fileNameFor(String character, String spokenText) =>
      'spoken_${character.codeUnitAt(0)}_${Object.hash(spokenText, _voiceIdentifier)}.wav';

  @override
  Future<void> speak(String character) async {
    await _ready;
    final cachedAudio = _cachedAudio[character];
    if (cachedAudio == null) {
      await _tts.speak(spokenTextFor(character));
      return;
    }

    // package:just_audio's play() future resolves once the native
    // platform has acknowledged the play *request*, not once the clip
    // actually finishes (confirmed on-device: it consistently resolved
    // within a few ms of being called). TrainingEngine's
    // onRecognitionTimeout hook needs to await actual completion
    // (section 28/29), so this listens for processingState reaching
    // ProcessingState.completed instead -- the just_audio equivalent of
    // the onPlayerComplete stream this code used with audioplayers.
    // Set up *after* setAudioSource (which moves processingState off of
    // any stale `completed` left over from the previous character) and
    // *before* play(), so no transition can be missed.
    await _player.setAudioSource(InMemoryAudioSource(cachedAudio));

    final completer = Completer<void>();
    late final StreamSubscription<ProcessingState> subscription;
    subscription = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        subscription.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await _player.play();
    await completer.future;
  }
}
