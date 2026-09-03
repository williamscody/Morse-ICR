/// The Settings screen's preferences (morse_icr_spec.md section 35), plus
/// the main training screen's own live-adjustable controls (Character
/// Speed, Recognition Time, Extra Gap, Character Set, Voice, Speech
/// Recognition), persisted across app launches (section 23) alongside the
/// rest of the training configuration -- 2026-08-30: previously only the
/// Settings-screen preferences survived a force quit; on-device testing
/// found the main screen silently reverting to hardcoded defaults every
/// cold launch was itself read as a bug by Bill ("persist ALL app
/// settings"), not just the ones already covered here.
///
/// Defaults preserve this app's existing behavior from before section 35
/// was implemented -- "." was already spoken as "dot" and "/" as
/// "slash" ([spokenNames]), and the Morse tone was already 600 Hz at a
/// fixed internal amplitude -- so a learner who never opens Settings
/// sees no behavior change. The newer fields below default to
/// [TrainingScreen]'s own previous hardcoded initial values, for the same
/// reason.
class AppSettings {
  const AppSettings({
    this.speakPeriodAsDot = true,
    this.speakSlashAsStroke = false,
    this.morsePitchHz = 600,
    this.morseVolumePercent = 60,
    this.voiceVolumePercent = 100,
    this.randomCharacterOrder = true,
    this.characterSpeedWpm = 90,
    this.recognitionTimeMs = 500,
    this.extraGapMs = 0,
    this.selectedCharacterSetNames = const ['letters'],
    this.voiceEnabled = true,
    this.recognitionEnabled = true,
    this.selectedVoiceName = '',
    this.selectedVoiceLocale = '',
  });

  final bool speakPeriodAsDot;
  final bool speakSlashAsStroke;
  final int morsePitchHz;
  final int morseVolumePercent;
  final int voiceVolumePercent;

  /// Section 35's "Voice" picker -- empty means "auto" (see
  /// [TtsAnswerSpeaker._bestAvailableVoice]), the default for a learner
  /// who's never opened this setting. A plain empty string rather than
  /// `null` so this stays a non-nullable field like every other setting
  /// here, avoiding the "explicit null" `copyWith` problem that would
  /// otherwise come with letting a learner pick "Auto" again after
  /// having picked something else.
  final String selectedVoiceName;
  final String selectedVoiceLocale;

  /// When false, characters play in the active set's own order instead
  /// of a random draw -- a diagnostic toggle (2026-08-23) for getting a
  /// repeatable, predictable sequence when isolating a recognition
  /// accuracy issue. See [CharacterSelector.randomOrder].
  final bool randomCharacterOrder;

  final int characterSpeedWpm;
  final int recognitionTimeMs;
  final int extraGapMs;

  /// [CharacterSetType.name] values for whichever character-set chips
  /// are checked on the main screen -- stored by name (not index) so a
  /// future reordering of the enum doesn't silently remap a learner's
  /// saved selection to the wrong set.
  final List<String> selectedCharacterSetNames;
  final bool voiceEnabled;
  final bool recognitionEnabled;

  AppSettings copyWith({
    bool? speakPeriodAsDot,
    bool? speakSlashAsStroke,
    int? morsePitchHz,
    int? morseVolumePercent,
    int? voiceVolumePercent,
    bool? randomCharacterOrder,
    int? characterSpeedWpm,
    int? recognitionTimeMs,
    int? extraGapMs,
    List<String>? selectedCharacterSetNames,
    bool? voiceEnabled,
    bool? recognitionEnabled,
    String? selectedVoiceName,
    String? selectedVoiceLocale,
  }) => AppSettings(
    speakPeriodAsDot: speakPeriodAsDot ?? this.speakPeriodAsDot,
    speakSlashAsStroke: speakSlashAsStroke ?? this.speakSlashAsStroke,
    morsePitchHz: morsePitchHz ?? this.morsePitchHz,
    morseVolumePercent: morseVolumePercent ?? this.morseVolumePercent,
    voiceVolumePercent: voiceVolumePercent ?? this.voiceVolumePercent,
    randomCharacterOrder: randomCharacterOrder ?? this.randomCharacterOrder,
    characterSpeedWpm: characterSpeedWpm ?? this.characterSpeedWpm,
    recognitionTimeMs: recognitionTimeMs ?? this.recognitionTimeMs,
    extraGapMs: extraGapMs ?? this.extraGapMs,
    selectedCharacterSetNames:
        selectedCharacterSetNames ?? this.selectedCharacterSetNames,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    recognitionEnabled: recognitionEnabled ?? this.recognitionEnabled,
    selectedVoiceName: selectedVoiceName ?? this.selectedVoiceName,
    selectedVoiceLocale: selectedVoiceLocale ?? this.selectedVoiceLocale,
  );

  Map<String, Object?> toJson() => {
    'speakPeriodAsDot': speakPeriodAsDot,
    'speakSlashAsStroke': speakSlashAsStroke,
    'morsePitchHz': morsePitchHz,
    'morseVolumePercent': morseVolumePercent,
    'voiceVolumePercent': voiceVolumePercent,
    'randomCharacterOrder': randomCharacterOrder,
    'characterSpeedWpm': characterSpeedWpm,
    'recognitionTimeMs': recognitionTimeMs,
    'extraGapMs': extraGapMs,
    'selectedCharacterSetNames': selectedCharacterSetNames,
    'voiceEnabled': voiceEnabled,
    'recognitionEnabled': recognitionEnabled,
    'selectedVoiceName': selectedVoiceName,
    'selectedVoiceLocale': selectedVoiceLocale,
  };

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const defaults = AppSettings();
    return AppSettings(
      speakPeriodAsDot:
          json['speakPeriodAsDot'] as bool? ?? defaults.speakPeriodAsDot,
      speakSlashAsStroke:
          json['speakSlashAsStroke'] as bool? ?? defaults.speakSlashAsStroke,
      morsePitchHz: json['morsePitchHz'] as int? ?? defaults.morsePitchHz,
      morseVolumePercent:
          json['morseVolumePercent'] as int? ?? defaults.morseVolumePercent,
      voiceVolumePercent:
          json['voiceVolumePercent'] as int? ?? defaults.voiceVolumePercent,
      randomCharacterOrder:
          json['randomCharacterOrder'] as bool? ??
          defaults.randomCharacterOrder,
      characterSpeedWpm:
          json['characterSpeedWpm'] as int? ?? defaults.characterSpeedWpm,
      recognitionTimeMs:
          json['recognitionTimeMs'] as int? ?? defaults.recognitionTimeMs,
      extraGapMs: json['extraGapMs'] as int? ?? defaults.extraGapMs,
      selectedCharacterSetNames:
          (json['selectedCharacterSetNames'] as List?)?.cast<String>() ??
          defaults.selectedCharacterSetNames,
      voiceEnabled: json['voiceEnabled'] as bool? ?? defaults.voiceEnabled,
      recognitionEnabled:
          json['recognitionEnabled'] as bool? ?? defaults.recognitionEnabled,
      selectedVoiceName:
          json['selectedVoiceName'] as String? ?? defaults.selectedVoiceName,
      selectedVoiceLocale:
          json['selectedVoiceLocale'] as String? ??
          defaults.selectedVoiceLocale,
    );
  }
}
