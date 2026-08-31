import 'dart:async';
import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data' show Int16List;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../audio/in_memory_audio_source.dart';
import '../audio/pcm16_gain.dart';
import '../audio/pcm16_silence_trim.dart';
import '../audio/pcm16_wav.dart';
import '../audio/wav_pcm16_converter.dart';
import '../debug_log.dart';
import '../morse/morse_code.dart';
import 'answer_speaker.dart';
import 'spoken_character.dart';

/// Speaks characters aloud via on-device text-to-speech
/// (morse_icr_spec.md section 28's "computer voice").
///
/// Pre-renders every speakable character's word once (via
/// [FlutterTts.synthesizeToFile]), reads the result into memory as raw
/// 16-bit-PCM/44100Hz samples with trailing silence trimmed, and caches
/// those samples for two consumers: [TurnAudioEngine] splices them
/// directly into a combined per-turn buffer (the pre-mix architecture,
/// morse_icr project memory) via [cachedSamplesFor], and [speak] itself
/// plays them back through [AudioPlayer] from in-memory bytes as a live
/// fallback for a character that isn't cached (pre-rendering failed, or
/// hasn't finished yet). On-device testing found audible clicks/
/// distortion when speaking live from inside the app that were absent
/// from iOS's own "Speak Selection" feature given the identical text,
/// and separately found inconsistent (not tied to any particular
/// character) playback delay when the cached audio was played directly
/// from disk instead of in-memory bytes -- consistent with per-call disk
/// I/O timing variance. Both are absent from Morse tone playback, which
/// has always used in-memory bytes.
class TtsAnswerSpeaker implements AnswerSpeaker {
  /// [speakPeriodAsDot]/[speakSlashAsStroke]/[voiceVolume] seed this
  /// speaker's section-35 settings for the very first pre-render pass;
  /// production code (TrainingScreen) generally starts these at their
  /// defaults (persisted settings load asynchronously, after this
  /// speaker already exists) and corrects them moments later via
  /// [updatePunctuationSpelling]/[setVoiceVolume] once the load resolves
  /// -- the same "reflects momentarily-stale-then-corrected state"
  /// approach [_useHighestQualityVoice] already takes for a newly
  /// installed voice.
  TtsAnswerSpeaker({
    FlutterTts? tts,
    AudioPlayer? player,
    this.speakPeriodAsDot = true,
    this.speakSlashAsStroke = false,
    double voiceVolume = 1.0,
  }) : _tts = tts ?? FlutterTts(),
       _voiceVolume = voiceVolume,
       // See TurnAudioEngine's matching constructor comment --
       // handleAudioSessionActivation: false avoids this player
       // redundantly reactivating the shared AVAudioSession (which
       // TrainingScreen already owns explicitly) on every play() call.
       _player = player ?? AudioPlayer(handleAudioSessionActivation: false) {
    // [speak] awaits this before playing or falling back to live
    // speech, so an early announcement can never race a still-in-flight
    // setup/pre-render call below.
    _ready = _initialize();
  }

  static const _sampleRate = 44100;

  final FlutterTts _tts;
  AudioPlayer _player;
  late final Future<void> _ready;
  final Map<String, Int16List> _cachedAudio = {};
  String _voiceIdentifier = 'default';
  bool speakPeriodAsDot;
  bool speakSlashAsStroke;
  double _voiceVolume;

  // Every operation that touches _player runs through this queue, so
  // resetPlayer() can never dispose it out from under a still-in-flight
  // speak() call -- see TurnAudioEngine's matching field for the full
  // rationale (the same class of race caused speak() to hang before its
  // onDone handler, below, was added).
  Future<void> _queue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

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
    // when the utterance/file is actually finished -- speak() relies on
    // resolving at actual completion, and pre-rendering below relies on
    // synthesizeToFile() resolving only once the file is fully written.
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
  /// reads it into memory as trimmed raw PCM16 samples so nothing needs
  /// live synthesis, per-call disk I/O, or per-call WAV parsing during an
  /// actual training session. The rendered files persist on disk across
  /// launches (skipped if already present) since nothing about a
  /// character's spoken form changes between runs -- except that the
  /// file name is derived from both the spoken text and the chosen
  /// voice, so a future change to [spokenTextFor]'s mapping, or the
  /// learner installing a higher-quality voice (section 36) that changes
  /// which voice [_useHighestQualityVoice] picks, naturally invalidates
  /// any stale cached file instead of it silently continuing to play the
  /// old pronunciation/voice.
  Future<void> _prerenderAll() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      for (final character in morseCodeTable.keys) {
        await _prerenderCharacter(character, directory);
      }
    } catch (_) {
      // Pre-rendering isn't guaranteed to succeed on every device --
      // speak() falls back to live synthesis for anything not cached.
    }
  }

  Future<void> _prerenderCharacter(
    String character, [
    Directory? directory,
  ]) async {
    final resolvedDirectory =
        directory ?? await getApplicationDocumentsDirectory();
    final spokenText = spokenTextFor(
      character,
      speakPeriodAsDot: speakPeriodAsDot,
      speakSlashAsStroke: speakSlashAsStroke,
    );
    final path =
        '${resolvedDirectory.path}/${_fileNameFor(character, spokenText)}';
    final file = File(path);
    if (!await file.exists()) {
      // AVSpeechSynthesizer.write() (what synthesizeToFile uses under
      // the hood on iOS) has a known Apple bug where its buffer-callback
      // loop never terminates for certain short utterances -- observed
      // on-device for "/" ("slash"): it spins indefinitely without ever
      // firing the didFinish delegate callback synthesizeToFile's future
      // awaits, pegging the main thread until iOS's launch watchdog
      // kills the whole app (blank white screen, then killed). stop()
      // interrupts the underlying AVSpeechSynthesizer directly so the
      // native spin doesn't keep burning CPU after Dart gives up on it.
      await _tts.synthesizeToFile(spokenText, path, true).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logDebug('prerender($character): synthesizeToFile timed out');
          unawaited(_tts.stop());
        },
      );
    }
    if (await file.exists()) {
      final rendered = await file.readAsBytes();
      // flutter_tts's synthesizeToFile writes 32-bit float PCM at
      // AVSpeechSynthesizer's own native sample rate on iOS (see
      // convertToPcm16Wav's doc comment) -- converting once here,
      // rather than leaving playback to handle that format directly,
      // is what fixed TTS answer audio's play() taking 600-1000ms+ to
      // be acknowledged regardless of clip length or whether the phone
      // was locked (morse_icr project memory). A character whose
      // format this wasn't written to handle (e.g. a future flutter_tts
      // version changing its output format) is left uncached rather
      // than caching something unusable for splicing into a turn
      // buffer -- speak() falls back to live synthesis for it instead.
      try {
        final wav = convertToPcm16Wav(rendered, targetSampleRate: _sampleRate);
        _cachedAudio[character] = trimTrailingSilence(readPcm16Samples(wav));
      } on FormatException catch (e) {
        logDebug('prerender($character): conversion failed: $e');
      }
    }
  }

  // Encodes as the character's code unit rather than the character
  // itself, since some characters (e.g. "/") aren't valid in a file
  // name; includes a hash of the spoken text and chosen voice so a
  // changed spelling or a newly installed higher-quality voice gets a
  // new file name instead of reusing a stale cached recording.
  String _fileNameFor(String character, String spokenText) =>
      'spoken_${character.codeUnitAt(0)}_${Object.hash(spokenText, _voiceIdentifier)}.wav';

  /// Updates which spoken form "." and "/" use going forward (section
  /// 35), re-rendering just those two characters -- everything else
  /// stays cached from before. A no-op if neither actually changed, so
  /// [TrainingScreen] can call this on every Settings load/change
  /// without worrying about redundant re-renders.
  Future<void> updatePunctuationSpelling({
    required bool speakPeriodAsDot,
    required bool speakSlashAsStroke,
  }) {
    return _enqueue(() async {
      if (this.speakPeriodAsDot == speakPeriodAsDot &&
          this.speakSlashAsStroke == speakSlashAsStroke) {
        return;
      }
      this.speakPeriodAsDot = speakPeriodAsDot;
      this.speakSlashAsStroke = speakSlashAsStroke;
      try {
        final directory = await getApplicationDocumentsDirectory();
        await _prerenderCharacter('.', directory);
        await _prerenderCharacter('/', directory);
      } catch (_) {
        // Same tolerance as _prerenderAll -- speak() falls back to live
        // synthesis for anything that fails to (re-)cache.
      }
    });
  }

  /// Updates the spoken answer's playback volume (section 35's "Voice:
  /// Volume") going forward -- applied as sample gain (see
  /// [scaleInt16Samples]'s doc comment for why), plus the live TTS
  /// engine's own volume for [_speak]'s uncached fallback path.
  void setVoiceVolume(double volume) {
    _voiceVolume = volume;
    unawaited(_tts.setVolume(volume));
  }

  @override
  Int16List? cachedSamplesFor(String character) {
    final cached = _cachedAudio[character];
    if (cached == null) return null;
    return scaleInt16Samples(cached, _voiceVolume);
  }

  @override
  Future<void> speak(String character) {
    return _enqueue(() => _speak(character));
  }

  Future<void> _speak(String character) async {
    await _ready;
    final cachedSamples = _cachedAudio[character];
    if (cachedSamples == null) {
      logDebug('speak($character): no cached audio, live synth');
      await _tts.speak(
        spokenTextFor(
          character,
          speakPeriodAsDot: speakPeriodAsDot,
          speakSlashAsStroke: speakSlashAsStroke,
        ),
      );
      return;
    }

    // just_audio's native iOS setAudioSource() auto-starts the newly
    // loaded source immediately if its own `playing` flag is still true
    // from before (AudioPlayer.m:606-720) -- nothing here ever
    // explicitly pauses this player between characters or sessions, so a
    // speak() call interrupted rather than left to finish naturally
    // (Stop, or the onDone-disposal race below) can leave that flag
    // stuck true. Pausing first (a no-op if already paused) guarantees
    // our own play() call is what actually starts playback.
    await _player.pause();
    await _player.setAudioSource(
      InMemoryAudioSource(
        pcm16WavBytes(
          scaleInt16Samples(cachedSamples, _voiceVolume),
          sampleRate: _sampleRate,
        ),
      ),
    );

    final completer = Completer<void>();
    late final StreamSubscription<ProcessingState> subscription;
    subscription = _player.processingStateStream.listen(
      (state) {
        if (state == ProcessingState.completed) {
          subscription.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      },
      onDone: () {
        // AudioPlayer.dispose() (called by resetPlayer(), e.g. from
        // TrainingScreen's app-resume handler racing this in-flight
        // speak()) closes this stream directly without ever emitting
        // ProcessingState.completed -- confirmed by reading just_audio's
        // dispose() source. Without this handler, completer.future never
        // resolves and this hangs forever.
        if (!completer.isCompleted) {
          logDebug('speak($character): player disposed mid-speak, unsticking');
          completer.completeError(
            StateError('AudioPlayer disposed during speak()'),
          );
        }
      },
    );
    logDebug('speak($character): play()');
    await _player.play();
    await completer.future;
    logDebug('speak($character): completed');
  }

  /// Recreates the underlying [AudioPlayer], discarding the old one.
  ///
  /// See [TurnAudioEngine.resetPlayer] -- the same underlying
  /// [InMemoryAudioSource]/just_audio local-proxy-server staleness
  /// applies here too, since [speak]'s live-fallback path plays cached
  /// TTS audio through the identical mechanism. Call this on app resume.
  Future<void> resetPlayer() {
    return _enqueue(_resetPlayer);
  }

  Future<void> _resetPlayer() async {
    final old = _player;
    _player = AudioPlayer(handleAudioSessionActivation: false);
    await old.dispose();
  }
}
