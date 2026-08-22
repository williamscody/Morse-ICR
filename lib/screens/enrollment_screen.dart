import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../speech/character_recorder.dart';
import '../speech/enrollment_store.dart';
import '../training/character_set.dart';

/// Lets the learner (re-)enroll their own voice against the full
/// character vocabulary (morse_icr_spec.md section 38): tapping any
/// character immediately records [_takesPerCharacter] takes of them
/// saying it and saves all of them, overwriting whatever was saved
/// before. One interaction covers both first-time enrollment and
/// section 38's re-enrollment requirement ("redoing some or all
/// characters") -- there's no separate mode, since enrolling and
/// re-enrolling a character are the same action. User-facing as
/// "Personalize Recognition" (Settings' entry point to this screen).
///
/// Reuses [ProblemCharacterKeyboard]'s `FilterChip` grid over
/// [allCharacters], but selected/filled here means "has saved
/// recordings" rather than a staged multi-select edit -- every tap is
/// already persisted, so unlike that screen there's no Done/Clear step.
class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({
    super.key,
    required this.store,
    this.recordTakes = recordCharacterTakes,
  });

  final EnrollmentStore store;
  final Future<List<Uint8List>> Function(
    int count, {
    void Function(int takeNumber)? onTakeRecorded,
  })
  recordTakes;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

/// How many separate takes each character records on every (re-)enroll
/// -- an explicit placeholder like every other threshold in the speech
/// pipeline, not tuned. Added (Milestone 13, 2026-08-22) after on-device
/// data showed a single take made matching sensitive to that one
/// recording's own noise rather than the character's actual acoustic
/// signature; [VoiceCharacterMatcher] keeps whichever enrolled take a
/// query is closest to.
const _takesPerCharacter = 3;

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  Set<String> _enrolled = {};
  bool _loaded = false;
  String? _recordingCharacter;
  int? _recordingTakeNumber;

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
    setState(() {
      _recordingCharacter = character;
      _recordingTakeNumber = 1;
    });
    try {
      // All-or-nothing: nothing is saved for [character] unless every
      // take succeeds, so a failure partway through never leaves a
      // previous enrollment silently replaced by a partial one.
      final takes = await widget.recordTakes(
        _takesPerCharacter,
        onTakeRecorded: (takeNumber) {
          // Clamped so the very last take's completion (e.g. 3 of 3)
          // never briefly displays as "take 4 of 3" while
          // saveRecordings is still in flight below.
          if (!mounted) return;
          setState(() {
            _recordingTakeNumber = takeNumber < _takesPerCharacter
                ? takeNumber + 1
                : takeNumber;
          });
        },
      );
      await widget.store.saveRecordings(character, takes);
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
    } on NoSpeechDetected {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Didn't catch that -- speak right after tapping, then try again.",
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _recordingCharacter = null;
          _recordingTakeNumber = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Text(
          'Personalize\nRecognition',
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
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Each character now records _takesPerCharacter
                        // separate takes per tap -- up to 40 characters
                        // x 3 takes is a lot of back-to-back utterances,
                        // so this tells Bill where he is in that
                        // sequence rather than leaving him to guess from
                        // the chip's small spinner alone.
                        if (_recordingCharacter != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Recording $_recordingCharacter, take '
                              '$_recordingTakeNumber of $_takesPerCharacter...',
                            ),
                          ),
                        Wrap(
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
