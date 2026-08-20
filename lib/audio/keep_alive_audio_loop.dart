import 'dart:math' as math;
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

import '../debug_log.dart';
import 'in_memory_audio_source.dart';
import 'pcm16_wav.dart';

/// Plays a continuous, effectively inaudible looping tone for the
/// entire duration a training session is running.
///
/// Lock-screen support was reverted (morse_icr_spec.md section 37), but
/// background execution itself is still required -- the app's actual
/// use case is training with wireless headphones, phone in a pocket,
/// screen locked. iOS grants a backgrounded app continued CPU time for
/// `UIBackgroundModes: audio` contingent on recognizing genuinely
/// continuous audio playback; Morse/TTS playback here is short bursts
/// separated by real silence (the recognition-time gap between
/// characters), and on-device testing showed the *entire training
/// loop* -- not just audio output -- froze mid-background-session when
/// a background transition happened to coincide with one of those
/// gaps, only resuming once the app was manually reopened. Looping a
/// quiet-but-genuinely-nonzero tone the whole time a session runs keeps
/// iOS's background-audio grant continuously satisfied -- the standard
/// fix for this class of "bursty" background-audio app (interval
/// timers, meditation-bell apps, and similar).
///
/// A louder/more assertive tone (200Hz, 0.3 amplitude, 0.1 volume) was
/// tried on 2026-08-20 to test whether it earned the process a stronger
/// background priority classification from iOS, hoping to reduce
/// `play()`'s own native acknowledgment latency climbing the longer the
/// phone stays locked (~300ms right after locking to ~600ms after ~8s
/// locked, reset instantly on resume -- morse_icr project memory).
/// Confirmed on-device to make no difference to that latency while
/// adding a real, unwanted audible hum -- reverted back to these
/// original values. That climbing latency is better explained as iOS
/// progressively deprioritizing a backgrounded process's own thread
/// scheduling over time, independent of what audio it happens to be
/// playing.
class KeepAliveAudioLoop {
  // See TurnAudioEngine's matching constructor comment --
  // handleAudioSessionActivation: false avoids this player redundantly
  // reactivating the shared AVAudioSession (which TrainingScreen
  // already owns explicitly) on every play() call.
  KeepAliveAudioLoop({AudioPlayer? player})
    : _player = player ?? AudioPlayer(handleAudioSessionActivation: false);

  AudioPlayer _player;

  static final Uint8List _loopWav = _synthesizeQuietLoop();

  Future<void> start() async {
    // start()/stop() are both called fire-and-forget from TrainingScreen
    // (see its Start/Stop handlers), so a fast Stop-then-Start doesn't
    // guarantee the previous stop() has actually landed natively before
    // this runs. just_audio's native setAudioSource() auto-starts a
    // newly loaded source immediately if its own `playing` flag is
    // still true (AudioPlayer.m:606-720) -- normally harmless here
    // since this method plays anyway, except it would do so at
    // whatever volume/loop mode was left over from before setLoopMode/
    // setVolume below get to run. Pausing first (a no-op if already
    // paused) avoids that.
    await _player.pause();
    // setAudioSource before setLoopMode -- on-device measurement found
    // the reverse order (loop mode set before any source existed) made
    // the final play() call take ~10s to resolve, vs. ~100-300ms for
    // an unlooped source; unconfirmed why, but this ordering matches
    // just_audio's own typical usage pattern.
    logDebug('keepAlive: setAudioSource');
    await _player.setAudioSource(InMemoryAudioSource(_loopWav));
    logDebug('keepAlive: setLoopMode');
    await _player.setLoopMode(LoopMode.one);
    logDebug('keepAlive: setVolume');
    await _player.setVolume(0.02);
    logDebug('keepAlive: play');
    await _player.play();
    logDebug('keepAlive: started');
  }

  Future<void> stop() => _player.stop();

  /// See [TurnAudioEngine.resetPlayer] -- the same just_audio
  /// local-proxy-server staleness applies here too. Callers should
  /// [start] again afterward if the loop should still be running.
  Future<void> resetPlayer() async {
    final old = _player;
    _player = AudioPlayer(handleAudioSessionActivation: false);
    await old.dispose();
  }

  Future<void> dispose() => _player.dispose();

  // Sub-bass frequency and low amplitude/volume: minimally perceptible
  // even without headphones, but genuinely nonzero PCM data (not
  // digital silence) at both the buffer and player-volume level, since
  // that's the detail that matters for iOS to keep counting this as
  // real playback.
  static Uint8List _synthesizeQuietLoop() {
    const sampleRate = 44100;
    const frequencyHz = 20.0;
    const amplitude = 0.05;
    const seconds = 1.0;

    final sampleCount = (sampleRate * seconds).round();
    final samples = Int16List(sampleCount);
    final phaseIncrement = 2 * math.pi * frequencyHz / sampleRate;
    var phase = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final value = amplitude * math.sin(phase);
      samples[i] = (value * 32767).round().clamp(-32768, 32767);
      phase += phaseIncrement;
      if (phase > 2 * math.pi) phase -= 2 * math.pi;
    }
    return pcm16WavBytes(samples, sampleRate: sampleRate);
  }
}
