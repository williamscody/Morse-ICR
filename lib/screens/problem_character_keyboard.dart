import 'package:flutter/material.dart';

import '../training/character_set.dart';
import '../training/problem_character_store.dart';

/// Lets the learner build a problem-character set by tapping characters
/// on and off (morse_icr_spec.md sections 11, 12, 39): one-tap toggle
/// per character, with a visual indication (the same selected-chip
/// styling [TrainingScreen] already uses for its character-set chips) of
/// what's currently in the set. Persists the result via [store] and
/// returns it to the caller once Done is tapped -- [TrainingScreen] is
/// what actually makes it the active training set (section 39's flow
/// step 3), this screen only edits and persists the list itself.
class ProblemCharacterKeyboard extends StatefulWidget {
  const ProblemCharacterKeyboard({super.key, required this.store});

  final ProblemCharacterStore store;

  @override
  State<ProblemCharacterKeyboard> createState() =>
      _ProblemCharacterKeyboardState();
}

class _ProblemCharacterKeyboardState extends State<ProblemCharacterKeyboard> {
  final Set<String> _selected = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Pre-populates the keyboard with whatever was saved last time, so
    // re-opening it to make a small edit doesn't start from a blank
    // slate (section 11: "The user should be able to edit... the list
    // at any time").
    widget.store.load().then((characters) {
      if (!mounted) return;
      setState(() {
        if (characters != null) _selected.addAll(characters);
        _loaded = true;
      });
    });
  }

  Future<void> _done() async {
    // [allCharacters]' own order, not selection order, so the
    // persisted/returned list is always in a stable, predictable order
    // regardless of which order the learner tapped characters in. Saved
    // (and returned) even when empty -- Clear-then-Done is how the
    // learner explicitly clears the problem-character set entirely,
    // not just for the rest of this session (on-device testing:
    // treating an empty Done as a plain cancel left Clear looking
    // broken, since neither the persisted list nor TrainingScreen's own
    // active-count indicator ever actually changed). [TrainingScreen]
    // is what turns an empty list back into "no problem set active."
    final characters = [
      for (final character in allCharacters)
        if (_selected.contains(character)) character,
    ];
    await widget.store.save(characters);
    if (!mounted) return;
    Navigator.of(context).pop(characters);
  }

  void _clear() {
    setState(() => _selected.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Default AppBar title is single-line-ellipsis; taller toolbar
        // plus an explicit line count gives "Problem Characters" room to
        // wrap instead of truncating to "Problem C..." (Bill, on-device).
        toolbarHeight: 72,
        title: const Text(
          'Problem\nCharacters',
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
        actions: [
          TextButton(
            onPressed: _loaded ? _clear : null,
            child: const Text('Clear'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _loaded ? _done : null,
              child: const Text('Done'),
            ),
          ),
        ],
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
                            selected: _selected.contains(character),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selected.add(character);
                                } else {
                                  _selected.remove(character);
                                }
                              });
                            },
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
