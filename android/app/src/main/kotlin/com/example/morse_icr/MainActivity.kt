package com.example.morse_icr

import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Android's on-device SpeechRecognizer service plays its own per-utterance
// earcon -- there is no public RecognizerIntent extra to suppress it, since
// the sound comes from Google's recognition service, not from this app.
// STREAM_MUSIC was tried first and ruled out: `adb shell dumpsys audio`
// confirmed the app's own just_audio playback is also on STREAM_MUSIC, so
// muting it silenced this app's Morse tone/TTS voice for the whole
// listening session without actually stopping the chime -- meaning the
// earcon isn't on that stream at all. STREAM_NOTIFICATION is confirmed
// (same dumpsys output) to NOT alias to STREAM_MUSIC, so it can't touch
// this app's own audio (Bill reported the chime 2026-08-27; first fix
// attempt regressed voice output the same day, this is the retry).
private const val RECOGNITION_SOUND_CHANNEL = "morse_icr/recognition_sound"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECOGNITION_SOUND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "mute" -> {
                    audioManager.adjustStreamVolume(
                        AudioManager.STREAM_NOTIFICATION,
                        AudioManager.ADJUST_MUTE,
                        0,
                    )
                    result.success(null)
                }
                "unmute" -> {
                    audioManager.adjustStreamVolume(
                        AudioManager.STREAM_NOTIFICATION,
                        AudioManager.ADJUST_UNMUTE,
                        0,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
