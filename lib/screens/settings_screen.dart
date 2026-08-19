import 'package:flutter/material.dart';

/// Settings previously inline on [TrainingScreen]'s main form, moved
/// here to keep that screen focused on the training controls
/// themselves. Local switch state mirrors [voiceEnabled]/
/// [recognitionEnabled] so this screen renders correctly the moment
/// it's pushed, but every toggle is reported back via
/// [onVoiceChanged]/[onRecognitionChanged] so [TrainingScreen] -- which
/// still owns the real setting and any live session it affects --
/// stays the source of truth.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.voiceEnabled,
    required this.voicePreparing,
    required this.recognitionEnabled,
    required this.onVoiceChanged,
    required this.onRecognitionChanged,
  });

  final bool voiceEnabled;
  final bool voicePreparing;
  final bool recognitionEnabled;
  final ValueChanged<bool> onVoiceChanged;
  final ValueChanged<bool> onRecognitionChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _voiceEnabled = widget.voiceEnabled;
  late bool _recognitionEnabled = widget.recognitionEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Voice',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Switch(
                        value: _voiceEnabled,
                        onChanged: (value) {
                          setState(() => _voiceEnabled = value);
                          widget.onVoiceChanged(value);
                        },
                      ),
                    ],
                  ),
                  if (widget.voicePreparing) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Preparing voice…',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Speech Recognition',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Switch(
                        value: _recognitionEnabled,
                        onChanged: (value) {
                          setState(() => _recognitionEnabled = value);
                          widget.onRecognitionChanged(value);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
