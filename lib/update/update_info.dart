/// One release as described by the website's update manifest (see
/// [UpdateChecker]) -- the fields this app actually needs to tell a
/// learner "a newer build exists" and send them to get it.
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.downloadUrl,
    this.releaseNotes = '',
  });

  /// Human-readable version string (e.g. "1.0.3") -- display only, never
  /// compared against; [latestBuildNumber] is what decides "is this
  /// newer".
  final String latestVersion;
  final int latestBuildNumber;
  final String downloadUrl;
  final String releaseNotes;

  /// Parses the manifest's JSON, throwing a [FormatException] if a
  /// required field is missing or the wrong type -- [UpdateChecker]
  /// treats any parse failure the same as a network failure (silently
  /// skip this check), so this is deliberately strict rather than
  /// filling in guessed defaults for a malformed manifest.
  factory UpdateInfo.fromJson(Map<String, Object?> json) {
    final latestVersion = json['latestVersion'];
    final latestBuildNumber = json['latestBuildNumber'];
    final downloadUrl = json['downloadUrl'];
    if (latestVersion is! String ||
        latestBuildNumber is! int ||
        downloadUrl is! String) {
      throw const FormatException(
        'update manifest missing required fields '
        '(latestVersion, latestBuildNumber, downloadUrl)',
      );
    }
    return UpdateInfo(
      latestVersion: latestVersion,
      latestBuildNumber: latestBuildNumber,
      downloadUrl: downloadUrl,
      releaseNotes: json['releaseNotes'] as String? ?? '',
    );
  }
}
