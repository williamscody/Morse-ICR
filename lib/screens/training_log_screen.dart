import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../training/training_log_formatting.dart';
import '../training/training_log_store.dart';
import '../training/training_session_record.dart';

/// The training log (morse_icr_spec.md section 21): every completed
/// session's date, time, duration, and active character set/problem-
/// character summary, each learner-editable with free-form notes,
/// cumulative training time, a Clear action (with confirmation), and a
/// CSV Export via the OS share sheet.
class TrainingLogScreen extends StatefulWidget {
  /// [exportCsv] lets tests substitute a fake so they don't have to
  /// exercise the real `share_plus` platform channel, which -- like
  /// other unmocked plugin channels in this project (see
  /// [TrainingScreen]'s own doc comment) -- has no channel mock
  /// registered under `flutter test`; production code always omits it
  /// and gets [_shareCsvFile], which writes the CSV to a temp file (via
  /// `path_provider`) and hands it to the OS share sheet.
  const TrainingLogScreen({
    super.key,
    required this.store,
    Future<void> Function(String csv, Rect? sharePositionOrigin)? exportCsv,
  }) : _exportCsv = exportCsv ?? _shareCsvFile;

  final TrainingLogStore store;
  final Future<void> Function(String csv, Rect? sharePositionOrigin)
  _exportCsv;

  @override
  State<TrainingLogScreen> createState() => _TrainingLogScreenState();
}

Future<void> _shareCsvFile(String csv, Rect? sharePositionOrigin) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/training_log.csv');
  await file.writeAsString(csv);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path)],
      fileNameOverrides: const ['training_log.csv'],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

class _TrainingLogScreenState extends State<TrainingLogScreen> {
  bool _loaded = false;
  // Oldest first -- the same order [TrainingLogStore] persists in.
  // [build] reverses only for display (section 21's "Recent sessions"
  // reads naturally newest-first).
  List<TrainingSessionRecord> _records = [];

  @override
  void initState() {
    super.initState();
    widget.store.load().then((records) {
      if (!mounted) return;
      setState(() {
        _records = records;
        _loaded = true;
      });
    });
  }

  // Section 21: "Cumulative time should be calculated from recorded
  // session durations rather than being a manually maintained counter."
  Duration get _totalDuration =>
      _records.fold(Duration.zero, (sum, record) => sum + record.duration);

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear training log?'),
        content: const Text(
          'This permanently deletes every recorded session. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.save(const []);
    if (!mounted) return;
    setState(() => _records = []);
  }

  Future<void> _export(BuildContext context) async {
    // Anchors the iPad/Mac popover to the Export button itself, rather
    // than the default center-of-screen fallback (see
    // ShareParams.sharePositionOrigin).
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox != null
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
    await widget._exportCsv(buildTrainingLogCsv(_records), origin);
  }

  Future<void> _updateNotes(int index, String notes) async {
    setState(() {
      _records = [
        for (var i = 0; i < _records.length; i++)
          i == index ? _records[i].copyWith(notes: notes) : _records[i],
      ];
    });
    await widget.store.save(_records);
  }

  @override
  Widget build(BuildContext context) {
    final displayOrder = _records.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training Log'),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export',
              onPressed: _records.isEmpty ? null : () => _export(context),
            ),
          ),
          TextButton(
            onPressed: _records.isEmpty ? null : () => _clear(context),
            child: const Text('Clear'),
          ),
        ],
      ),
      body: SafeArea(
        child: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Total Time: ${formatSessionDuration(_totalDuration)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    child: _records.isEmpty
                        ? const Center(
                            child: Text('No training sessions recorded yet.'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: displayOrder.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 32),
                            itemBuilder: (context, i) {
                              final record = displayOrder[i];
                              // [displayOrder] is [_records] reversed, so
                              // this maps a display position back to its
                              // real index in the storage-order list.
                              final storageIndex = _records.length - 1 - i;
                              return _SessionRow(
                                key: ValueKey(record.id),
                                record: record,
                                onNotesChanged: (notes) =>
                                    _updateNotes(storageIndex, notes),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required super.key,
    required this.record,
    required this.onNotesChanged,
  });

  final TrainingSessionRecord record;
  final ValueChanged<String> onNotesChanged;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  late final TextEditingController _notesController = TextEditingController(
    text: widget.record.notes,
  );
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChange);

  // Commits on blur/submit, not per-keystroke -- matches
  // [SteppedIntControl]'s own commit-on-blur convention and avoids
  // writing the log file to disk on every character typed.
  void _onFocusChange() {
    if (_focusNode.hasFocus) return;
    widget.onNotesChanged(_notesController.text);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Cell('Date', formatSessionDate(record.startedAt)),
            _Cell('Time', formatSessionTime(record.startedAt)),
            _Cell('Duration', formatSessionDuration(record.duration)),
          ],
        ),
        const SizedBox(height: 8),
        // Its own row, full-width -- a long character-set focus summary
        // squeezed into the Date/Time/Duration row above pushed those
        // cells together until they visually collided (Bill, on-device,
        // after seeing several problem characters selected at once).
        _Cell('Focus', record.focusSummary),
        const SizedBox(height: 8),
        // A second row for the settings the session started at (too
        // crowded to fit alongside Date/Time/Duration/Focus in one row --
        // Bill, on-device, after seeing the first cut).
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Cell('WPM', '${record.wpm}'),
            _Cell('Recognition', '${record.recognitionTimeMs} ms'),
            _Cell('Gap', '${record.extraGapMs} ms'),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notesController,
          focusNode: _focusNode,
          decoration: const InputDecoration(
            labelText: 'Notes',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onSubmitted: widget.onNotesChanged,
        ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
