# Changelog

## 0.1.0

- Initial release. `ZenCloudKitSync`: `CKSyncEngine` against the user's private database, each
  record end-to-end encrypted in `encryptedValues`; `ZenKeychainStoreKey`: the store's key in the
  Keychain and iOS Data Protection on its directory. iOS 17 and macOS 14 (ADR-065).

## Unreleased

- A change the store cannot write now waits and is retried, and CloudKit's change token is saved
  only after it. A record this version of the app cannot read holds the token back too. The status
  that says so is no longer replaced by `upToDate`. `ZenCloudKitSync.start` takes `retryEvery`
  (ADR-088, #284).
- A record whose save was refused is handed to the engine again after the merge, not only at the
  next launch or edit.
- A reset of the cloud copy reaches the store before the engine starts, and kept system fields are
  used only for the record and zone they name.

- Record names are an HMAC of `<collection>:<id>` under a key in a synchronizable Keychain item;
  the plain name moves into the encrypted state. Records live in a new zone `<zone>_v2`; the old
  zone is deleted after the device uploads again (ADR-083, #236).

- `ZenKeychainStoreKey` moved to `zen_store_key` as `ZenDeviceStoreKey` (every platform needs it,
  not only Apple's). `protectDirectory` stays here as `ZenDataProtection.protectDirectory` (ADR-075).
