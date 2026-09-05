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
import 'tts_voice_option.dart';

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
  /// [speakPeriodAsDot]/[speakSlashAsStroke]/[voiceVolume]/
  /// [preferredVoiceName]/[preferredVoiceLocale] seed this speaker's
  /// section-35 settings for the very first pre-render pass; production
  /// code (TrainingScreen) generally starts these at their defaults
  /// (persisted settings load asynchronously, after this speaker already
  /// exists) and corrects them moments later via
  /// [updatePunctuationSpelling]/[setVoiceVolume]/[setPreferredVoice]
  /// once the load resolves -- the same "reflects momentarily-stale-
  /// then-corrected state" approach [_selectVoice]'s own auto-pick
  /// fallback already takes for a newly installed voice.
  TtsAnswerSpeaker({
    FlutterTts? tts,
    AudioPlayer? player,
    this.speakPeriodAsDot = true,
    this.speakSlashAsStroke = false,
    double voiceVolume = 1.0,
    String? preferredVoiceName,
    String? preferredVoiceLocale,
  }) : _tts = tts ?? FlutterTts(),
       _voiceVolume = voiceVolume,
       _preferredVoiceName = preferredVoiceName,
       _preferredVoiceLocale = preferredVoiceLocale,
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
  // Null means "auto" -- see [_selectVoice]. Set from the section-35
  // "Voice" picker via [setPreferredVoice]; a name with no matching
  // installed voice (e.g. persisted on one device, then restored on
  // another without it) falls back to auto rather than silently doing
  // nothing, same as never having a preference at all.
  String? _preferredVoiceName;
  String? _preferredVoiceLocale;
  // Every English-locale voice flutter_tts reported as installed, once
  // known -- see [_loadAvailableVoices]. Populated before [_selectVoice]
  // ever runs, so both it and the public [availableVoices] getter (for
  // the Settings picker) always see the same list.
  List<TtsVoiceOption> _availableVoices = [];

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
  /// and pre-rendering have finished. Nothing outside this class actually
  /// waits on the *pre-rendering* half any more (see
  /// [voiceSelectionReady]) -- this is kept for callers that genuinely
  /// need every character cached, and because [_prerenderCharacters]'s
  /// own failure tolerance means this still resolves in bounded time
  /// even when pre-rendering never fully succeeds.
  Future<void> get ready => _ready;

  /// Resolves once voice selection (which installed voice will actually
  /// speak) is settled -- well before [ready], which additionally waits
  /// on every character's audio being pre-rendered. Settings' "Speech
  /// Voice" picker and its "Preparing voice…" spinner watch this, not
  /// [ready] (2026-09-05): an earlier version gated both on [ready], so
  /// picking a voice that's slow or intermittently hangs mid-synthesis
  /// (Samantha (Enhanced) on this device/iOS version -- see morse_icr
  /// project memory) left the picker stuck showing "Auto" and the
  /// spinner running for as long as pre-rendering the whole ~40-character
  /// table took, sometimes minutes, even though the voice to actually
  /// speak with had already been settled in the first second or two.
  /// Pre-rendering keeps running in the background regardless; [speak]
  /// already tolerates a character that isn't cached yet by falling back
  /// to live synthesis.
  Future<void> get voiceSelectionReady => _voiceSelectionReady.future;

  final Completer<void> _voiceSelectionReady = Completer<void>();

  /// Every English-locale voice installed on this device, for the
  /// section-35 "Voice" picker -- empty before [voiceSelectionReady]
  /// resolves, or if voice discovery fails (see [_loadAvailableVoices]'s
  /// own try/catch).
  List<TtsVoiceOption> get availableVoices =>
      List.unmodifiable(_availableVoices);

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
      await _selectVoice();
    }
    // Deliberately before _prerenderAll(), not after -- see
    // [voiceSelectionReady]'s own doc comment for why.
    if (!_voiceSelectionReady.isCompleted) _voiceSelectionReady.complete();

    await _prerenderAll();
  }

  /// Populates [_availableVoices] from whatever flutter_tts reports as
  /// installed, English-locale voices only -- shared by [_selectVoice]
  /// (which picks from it) and the public [availableVoices] getter
  /// (which lists it for the Settings picker), so both always agree on
  /// what's actually available on this device.
  Future<void> _loadAvailableVoices() async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null) return;
      final options = <TtsVoiceOption>[];
      for (final entry in voices) {
        final voice = Map<String, dynamic>.from(entry as Map);
        final locale = voice['locale'] as String? ?? '';
        if (!locale.startsWith('en')) continue;
        options.add(
          TtsVoiceOption(
            name: voice['name'] as String? ?? '',
            locale: locale,
            quality: (voice['quality'] as String? ?? 'default').toLowerCase(),
          ),
        );
      }
      _availableVoices = options;
    } catch (_) {
      // Voice discovery isn't guaranteed to succeed on every device --
      // [_availableVoices] just stays empty, and [_selectVoice] falls
      // back to whatever the platform default voice is rather than
      // blocking speech entirely.
    }
  }

  /// Selects [_preferredVoiceName]/[_preferredVoiceLocale] (the
  /// section-35 "Voice" setting) if it names a voice actually installed
  /// on this device, falling back to auto-picking the highest-quality
  /// installed English voice otherwise -- both when no preference has
  /// ever been set (null, the default for a learner who's never opened
  /// that setting) and when a *persisted* preference names a voice this
  /// device doesn't have (e.g. restored from a different device). Only
  /// switches away from the plain default voice if something better is
  /// actually available -- Enhanced/Premium voices are an opt-in
  /// download in iOS Settings, not guaranteed present, and iOS's default
  /// "compact" voice has audible synthesis artifacts a higher-quality
  /// one doesn't.
  Future<void> _selectVoice() async {
    await _loadAvailableVoices();
    try {
      TtsVoiceOption? chosen;
      final preferredName = _preferredVoiceName;
      if (preferredName != null) {
        for (final voice in _availableVoices) {
          if (voice.name == preferredName &&
              (_preferredVoiceLocale == null ||
                  voice.locale == _preferredVoiceLocale)) {
            chosen = voice;
            break;
          }
        }
      }
      chosen ??= _bestAvailableVoice();
      if (chosen == null) return;
      await _tts.setVoice({'name': chosen.name, 'locale': chosen.locale});
      _voiceIdentifier = '${chosen.name}_${chosen.locale}';
    } catch (_) {
      // Same tolerance as _loadAvailableVoices -- speak()/pre-rendering
      // fall back to whatever the platform default voice is.
    }
  }

  TtsVoiceOption? _bestAvailableVoice() {
    TtsVoiceOption? best;
    var bestRank = 1; // Only switch away from the default voice.
    for (final voice in _availableVoices) {
      final rank = _voiceQualityRank[voice.quality] ?? 1;
      if (rank > bestRank) {
        bestRank = rank;
        best = voice;
      }
    }
    return best;
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
  Future<void> _prerenderAll() =>
      _prerenderCharacters(morseCodeTable.keys.toList());

  // A single bulk retry pass over whatever failed the first time, rather
  // than retrying each character in place before moving to the next
  // (2026-09-05) -- the AVSpeechSynthesizer hang [_prerenderCharacter]
  // works around below is intermittent, not tied to a specific character
  // or even a small handful of them: on-device, a learner picked Samantha
  // (Enhanced) and force-quit before its very first (full-table, nothing
  // cached yet) pre-render pass finished, so on relaunch most of the
  // table still needed synthesizing -- and Samantha hangs (or is just
  // plain slow -- a large neural voice rendering ~40 short files
  // sequentially, with no per-character concurrency, adds up regardless
  // of hangs) on enough of them that retrying in place (an earlier
  // version of this fix tried 3 attempts per character before moving on)
  // multiplied an already-slow pass badly. Retrying the whole batch of
  // failures exactly once instead mirrors the one workaround already
  // proven to reliably recover (switching to another voice and back,
  // which is just one more full [_prerenderAll] pass) while bounding the
  // added worst case to roughly 1 extra pass, however many characters
  // happen to be affected, not 2-3 extra passes *per affected character*.
  // This alone did not fix Settings' "Voice" picker reading as hung,
  // though -- see [voiceSelectionReady]'s doc comment for the actual fix,
  // which stopped that picker waiting on this slow method at all.
  Future<void> _prerenderCharacters(List<String> characters) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final failed = <String>[];
      for (final character in characters) {
        if (!await _prerenderCharacter(character, directory)) {
          failed.add(character);
        }
      }
      for (final character in failed) {
        await _prerenderCharacter(character, directory);
      }
    } catch (_) {
      // Pre-rendering isn't guaranteed to succeed on every device --
      // speak() falls back to live synthesis for anything not cached.
    }
  }

  /// Renders and caches one character, returning whether it ended up
  /// cached -- callers (see [_prerenderCharacters]) use a `false` to
  /// decide what's worth a retry pass, rather than this method retrying
  /// internally (see that method's own doc comment for why).
  Future<bool> _prerenderCharacter(
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
      var timedOut = false;
      await _tts
          .synthesizeToFile(spokenText, path, true)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              logDebug('prerender($character): synthesizeToFile timed out');
              timedOut = true;
              unawaited(_tts.stop());
            },
          );
      if (timedOut && await file.exists()) {
        // The buffer-callback writer flushes audio incrementally as it
        // goes, not atomically at the end -- confirmed on-device
        // (2026-09-02): "A" under Samantha (Enhanced) hung on this same
        // bug, but the file already existed by the time the timeout
        // fired, containing only however much audio had been written
        // before the hang. Left alone, that truncated fragment -- "A"
        // played back as a short click, not the full word -- would get
        // cached below exactly like a real, complete render. Deleting
        // it here instead sends this character down the same too-short
        // check below as a render that produced nothing at all.
        await file.delete();
      }
    }
    if (!await file.exists()) {
      // Nothing was written at all (a hang with zero buffers flushed
      // before the timeout) -- report failure so [_prerenderCharacters]
      // can retry it in its one bulk pass, rather than falling straight
      // through to [_speak]'s live-synthesis fallback for the rest of
      // this app session.
      return false;
    }
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
      final samples = trimTrailingSilence(readPcm16Samples(wav));
      // Guards against a *previous* run's truncated file, not just a
      // fresh one this call just avoided caching above -- the file
      // this reads back was already sitting on disk (this whole
      // branch only runs when `!await file.exists()` was false coming
      // in, i.e. some earlier prerender pass wrote it, possibly
      // before this truncation guard existed at all). Confirmed
      // on-device (2026-09-02): a single-vowel word like "a" (see
      // [spokenNames]) is short even fully spoken, but a genuinely
      // truncated click fragment measured well under this floor --
      // 100ms is comfortably below every real spoken character's own
      // length while still well above a bare onset transient.
      // Discarding it here (not just at synthesis time) makes this
      // self-healing: a stale corrupt file from before this check
      // existed gets caught and cleaned up the next time this
      // character's audio is loaded, not just newly-created ones.
      if (samples.length < (_sampleRate * 0.1).round()) {
        logDebug(
          'prerender($character): cached file too short '
          '(${samples.length} samples), discarding',
        );
        await file.delete();
        return false;
      }
      _cachedAudio[character] = samples;
      return true;
    } on FormatException catch (e) {
      // A format problem will look identical on retry -- report failure
      // but leave the (unusable) file in place; a retry would just hit
      // the same conversion failure again.
      logDebug('prerender($character): conversion failed: $e');
      return false;
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
      await _prerenderCharacters(const ['.', '/']);
    });
  }

  /// Updates which installed voice (section 35's "Voice" picker) speaks
  /// every character going forward -- null [name] means "auto" (see
  /// [_bestAvailableVoice]), matching [TtsAnswerSpeaker]'s original
  /// always-auto behavior for a learner who's never touched this
  /// setting. Re-renders *every* character, not just "." and "/" like
  /// [updatePunctuationSpelling] -- a voice change affects every spoken
  /// word, and [_fileNameFor]'s cache key already includes
  /// [_voiceIdentifier], so [_prerenderAll] naturally regenerates
  /// everything under new file names rather than reusing the old
  /// voice's recordings. A no-op if neither actually changed, same
  /// reasoning as [updatePunctuationSpelling]'s own no-op guard. Only
  /// [_selectVoice] itself is iOS-only (see [_initialize]'s matching
  /// platform check) -- calling this on another platform just records
  /// the preference harmlessly for whenever it might matter there too.
  Future<void> setPreferredVoice({required String? name, String? locale}) {
    return _enqueue(() async {
      if (_preferredVoiceName == name && _preferredVoiceLocale == locale) {
        return;
      }
      _preferredVoiceName = name;
      _preferredVoiceLocale = locale;
      if (!kIsWeb && Platform.isIOS) {
        await _selectVoice();
      }
      await _prerenderAll();
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
      // Timed out, same as [_prerenderCharacter]'s own synthesizeToFile
      // call -- confirmed on-device (2026-09-02) that the identical
      // underlying AVSpeechSynthesizer hang (see that method's own
      // comment) also happens via plain speak(), not just write()/
      // synthesizeToFile, and specifically far more often on some
      // voices (Samantha Enhanced) than others. Without this timeout, a
      // single hung speak() call here -- awaitSpeakCompletion(true)
      // means its Future never resolves on its own -- would never
      // return, which permanently wedges [_enqueue]'s own queue (every
      // operation after it, on any character, waits on this Future
      // forever): confirmed on-device as the cause of a voice going
      // completely silent for every character except the few that
      // happened to already be cached (and so never needed this live
      // fallback at all) before the wedge occurred.
      await _tts
          .speak(
            spokenTextFor(
              character,
              speakPeriodAsDot: speakPeriodAsDot,
              speakSlashAsStroke: speakSlashAsStroke,
            ),
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              logDebug('speak($character): live synth timed out');
              unawaited(_tts.stop());
            },
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
