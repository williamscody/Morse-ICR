import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('morse_icr/notification_permission');

/// Requests the Android 13+ (API 33+) runtime `POST_NOTIFICATIONS`
/// permission, best-effort, so the foreground service's Now Playing
/// notification -- the lock-screen/notification-shade card itself -- can
/// actually be shown (section 42, Android background audio). A denial
/// doesn't block training: the foreground service can still run and the
/// session still advances correctly, it just has no visible card.
///
/// A platform `MethodChannel` call into [MainActivity] rather than a
/// dedicated permission package: the only third-party option
/// (`permission_handler`) pulls in a dependency (`permission_handler_android`)
/// that requires `compileSdk 37`, ahead of what this project (and its
/// current Android Gradle Plugin version) supports -- not worth the
/// compileSdk/AGP upgrade for what's otherwise a single native API call,
/// especially alongside the mute/unmute channel [MainActivity] already
/// hand-rolls the same way. A no-op on iOS (never calls the channel at
/// all) and on pre-33 Android (the native side just returns immediately;
/// the permission doesn't exist there, notifications are allowed by
/// default).
Future<void> requestNotificationPermissionIfNeeded() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod<void>('requestNotificationPermission');
  } catch (_) {
    // Best-effort -- an unexpected platform failure here shouldn't block
    // starting a training session, the same "external boundary" tolerance
    // this app already applies to other platform calls (headphone check,
    // audio session reconfigure) around Start.
  }
}
