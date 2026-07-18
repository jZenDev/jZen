// Ported from ../DartZen/packages/dartzen_core/lib/src/dartzen_constants.dart.
// Renamed dz* -> zen* and the DZ_* build defines -> ZEN_*. The donor's GCP/Firestore
// emulator constants (donor lines 20-62: dzGcloudProject, dzFirestoreEmulatorHost,
// dzStorageEmulatorHost, dzIdentityToolkitEmulatorHost) are STRIPPED - Firebase and GCP
// are discarded from jZen (docs/architecture/MANIFESTO.md "What jZen explicitly discards").

/// Environment constants
///
/// These constants are used to determine the current environment (DEV or PRD).
/// They are set via the environment variable ZEN_ENV.
///
/// Client config is compile-time (docs/architecture/STANDARDS.md, TA-7): these
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

/// Maximum number of items to display in the mobile navigation bar.
const int zenMaxItemsMobile = 4;

/// Minimum width for the desktop navigation bar.
const int zenNarrowWidth = 720;
