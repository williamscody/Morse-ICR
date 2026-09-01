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

  // Shrinks a widget's Material tap-target padding a bit below Material's
  // default 48x48 minimum -- still comfortably tappable, but keeps a
  // 3-control card compact enough to fit one screen without scrolling
  // (Bill, 2026-08-31).
  static const _tightTapTarget = VisualDensity(horizontal: -2, vertical: -2);

  // Breathing room between the slider and the +/- buttons, which also
  // shortens the slider track at each end so fingers near the ends of the
  // track don't land on a button.
  static const _sliderGap = 20.0;

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
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              visualDensity: _tightTapTarget,
              iconSize: 26,
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: widget.enabled
                  ? () => _setValue(widget.value - widget.step)
                  : null,
            ),
            const SizedBox(width: _sliderGap),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(
                  context,
                ).copyWith(trackHeight: 3, padding: EdgeInsets.zero),
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
            ),
            const SizedBox(width: _sliderGap),
            IconButton(
              visualDensity: _tightTapTarget,
              iconSize: 26,
              icon: const Icon(Icons.add_circle_outline),
              onPressed: widget.enabled
                  ? () => _setValue(widget.value + widget.step)
                  : null,
            ),
            const SizedBox(width: 6),
            Container(
              width: 60,
              height: 45,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              // The border is drawn by this Container rather than the
              // TextField's own InputDecoration, and the decoration below
              // is fully collapsed (no reserved label/helper space) --
              // that way this Container's `alignment: Alignment.center`
              // is the only thing controlling vertical position, instead
              // of fighting InputDecorator's own padding math.
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                style: Theme.of(context).textTheme.bodyMedium,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onSubmitted: (_) => _confirmEdit(),
              ),
            ),
            AnimatedBuilder(
              animation: _focusNode,
              builder: (context, _) {
                if (!_focusNode.hasFocus) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: _tightTapTarget,
                      iconSize: 32,
                      tooltip: 'Cancel',
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: _cancelEdit,
                    ),
                    IconButton(
                      visualDensity: _tightTapTarget,
                      iconSize: 32,
                      tooltip: 'Done',
                      icon: const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                      onPressed: _confirmEdit,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}
