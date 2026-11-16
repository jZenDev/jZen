# Changelog

## 0.1.0

- Initial release. `ZenCloudKitSync`: `CKSyncEngine` against the user's private database, each
  record end-to-end encrypted in `encryptedValues`; `ZenKeychainStoreKey`: the store's key in the
  Keychain and iOS Data Protection on its directory. iOS 17 and macOS 14 (ADR-065).

## Unreleased

- Record names are an HMAC of `<collection>:<id>` under a key in a synchronizable Keychain item;
  the plain name moves into the encrypted state. Records live in a new zone `<zone>_v2`; the old
  zone is deleted after the device uploads again (ADR-083, #236).

- `ZenKeychainStoreKey` moved to `zen_store_key` as `ZenDeviceStoreKey` (every platform needs it,
  not only Apple's). `protectDirectory` stays here as `ZenDataProtection.protectDirectory` (ADR-075).
