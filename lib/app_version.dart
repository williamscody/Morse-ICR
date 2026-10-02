/// The app version shown on the Help page's footer -- maintained by hand
/// here, not derived from `pubspec.yaml` at runtime (no
/// `package_info_plus` dependency for a single label). Bump this string
/// only when explicitly asked to (Bill, 2026-08-31); keep it in step
/// with `pubspec.yaml`'s own `version:` field when you do, so the two
/// don't drift apart.
const String appVersion = '1.0.2';

/// This build's number -- the `+N` in `pubspec.yaml`'s `version:` field --
/// compared against the website's manifest by [UpdateChecker] to decide
/// whether a newer build is available. An integer, not [appVersion]'s
/// version string, so that comparison is a single `>` rather than parsing
/// and comparing dotted version strings. Bumped on the same schedule as
/// [appVersion].
const int appBuildNumber = 1;
