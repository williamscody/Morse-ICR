# Local fork notes

This is a local copy of `speech_to_text` 7.4.0 (pub.dev), BSD-3-Clause,
patched for morse_icr and wired in via `dependency_overrides` in the
app's `pubspec.yaml` rather than pulled from pub.dev.

## What's patched

`android/src/main/kotlin/com/csdcorp/speech_to_text/SpeechToTextPlugin.kt`,
`createRecognizer`: upstream reuses the same `SpeechRecognizer` instance
across restarts instead of creating a fresh one each time. Confirmed
on-device (Moto G Play 2024, 2026-09-08/10): that reuse is what causes
`ERROR_CLIENT` on every recognition restart after a session's first
`listen()` call. See `project_android_bluetooth_recognition.md` in
project memory for the full investigation. The patch always destroys
and recreates the recognizer instead of reusing it.

## Maintenance

If `speech_to_text` is ever upgraded, re-apply this same change (search
`createRecognizer` for the early-return reuse check) or re-diff against
a fresh copy of the target version. Drop this fork entirely if upstream
fixes the underlying reuse behavior itself.
