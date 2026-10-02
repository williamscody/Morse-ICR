import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/update/update_info.dart';

void main() {
  test('fromJson reads every field', () {
    final info = UpdateInfo.fromJson({
      'latestVersion': '1.0.3',
      'latestBuildNumber': 4,
      'downloadUrl': 'https://example.com/app.apk',
      'releaseNotes': 'Adds things',
    });

    expect(info.latestVersion, '1.0.3');
    expect(info.latestBuildNumber, 4);
    expect(info.downloadUrl, 'https://example.com/app.apk');
    expect(info.releaseNotes, 'Adds things');
  });

  test('fromJson defaults releaseNotes to empty when absent', () {
    final info = UpdateInfo.fromJson({
      'latestVersion': '1.0.3',
      'latestBuildNumber': 4,
      'downloadUrl': 'https://example.com/app.apk',
    });

    expect(info.releaseNotes, '');
  });

  test('fromJson throws when a required field is missing', () {
    expect(
      () => UpdateInfo.fromJson({
        'latestVersion': '1.0.3',
        'downloadUrl': 'https://example.com/app.apk',
      }),
      throwsFormatException,
    );
  });

  test('fromJson throws when a required field has the wrong type', () {
    expect(
      () => UpdateInfo.fromJson({
        'latestVersion': '1.0.3',
        'latestBuildNumber': '4',
        'downloadUrl': 'https://example.com/app.apk',
      }),
      throwsFormatException,
    );
  });
}
