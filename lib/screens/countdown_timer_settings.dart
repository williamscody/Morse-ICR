import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;

import '../training/countdown_timer_config.dart';
import '../training/countdown_timer_store.dart';

/// Lets the learner store a duration into each of the three countdown-
/// timer memories, and choose which one (if any) is the active timer
/// (morse_icr_spec.md section 9). Mirrors [ProblemCharacterKeyboard]'s
/// edit-in-place-then-Done flow: every action here -- editing a memory's
/// stored value, or changing the active selection -- only touches this
/// screen's own working copy until Done persists it, so backing out (or
/// tapping Cancel) always leaves the persisted config exactly as it was.
class CountdownTimerSettings extends StatefulWidget {
  const CountdownTimerSettings({super.key, required this.store});

  final CountdownTimerStore store;

  @override
  State<CountdownTimerSettings> createState() =>
      _CountdownTimerSettingsState();
}

class _CountdownTimerSettingsState extends State<CountdownTimerSettings> {
  bool _loaded = false;
  late List<int?> _slotSeconds;
  int? _selectedSlot;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((config) {
      if (!mounted) return;
      setState(() {
        _slotSeconds = List.of(config.slotSeconds);
        _selectedSlot = config.selectedSlot;
        _loaded = true;
      });
    });
  }

  Future<void> _editSlot(int index) async {
    final result = await showDialog<_SlotEditResult>(
      context: context,
      builder: (_) => _SlotEditDialog(
        label: '${index + 1}',
        initialSeconds: _slotSeconds[index] ?? 0,
      ),
    );
    if (result == null) return;
    setState(() {
      _slotSeconds[index] = result.cleared ? null : result.seconds;
      // Clearing the memory currently in use turns the timer off, rather
      // than leaving it selected with nothing to count down from.
      if (result.cleared && _selectedSlot == index) _selectedSlot = null;
    });
  }

  Future<void> _done() async {
    final config = CountdownTimerConfig(
      slotSeconds: _slotSeconds,
      selectedSlot: _selectedSlot,
    );
    await widget.store.save(config);
    if (!mounted) return;
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timer'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
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
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: RadioGroup<int?>(
                    groupValue: _selectedSlot,
                    onChanged: (value) =>
                        setState(() => _selectedSlot = value),
                    child: ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const RadioListTile<int?>(
                          title: Text('Off (no timer)'),
                          value: null,
                        ),
                        for (var i = 0; i < 3; i++)
                          ListTile(
                            // A memory with nothing stored can't be
                            // selected as the active timer -- there's no
                            // duration to count down from.
                            leading: IgnorePointer(
                              ignoring: _slotSeconds[i] == null,
                              child: Opacity(
                                opacity: _slotSeconds[i] == null ? 0.4 : 1,
                                child: Radio<int?>(value: i),
                              ),
                            ),
                            title: Text('Memory ${i + 1}'),
                            subtitle: Text(
                              _slotSeconds[i] == null
                                  ? 'Not set'
                                  : formatCountdown(
                                      Duration(seconds: _slotSeconds[i]!),
                                    ),
                            ),
                            trailing: TextButton(
                              onPressed: () => _editSlot(i),
                              child: const Text('Edit'),
                            ),
                            onTap: _slotSeconds[i] == null
                                ? null
                                : () => setState(() => _selectedSlot = i),
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

class _SlotEditResult {
  const _SlotEditResult({required this.seconds, required this.cleared});

  final int seconds;
  final bool cleared;
}

/// A single memory's minutes/seconds entry (morse_icr_spec.md section 9:
/// "enter... values"), with Clear and Save actions distinct from this
/// screen's own Cancel/Done -- Save only writes into
/// [_CountdownTimerSettingsState]'s working copy, not the persisted
/// store, matching every other edit made here.
class _SlotEditDialog extends StatefulWidget {
  const _SlotEditDialog({required this.label, required this.initialSeconds});

  final String label;
  final int initialSeconds;

  @override
  State<_SlotEditDialog> createState() => _SlotEditDialogState();
}

class _SlotEditDialogState extends State<_SlotEditDialog> {
  // Whole minutes only -- section 9's countdown timers exist to bound a
  // training session, not for second-level precision, and dropping
  // seconds entry keeps this dialog a single control.
  late int _minutes = widget.initialSeconds ~/ 60;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Memory ${widget.label}'),
      // A single compact stepper row, not the full slider-based
      // [SteppedIntControl] used elsewhere -- that control is sized for
      // the main training screen's own layout, and made this one-value
      // dialog needlessly tall (Bill, on-device: "way too big
      // vertically").
      content: _MinutesStepper(
        minutes: _minutes,
        onChanged: (v) => setState(() => _minutes = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(const _SlotEditResult(seconds: 0, cleared: true)),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_SlotEditResult(seconds: _minutes * 60, cleared: false)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A single-row minutes stepper: -/+ buttons flanking a directly-typeable
/// number field, in place of [SteppedIntControl]'s slider-plus-label
/// layout, which was built for the main training screen's own vertical
/// column and reads as excess empty space in a modal dialog holding just
/// one value.
class _MinutesStepper extends StatefulWidget {
  const _MinutesStepper({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  State<_MinutesStepper> createState() => _MinutesStepperState();
}

class _MinutesStepperState extends State<_MinutesStepper> {
  static const _min = 0;
  static const _max = 99;

  late final TextEditingController _controller = TextEditingController(
    text: '${widget.minutes}',
  );

  @override
  void didUpdateWidget(covariant _MinutesStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minutes != widget.minutes &&
        int.tryParse(_controller.text) != widget.minutes) {
      _controller.text = '${widget.minutes}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _set(int value) {
    final clamped = value.clamp(_min, _max);
    widget.onChanged(clamped);
    _controller.text = '$clamped';
  }

  @override
  Widget build(BuildContext context) {
    // Centers horizontally without affecting height: a bare [Center]
    // sizes to fill all the (loosely-bounded, i.e. very tall) space
    // AlertDialog's own content area offers, stretching the whole dialog
    // vertically to match -- confirmed on-device as the cause of a
    // near-full-screen dialog with a single row of controls floating in
    // the middle of it.
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: widget.minutes > _min
                ? () => _set(widget.minutes - 1)
                : null,
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'min',
                border: OutlineInputBorder(),
              ),
              onChanged: (text) {
                final parsed = int.tryParse(text);
                if (parsed != null) {
                  widget.onChanged(parsed.clamp(_min, _max));
                }
              },
            ),
          ),
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: widget.minutes < _max
                ? () => _set(widget.minutes + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
