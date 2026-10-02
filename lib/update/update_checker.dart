import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'update_info.dart';

/// Checks this app's update manifest -- a static JSON file committed to
/// the root of the public `williamscody/Morse-ICR` GitHub repo and
/// served via raw.githubusercontent.com -- for a build newer than the
/// one currently installed.
///
/// This app isn't distributed through Google Play, so there's no store
/// to notify a learner of a new release -- this is that mechanism.
/// GitHub (not Bill's own website, via Publii) hosts the manifest so a
/// routine Publii site publish can never wipe it out from under this
/// check -- Publii's own sync only knows about files it put there
/// itself, and some of its deploy targets delete anything else on the
/// server/bucket during a publish. [TrainingScreen] throttles *when*
/// this gets called (no more than once/day, persisted in
/// [AppSettings]); this class only does the fetch-and-compare, so
/// [HelpScreen]'s manual "Check for Updates" button can reuse it
/// unthrottled.
class UpdateChecker {
  UpdateChecker({
    this.manifestUrl =
        'https://raw.githubusercontent.com/williamscody/Morse-ICR/master/update.json',
    this.currentBuildNumber = appBuildNumber,
    Future<String> Function(Uri uri)? fetch,
  }) : _fetch = fetch ?? _httpGet;

  final String manifestUrl;
  final int currentBuildNumber;
  final Future<String> Function(Uri uri) _fetch;

  static Future<String> _httpGet(Uri uri) async {
    final response = await http.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'update manifest request failed: HTTP ${response.statusCode}',
        uri,
      );
    }
    return response.body;
  }

  /// The newest release described by the manifest, if it's newer than
  /// [currentBuildNumber] -- or null if the app is already current, the
  /// manifest couldn't be reached, or it didn't parse. Every failure
  /// mode returns null rather than throwing: a learner training offline,
  /// or Bill's website being briefly down, should never surface as an
  /// error in this app. Used by the automatic, throttled check
  /// ([TrainingScreen]); the manual "Check for Updates" button
  /// ([HelpScreen]) calls [fetchLatest] directly instead, so it can tell
  /// a learner apart "you're current" from "couldn't reach the server".
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final info = await fetchLatest();
      return info.latestBuildNumber > currentBuildNumber ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// The manifest's release info, regardless of whether it's newer than
  /// [currentBuildNumber] -- throws on any network or parse failure,
  /// unlike [checkForUpdate].
  Future<UpdateInfo> fetchLatest() async {
    final body = await _fetch(Uri.parse(manifestUrl));
    return UpdateInfo.fromJson(jsonDecode(body) as Map<String, Object?>);
  }
}
