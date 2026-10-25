/// jZen Store CloudKit - CloudKit sync, the Keychain key and Data Protection for a light jZen
/// application on iOS 17 and macOS 14.
///
/// - [ZenCloudKitSync]: the `ZenSyncTransport` a release build uses
/// - [ZenKeychainStoreKey]: the store's key in the Keychain, and Data Protection on its directory
///
/// See docs/architecture/DECISIONS.md ADR-065.
library;

export 'src/zen_cloudkit_sync.dart';
export 'src/zen_keychain_store_key.dart';
