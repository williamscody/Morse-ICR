/// One installed text-to-speech voice, as [TtsAnswerSpeaker] reports it --
/// a plain value type (no `flutter_tts` types) so [SettingsScreen] can
/// list/select from these without depending on the concrete TTS engine
/// (morse_icr_spec.md section 35's "Voice" picker, added 2026-09-02 after
/// [TtsAnswerSpeaker] was found to always self-select a voice regardless
/// of the learner's own iOS Accessibility > Spoken Content choice).
class TtsVoiceOption {
  const TtsVoiceOption({
    required this.name,
    required this.locale,
    required this.quality,
  });

  final String name;
  final String locale;

  /// `flutter_tts`'s own lowercase quality string -- `'default'`,
  /// `'enhanced'`, or `'premium'`.
  final String quality;

  @override
  bool operator ==(Object other) =>
      other is TtsVoiceOption &&
      other.name == name &&
      other.locale == locale &&
      other.quality == quality;

  @override
  int get hashCode => Object.hash(name, locale, quality);
}
