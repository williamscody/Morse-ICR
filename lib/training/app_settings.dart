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
  });

  final bool speakPeriodAsDot;
  final bool speakSlashAsStroke;
  final int morsePitchHz;
  final int morseVolumePercent;
  final int voiceVolumePercent;

  AppSettings copyWith({
    bool? speakPeriodAsDot,
    bool? speakSlashAsStroke,
    int? morsePitchHz,
    int? morseVolumePercent,
    int? voiceVolumePercent,
  }) => AppSettings(
    speakPeriodAsDot: speakPeriodAsDot ?? this.speakPeriodAsDot,
    speakSlashAsStroke: speakSlashAsStroke ?? this.speakSlashAsStroke,
    morsePitchHz: morsePitchHz ?? this.morsePitchHz,
    morseVolumePercent: morseVolumePercent ?? this.morseVolumePercent,
    voiceVolumePercent: voiceVolumePercent ?? this.voiceVolumePercent,
  );

  Map<String, Object?> toJson() => {
    'speakPeriodAsDot': speakPeriodAsDot,
    'speakSlashAsStroke': speakSlashAsStroke,
    'morsePitchHz': morsePitchHz,
    'morseVolumePercent': morseVolumePercent,
    'voiceVolumePercent': voiceVolumePercent,
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
    );
  }
}
