import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/training/app_settings.dart';

void main() {
  test('defaults preserve the app\'s pre-section-35 behavior', () {
    const settings = AppSettings();

    expect(settings.speakPeriodAsDot, isTrue);
    expect(settings.speakSlashAsStroke, isFalse);
    expect(settings.morsePitchHz, 600);
    expect(settings.morseVolumePercent, 60);
    expect(settings.voiceVolumePercent, 100);
  });

  test('toJson/fromJson round-trips every field', () {
    const settings = AppSettings(
      speakPeriodAsDot: false,
      speakSlashAsStroke: true,
      morsePitchHz: 750,
      morseVolumePercent: 40,
      voiceVolumePercent: 85,
    );

    final roundTripped = AppSettings.fromJson(settings.toJson());

    expect(roundTripped.speakPeriodAsDot, settings.speakPeriodAsDot);
    expect(roundTripped.speakSlashAsStroke, settings.speakSlashAsStroke);
    expect(roundTripped.morsePitchHz, settings.morsePitchHz);
    expect(roundTripped.morseVolumePercent, settings.morseVolumePercent);
    expect(roundTripped.voiceVolumePercent, settings.voiceVolumePercent);
  });

  test('fromJson falls back to defaults for missing fields -- settings '
      'saved before a later field was added', () {
    final settings = AppSettings.fromJson({'speakPeriodAsDot': false});

    expect(settings.speakPeriodAsDot, isFalse);
    expect(settings.speakSlashAsStroke, isFalse);
    expect(settings.morsePitchHz, 600);
    expect(settings.morseVolumePercent, 60);
    expect(settings.voiceVolumePercent, 100);
  });

  test('copyWith replaces only the given fields', () {
    const settings = AppSettings();

    final updated = settings.copyWith(morsePitchHz: 800);

    expect(updated.morsePitchHz, 800);
    expect(updated.speakPeriodAsDot, settings.speakPeriodAsDot);
    expect(updated.speakSlashAsStroke, settings.speakSlashAsStroke);
    expect(updated.morseVolumePercent, settings.morseVolumePercent);
    expect(updated.voiceVolumePercent, settings.voiceVolumePercent);
  });
}
