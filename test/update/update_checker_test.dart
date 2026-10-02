import 'package:flutter_test/flutter_test.dart';
import 'package:morse_icr/update/update_checker.dart';

void main() {
  const manifestJson = '''
  {
    "latestVersion": "1.1.0",
    "latestBuildNumber": 5,
    "downloadUrl": "https://example.com/app.apk",
    "releaseNotes": "Bug fixes"
  }
  ''';

  test('checkForUpdate returns the manifest when it is newer', () async {
    final checker = UpdateChecker(
      currentBuildNumber: 3,
      fetch: (_) async => manifestJson,
    );

    final info = await checker.checkForUpdate();

    expect(info, isNotNull);
    expect(info!.latestVersion, '1.1.0');
    expect(info.latestBuildNumber, 5);
    expect(info.downloadUrl, 'https://example.com/app.apk');
    expect(info.releaseNotes, 'Bug fixes');
  });

  test('checkForUpdate returns null when already current', () async {
    final checker = UpdateChecker(
      currentBuildNumber: 5,
      fetch: (_) async => manifestJson,
    );

    expect(await checker.checkForUpdate(), isNull);
  });

  test('checkForUpdate returns null when newer than the manifest', () async {
    final checker = UpdateChecker(
      currentBuildNumber: 9,
      fetch: (_) async => manifestJson,
    );

    expect(await checker.checkForUpdate(), isNull);
  });

  test('checkForUpdate returns null on a network failure', () async {
    final checker = UpdateChecker(
      currentBuildNumber: 1,
      fetch: (_) async => throw Exception('offline'),
    );

    expect(await checker.checkForUpdate(), isNull);
  });

  test('checkForUpdate returns null on a malformed manifest', () async {
    final checker = UpdateChecker(
      currentBuildNumber: 1,
      fetch: (_) async => '{"not": "valid"}',
    );

    expect(await checker.checkForUpdate(), isNull);
  });

  test(
    'fetchLatest throws on a network failure, unlike checkForUpdate',
    () async {
      final checker = UpdateChecker(
        currentBuildNumber: 1,
        fetch: (_) async => throw Exception('offline'),
      );

      expect(checker.fetchLatest(), throwsException);
    },
  );

  test('fetchLatest returns the manifest even when not newer', () async {
    final checker = UpdateChecker(
      currentBuildNumber: 9,
      fetch: (_) async => manifestJson,
    );

    final info = await checker.fetchLatest();
    expect(info.latestBuildNumber, 5);
  });
}
