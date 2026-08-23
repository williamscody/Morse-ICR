/// The Settings screen's preferences (morse_icr_spec.md section 35),
/// persisted across app launches (section 23) alongside the rest of the
/// training configuration.
///
/// Defaults preserve this app's existing behavior from before section 35
/// was implemented -- "." was already spoken as "dot" and "/" as
/// "slash" ([spokenNames]), and the Morse tone was already 600 Hz at a
/// fixed internal amplitude -- so a learner who never opens Settings
/// sees no behavior change.
class AppSettings {
  const AppSettings({
    this.speakPeriodAsDot = true,
    this.speakSlashAsStroke = false,
    this.morsePitchHz = 600,
    this.morseVolumePercent = 60,
    this.voiceVolumePercent = 100,
    this.randomCharacterOrder = true,
  });

  final bool speakPeriodAsDot;
  final bool speakSlashAsStroke;
  final int morsePitchHz;
  final int morseVolumePercent;
  final int voiceVolumePercent;

  /// When false, characters play in the active set's own order instead
  /// of a random draw -- a diagnostic toggle (2026-08-23) for getting a
  /// repeatable, predictable sequence when isolating a recognition
  /// accuracy issue. See [CharacterSelector.randomOrder].
  final bool randomCharacterOrder;

  AppSettings copyWith({
    bool? speakPeriodAsDot,
    bool? speakSlashAsStroke,
    int? morsePitchHz,
    int? morseVolumePercent,
    int? voiceVolumePercent,
    bool? randomCharacterOrder,
  }) => AppSettings(
    speakPeriodAsDot: speakPeriodAsDot ?? this.speakPeriodAsDot,
    speakSlashAsStroke: speakSlashAsStroke ?? this.speakSlashAsStroke,
    morsePitchHz: morsePitchHz ?? this.morsePitchHz,
    morseVolumePercent: morseVolumePercent ?? this.morseVolumePercent,
    voiceVolumePercent: voiceVolumePercent ?? this.voiceVolumePercent,
    randomCharacterOrder: randomCharacterOrder ?? this.randomCharacterOrder,
  );

  Map<String, Object?> toJson() => {
    'speakPeriodAsDot': speakPeriodAsDot,
    'speakSlashAsStroke': speakSlashAsStroke,
    'morsePitchHz': morsePitchHz,
    'morseVolumePercent': morseVolumePercent,
    'voiceVolumePercent': voiceVolumePercent,
    'randomCharacterOrder': randomCharacterOrder,
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
    );
  }
}
