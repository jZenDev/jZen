# Changelog

## 0.1.0

- Initial release. `ZenCloudKitSync`: `CKSyncEngine` against the user's private database, each
  record end-to-end encrypted in `encryptedValues`; `ZenKeychainStoreKey`: the store's key in the
  Keychain and iOS Data Protection on its directory. iOS 17 and macOS 14 (ADR-065).

## Unreleased

- `ZenKeychainStoreKey` moved to `zen_store_key` as `ZenDeviceStoreKey` (every platform needs it,
  not only Apple's). `protectDirectory` stays here as `ZenDataProtection.protectDirectory` (ADR-075).
