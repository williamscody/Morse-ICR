/// One completed training session (morse_icr_spec.md section 21): what
/// was trained, when, for how long, and at what settings, plus the
/// learner's own notes.
///
/// Deliberately narrower than section 23's full field list where
/// characters attempted/correct/missed are concerned -- those depend on
/// scoring (Milestone 14), which isn't settled yet. [wpm],
/// [recognitionTimeMs], and [extraGapMs] are the values in effect the
/// moment the session *started* -- all three are live-adjustable mid-
/// session (see [TrainingScreen]'s speed/recognition-time/extra-gap
/// controls staying enabled while training), so a single value can't
/// represent the whole session exactly, but the starting settings are
/// what the learner actually chose to train at. [focusSummary] folds
/// together section 23's separate "character set" and "problem-
/// character set" fields into the one value that was actually active
/// for the session, matching how [TrainingScreen] already treats them as
/// mutually exclusive ([TrainingScreen._activeCharacters]) -- and unlike
/// the three settings above, it's read at Stop time since it's locked
/// for the whole session (the character-set chips and Focus button are
/// both disabled while training).
class TrainingSessionRecord {
  const TrainingSessionRecord({
    required this.id,
    required this.startedAt,
    required this.duration,
    required this.focusSummary,
    required this.wpm,
    required this.recognitionTimeMs,
    required this.extraGapMs,
    this.notes = '',
  });

  /// Unique per session -- derived from [startedAt]'s microsecond
  /// timestamp rather than a generated UUID, since this app is
  /// single-threaded and never starts two sessions in the same
  /// microsecond (morse_icr_spec.md section 32: avoid unnecessary
  /// dependencies).
  final String id;

  final DateTime startedAt;

  /// The session's actual elapsed training time (section 22) -- wall-
  /// clock elapsed when manually stopped, or the timer's full configured
  /// duration when it ran to zero (section 22: "If the timer reaches
  /// zero, record the full configured duration").
  final Duration duration;

  /// A human-readable summary of whichever character set or problem-
  /// character list was actually active for this session.
  final String focusSummary;

  /// Character speed (section 5), in WPM, when the session started.
  final int wpm;

  /// Recognition time (section 6), in milliseconds, when the session
  /// started.
  final int recognitionTimeMs;

  /// Extra Gap, in milliseconds, when the session started.
  final int extraGapMs;

  /// The learner's free-form notes for this session (section 21),
  /// editable in place on the log screen; empty until they type
  /// something.
  final String notes;

  TrainingSessionRecord copyWith({String? notes}) => TrainingSessionRecord(
    id: id,
    startedAt: startedAt,
    duration: duration,
    focusSummary: focusSummary,
    wpm: wpm,
    recognitionTimeMs: recognitionTimeMs,
    extraGapMs: extraGapMs,
    notes: notes ?? this.notes,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'focusSummary': focusSummary,
    'wpm': wpm,
    'recognitionTimeMs': recognitionTimeMs,
    'extraGapMs': extraGapMs,
    'notes': notes,
  };

  factory TrainingSessionRecord.fromJson(Map<String, Object?> json) =>
      TrainingSessionRecord(
        id: json['id'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        duration: Duration(milliseconds: json['durationMs'] as int),
        focusSummary: json['focusSummary'] as String,
        wpm: json['wpm'] as int? ?? 0,
        recognitionTimeMs: json['recognitionTimeMs'] as int? ?? 0,
        extraGapMs: json['extraGapMs'] as int? ?? 0,
        notes: json['notes'] as String? ?? '',
      );
}
