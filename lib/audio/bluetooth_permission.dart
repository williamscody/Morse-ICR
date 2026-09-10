import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('morse_icr/bluetooth_permission');

/// Requests the Android 12+ (API 31+) runtime `BLUETOOTH_CONNECT`
/// permission, best-effort, so package:speech_to_text's own native
/// Kotlin side (SpeechToTextPlugin.kt's optionallyStartBluetooth) can
/// actually switch a connected Bluetooth headset into SCO/voice-
/// recognition mode around each listen session, instead of silently
/// no-opping and leaving Bluetooth mic routing to whatever the OS does
/// by default.
///
/// Investigated on-device (Moto G Play 2024, 2026-09-08): recognition
/// over Bluetooth headphones was wildly unreliable without this --
/// sometimes working with several seconds of delay, sometimes an
/// outright restart-storm (the native recognizer reporting done/
/// notListening within single-digit milliseconds of starting, thousands
/// of times in a row, zero results the entire session).
///
/// A platform `MethodChannel` call into [MainActivity] rather than a
/// dedicated permission package -- same reasoning as
/// [requestNotificationPermissionIfNeeded] in notification_permission.dart.
/// A no-op on iOS and pre-31 Android.
Future<void> requestBluetoothPermissionIfNeeded() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('requestBluetoothPermission');
  } catch (_) {
    // Best-effort -- an unexpected platform failure here shouldn't block
    // starting a training session, same tolerance as the notification
    // permission request this mirrors.
  }
}
