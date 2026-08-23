import 'package:record/record.dart';

/// Selects the phone's own built-in microphone as [RecordConfig]'s
/// `device`, overriding iOS's default preference for a connected
/// Bluetooth accessory's mic once one is connected.
///
/// `record`'s default iOS category options (`allowBluetooth`/
/// `allowBluetoothA2DP`, both still left on here -- see
/// [character_recorder.dart] and [voice_response_listener.dart]'s
/// callers) let iOS silently route *recording* through a connected
/// headset's hands-free (HFP) mic once one is connected, which is much
/// lower fidelity (narrowband, mono, lossy codec) than the phone's own
/// mic array -- while *playback* stays full quality on a separate
/// stereo profile, so nothing about the listening experience hints
/// anything changed. Traced (2026-08-23) as the likely cause of
/// intermittent garbage/high-distance match results once Bill started
/// testing with AirPods connected: leaving Bluetooth allowed for output
/// (headphones are required -- see [hasNonSpeakerAudioOutput]'s own
/// doc comment on the self-hearing problem they prevent) while pinning
/// *input* specifically to the built-in mic keeps both properties.
///
/// Returns null (falling back to `record`'s own default: whatever
/// device iOS currently prefers) if no built-in device is reported --
/// e.g. platforms that don't expose per-device types at all.
Future<InputDevice?> preferredInputDevice(AudioRecorder recorder) async {
  final devices = await recorder.listInputDevices();
  for (final device in devices) {
    if (device.type == InputDeviceType.builtIn) return device;
  }
  return null;
}
