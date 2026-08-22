import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../speech/character_recorder.dart';
import '../speech/enrollment_store.dart';
import '../training/character_set.dart';

/// Lets the learner (re-)enroll their own voice against the full
/// character vocabulary (morse_icr_spec.md section 38): tapping any
/// character immediately records and saves a short clip of them saying
/// it, overwriting whatever was saved before. One interaction covers
/// both first-time enrollment and section 38's re-enrollment
/// requirement ("redoing some or all characters") -- there's no
/// separate mode, since enrolling and re-enrolling a character are the
/// same action.
///
/// Reuses [ProblemCharacterKeyboard]'s `FilterChip` grid over
/// [allCharacters], but selected/filled here means "has a saved
/// recording" rather than a staged multi-select edit -- every tap is
/// already persisted, so unlike that screen there's no Done/Clear step.
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({
    super.key,
    required this.store,
    this.recordClip = recordCharacterClip,
  });

  final EnrollmentStore store;
  final Future<Uint8List> Function() recordClip;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  Set<String> _enrolled = {};
  bool _loaded = false;
  String? _recordingCharacter;

  @override
  void initState() {
    super.initState();
    widget.store.enrolledCharacters().then((characters) {
      if (!mounted) return;
      setState(() {
        _enrolled = characters;
        _loaded = true;
      });
    });
  }

  Future<void> _enroll(String character) async {
    setState(() => _recordingCharacter = character);
    try {
      final clip = await widget.recordClip();
      await widget.store.saveRecording(character, clip);
      if (!mounted) return;
      setState(() => _enrolled = {..._enrolled, character});
    } on MicPermissionDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enrollment needs microphone access -- enable it in Settings.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _recordingCharacter = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Text(
          'Voice\nEnrollment',
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _loaded
                  ? Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final character in allCharacters)
                          FilterChip(
                            label: Text(character),
                            showCheckmark: false,
                            selected: _enrolled.contains(character),
                            avatar: _recordingCharacter == character
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            onSelected: _recordingCharacter == null
                                ? (_) => _enroll(character)
                                : null,
                          ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      ),
    );
  }
}
