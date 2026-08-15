import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labeled numeric control combining a slider, +/- step buttons, and a
/// direct numeric-entry field. Shared by Character Speed (WPM) and
/// Recognition Time.
class SteppedIntControl extends StatefulWidget {
  const SteppedIntControl({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.suffix,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String suffix;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  State<SteppedIntControl> createState() => _SteppedIntControlState();
}

class _SteppedIntControlState extends State<SteppedIntControl> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant SteppedIntControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Set right before an explicit unfocus() from _confirmEdit/_cancelEdit so
  // the resulting focus-loss notification doesn't re-run _commitText with
  // logic that's already been handled (or deliberately skipped, for
  // Cancel) by the caller.
  bool _suppressNextFocusLossCommit = false;

  void _onFocusChange() {
    if (_focusNode.hasFocus) return;
    if (_suppressNextFocusLossCommit) {
      _suppressNextFocusLossCommit = false;
      return;
    }
    _commitText();
  }

  void _setValue(int v) {
    widget.onChanged(v.clamp(widget.min, widget.max));
  }

  void _commitText() {
    final parsed = int.tryParse(_controller.text);
    if (parsed == null) {
      _controller.text = '${widget.value}';
      return;
    }
    final clamped = parsed.clamp(widget.min, widget.max);
    _setValue(clamped);
    // Reset to the clamped value we just computed rather than
    // widget.value: the parent's setState hasn't rebuilt this widget
    // yet, so widget.value is still stale at this point.
    _controller.text = '$clamped';
  }

  void _confirmEdit() {
    _commitText();
    _suppressNextFocusLossCommit = true;
    _focusNode.unfocus();
  }

  void _cancelEdit() {
    _controller.text = '${widget.value}';
    _suppressNextFocusLossCommit = true;
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final divisions = ((widget.max - widget.min) / widget.step).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.label}: ${widget.value} ${widget.suffix}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Row(
          children: [
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: widget.enabled
                  ? () => _setValue(widget.value - widget.step)
                  : null,
            ),
            Expanded(
              child: Slider(
                value: widget.value.clamp(widget.min, widget.max).toDouble(),
                min: widget.min.toDouble(),
                max: widget.max.toDouble(),
                divisions: divisions,
                label: '${widget.value} ${widget.suffix}',
                onChanged: widget.enabled
                    ? (v) => _setValue(v.round())
                    : null,
              ),
            ),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: widget.enabled
                  ? () => _setValue(widget.value + widget.step)
                  : null,
            ),
          ],
        ),
        AnimatedBuilder(
          animation: _focusNode,
          builder: (context, _) {
            final isEditing = _focusNode.hasFocus;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: widget.suffix,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _confirmEdit(),
                  ),
                ),
                if (isEditing) ...[
                  IconButton(
                    iconSize: 40,
                    tooltip: 'Done',
                    icon: const Icon(Icons.check_circle, color: Colors.green),
                    onPressed: _confirmEdit,
                  ),
                  IconButton(
                    iconSize: 40,
                    tooltip: 'Cancel',
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: _cancelEdit,
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
