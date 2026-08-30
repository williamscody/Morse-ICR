package com.example.morse_icr

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioServiceActivity
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

// Matches notification_permission.dart's own channel name and single
// method -- the POST_NOTIFICATIONS runtime permission (Android 13+/API
// 33+) the foreground service's Now Playing notification needs to
// actually be visible (section 42, Android background audio). No
// dedicated permission package: the only third-party option
// (permission_handler) requires compileSdk 37, ahead of what this
// project's Android Gradle Plugin version supports, not worth a Gradle
// upgrade for what's otherwise one native API call -- same reasoning as
// hand-rolling the mute/unmute channel below rather than pulling in a
// package for that.
private const val NOTIFICATION_PERMISSION_CHANNEL = "morse_icr/notification_permission"

// AudioServiceActivity (a thin FlutterActivity subclass from
// package:audio_service) points this activity at the same FlutterEngine
// audio_service's own foreground service hosts, rather than creating a
// fresh one -- that shared engine is what keeps TrainingEngine's Dart
// Timers (turn-to-turn advancement, response-window scoring) running once
// this Activity itself is torn down by the screen locking or the app
// backgrounding (section 42, Android background audio).
class MainActivity : AudioServiceActivity() {
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_PERMISSION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    // The permission doesn't exist before API 33 --
                    // notifications are allowed by default there, nothing
                    // to request.
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        val alreadyGranted = ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!alreadyGranted) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                0,
                            )
                        }
                    }
                    // Fire-and-forget on the Dart side (best-effort,
                    // doesn't gate anything on the outcome) -- succeed
                    // immediately rather than waiting on
                    // onRequestPermissionsResult for a grant/denial this
                    // caller doesn't act on either way.
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
