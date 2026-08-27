import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../speech/character_player.dart';
import '../speech/character_recorder.dart';
import '../speech/enrollment_store.dart';
import '../speech/response_listener.dart';
import '../speech/speech_to_text_response_listener.dart';
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
    this.playTakes = playCharacterTakes,
    ResponseListener? responseListener,
  }) : _injectedResponseListener = responseListener;

  final EnrollmentStore store;
  final Future<List<Uint8List>> Function(
    int count, {
    void Function(int takeNumber)? onTakeRecorded,
  })
  recordTakes;
  final Future<void> Function(
    List<Uint8List> pcm16Takes, {
    void Function(int takeNumber)? onTakePlaying,
  })
  playTakes;
  // Testable seam for the "Test" mode listener below -- defaults to a
  // real [SpeechToTextResponseListener], the same production listener
  // [TrainingScreen] uses, so Test mode actually exercises what training
  // sessions run on (constructed in [State.initState], not here, so a
  // test that injects its own never pays for a real listener's native
  // speech-recognition setup).
  final ResponseListener? _injectedResponseListener;

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
  String? _playingCharacter;
  int? _playingTakeNumber;
  // Toggled by the "Audition" chip above the grid -- while true, tapping
  // an enrolled character plays its saved takes back instead of
  // re-recording it. A separate mode rather than a small per-chip play
  // icon: Bill found that icon too small a target, with a mis-tap
  // re-enrolling (and so overwriting) the very character he meant to
  // just listen to (2026-08-24 on-device feedback).
  bool _auditionMode = false;
  // Toggled by the "Test" chip -- while true, [_responseListener] runs
  // continuously (the same production recognizer `TrainingScreen` uses,
  // just not gated by a training session), and every character it
  // matches gets outlined below via [_testHighlighted]. Lets the learner
  // speak their way through the vocabulary and immediately see, chip by
  // chip, whether what lights up matches what they actually said -- a
  // live, targeted sanity check for misrecognition without waiting to
  // notice it mid-training-session. [_responseListener] is currently
  // [SpeechToTextResponseListener] (2026-08-26), which needs no
  // enrollment at all -- this still works against [_enrolled]'s DTW-era
  // recordings sitting unused, but nothing here depends on them.
  bool _testMode = false;
  // Every character [_responseListener] has matched since Test mode was
  // last turned on -- additive, not replaced by each new match, so a
  // full pass through the vocabulary leaves a visible record of
  // everything the recognizer actually produced. Cleared when Test mode
  // is turned off (or back on).
  final Set<String> _testHighlighted = {};
  late final ResponseListener _responseListener;

  @override
  void initState() {
    super.initState();
    _responseListener =
        widget._injectedResponseListener ?? SpeechToTextResponseListener();
    widget.store.enrolledCharacters().then((characters) {
      if (!mounted) return;
      setState(() {
        _enrolled = characters;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    if (_testMode) unawaited(_responseListener.stopListening());
    super.dispose();
  }

  Future<void> _setTestMode(bool enabled) async {
    if (enabled) {
      setState(() {
        _testMode = true;
        _testHighlighted.clear();
      });
      await _responseListener.startListening(_handleTestRecognized);
    } else {
      await _responseListener.stopListening();
      if (!mounted) return;
      setState(() {
        _testMode = false;
        _testHighlighted.clear();
      });
    }
  }

  void _handleTestRecognized(String character, {ResponseWindowSnapshot? at}) {
    if (!mounted) return;
    setState(() => _testHighlighted.add(character));
  }

  /// Plays back every saved take of [character] in order -- lets Bill
  /// hear exactly what got enrolled (e.g. checking for a clipped onset)
  /// without needing to pull files off the device by hand.
  Future<void> _audition(String character) async {
    if (_recordingCharacter != null || _playingCharacter != null) return;
    final takes = await widget.store.loadRecordings(character);
    if (!mounted || takes.isEmpty) return;
    setState(() {
      _playingCharacter = character;
      _playingTakeNumber = 1;
    });
    try {
      await widget.playTakes(
        takes,
        onTakePlaying: (takeNumber) {
          if (!mounted) return;
          setState(() => _playingTakeNumber = takeNumber);
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _playingCharacter = null;
          _playingTakeNumber = null;
        });
      }
    }
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
                        if (_playingCharacter != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Playing $_playingCharacter, take '
                              '$_playingTakeNumber of $_takesPerCharacter...',
                            ),
                          )
                        else if (_auditionMode)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Audition mode -- tap an enrolled character '
                              'to hear it back.',
                            ),
                          )
                        else if (_testMode)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Test mode -- speak a character and watch '
                              'which chip outlines.',
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('Audition'),
                                avatar: const Icon(Icons.headphones, size: 18),
                                showCheckmark: false,
                                selected: _auditionMode,
                                onSelected:
                                    _recordingCharacter == null &&
                                        _playingCharacter == null &&
                                        !_testMode
                                    ? (value) =>
                                          setState(() => _auditionMode = value)
                                    : null,
                              ),
                              FilterChip(
                                label: const Text('Test'),
                                avatar: const Icon(Icons.mic, size: 18),
                                showCheckmark: false,
                                selected: _testMode,
                                onSelected:
                                    _recordingCharacter == null &&
                                        _playingCharacter == null &&
                                        !_auditionMode
                                    ? _setTestMode
                                    : null,
                              ),
                            ],
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
                                // Outlines whatever Test mode has
                                // recognized -- layered on top of (not
                                // instead of) the enrolled/selected fill
                                // above, since the two answer different
                                // questions ("is this enrolled at all"
                                // vs. "did the recognizer just hear this
                                // one").
                                side:
                                    _testMode &&
                                        _testHighlighted.contains(character)
                                    ? BorderSide(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.tertiary,
                                        width: 3,
                                      )
                                    : null,
                                avatar:
                                    _recordingCharacter == character ||
                                        _playingCharacter == character
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : null,
                                onSelected:
                                    _recordingCharacter != null ||
                                        _playingCharacter != null ||
                                        _testMode
                                    ? null
                                    : _auditionMode
                                    ? (_enrolled.contains(character)
                                          ? (_) => _audition(character)
                                          : null)
                                    : (_) => _enroll(character),
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
