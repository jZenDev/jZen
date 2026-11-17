// jZen declares no GCP or Firebase emulator constants: neither is part of the stack
// (docs/architecture/MANIFESTO.md "Boundaries - what jZen is not").

/// Environment constants
///
/// These constants are used to determine the current environment (DEV or PRD).
/// They are set via the environment variable ZEN_ENV.
///
/// Client config is compile-time (docs/architecture/STANDARDS.md): these
/// `String.fromEnvironment` constants combine with conditional imports to tree-shake
/// the wrong platform's code out of each bundle. Do not make them runtime.
///
/// Usage:
/// ```dart
/// if (zenIsDev) {
///   // Development code
/// }
/// ```
const String zenEnv = String.fromEnvironment('ZEN_ENV', defaultValue: 'prd');

/// Whether the current environment is development.
const bool zenIsDev = zenEnv == 'dev';

/// Whether the current environment is production.
const bool zenIsPrd = zenEnv == 'prd';

/// Whether this is a release build (`flutter build --release`, AOT), whatever `ZEN_ENV` says.
const bool zenIsRelease = bool.fromEnvironment('dart.vm.product');

/// Whether this is a development build that is **not** a release build.
///
/// `ZEN_ENV` alone is not enough to tell: `Taskfile.app.yml` defaults it to `dev`, so a release
/// build made without an explicit `ZEN_ENV=prd` has [zenIsDev] true. A release build never counts as
/// a development build, so anything weakened "for development" (the macOS login keychain for the
/// store key and the PIN hash, ADR-087) stays strong in it.
const bool zenIsDevBuild = zenIsDev && !zenIsRelease;

/// Platform constants
///
/// These constants are used to determine the current platform.
/// They are set via the environment variable ZEN_PLATFORM.
///
/// Usage:
/// ```dart
/// if (zenIsMobile) {
///   // Mobile code
/// }
/// ```
const String zenPlatform = String.fromEnvironment('ZEN_PLATFORM');

/// Whether the current platform is Android.
const bool zenIsAndroid = zenPlatform == 'android';

/// Whether the current platform is iOS.
const bool zenIsIOS = zenPlatform == 'ios';

/// Whether the current platform is macOS.
const bool zenIsMacOS = zenPlatform == 'macos';

/// Whether the current platform is Linux.
const bool zenIsLinux = zenPlatform == 'linux';

/// Whether the current platform is Windows.
const bool zenIsWindows = zenPlatform == 'windows';

/// Whether the current platform is Web.
const bool zenIsWeb = zenPlatform == 'web';

/// Whether the current platform is mobile (Android or iOS).
const bool zenIsMobile = zenIsAndroid || zenIsIOS;

/// Whether the current platform is desktop (macOS, Linux, or Windows).
const bool zenIsDesktop = zenIsMacOS || zenIsLinux || zenIsWindows;

/// Whether the current platform is an Apple platform (iOS or macOS).
///
/// The grouping the UI packages branch on to render Cupertino instead of Material. Nothing
/// else spans exactly {iOS, macOS}: [zenIsMobile] puts iOS with Android and [zenIsDesktop]
/// puts macOS with Linux and Windows.
const bool zenIsApplePlatform = zenIsIOS || zenIsMacOS;

/// Maximum number of items to display in the mobile navigation bar.
const int zenMaxItemsMobile = 4;

/// Minimum width for the desktop navigation bar.
const int zenNarrowWidth = 720;
