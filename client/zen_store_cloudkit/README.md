# zen_store_cloudkit

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**CloudKit sync, the store's key and Data Protection for a light jZen application, on iOS 17 and
macOS 14.**

Three things a light app's `zen_store` needs from Apple's APIs, and nothing else:

- **`ZenCloudKitSync`** — the `ZenSyncTransport` a release build uses. `CKSyncEngine` against the
  user's private database, one CloudKit record per store record in a custom zone, the record's
  whole state in one `encryptedValues` field: encrypted on the device with keys in the user's
  iCloud Keychain, so Apple holds ciphertext whether or not Advanced Data Protection is on.
- **`ZenKeychainStoreKey`** — the 256-bit key `zen_store` encrypts its files with, in the Keychain,
  this device only, readable only while the device is unlocked. Made once; a Keychain that cannot
  be read fails the load rather than producing a new key that would orphan the existing files.
- **`ZenKeychainStoreKey.protectDirectory`** — iOS Data Protection `complete` on the store's
  directory, so its files are unreadable while the phone is locked. macOS has no such class; the
  store's own encryption covers it there.

See `docs/architecture/DECISIONS.md` ADR-065.

## 🧘 Why this is its own package

A plugin imports `dart:ui`, and `dart test` cannot load `dart:ui`, so putting this in `zen_store`
would move that package's suite off the Dart VM — the same reason `zen_secure_store` is not part
of `zen_transport`.

## 🧩 Why `CKSyncEngine`

It is Apple's, and it owns what a hand-written sync loop would own badly: change tracking,
batching, retries, push-triggered fetches and change tokens. This plugin only hands it records and
hands back what it fetched, saved or refused. The merge stays `zen_store`'s: a save CloudKit refuses
because another device saved first comes back with the server's copy, the store merges it — or
records a conflict for the person — and sends it again.

## 📦 Swift Package Manager only

The plugin ships `darwin/zen_store_cloudkit/Package.swift` and no podspec. SwiftPM is Flutter's
default for iOS and macOS since 3.44, and the CocoaPods registry goes read-only on 2026-12-02. An
app created with a current Flutter is already on SwiftPM; an older one turns it on with
`flutter config --enable-swift-package-manager`.

## 🚀 Use

```dart
final directory = await getApplicationSupportDirectory();
await ZenKeychainStoreKey.protectDirectory(directory);   // before the store writes anything
final key = (await ZenKeychainStoreKey.load()).dataOrNull!;
final store = (await ZenStore.open(directory, deviceName: "Alex's iPhone", key: key)).dataOrNull!;

// Chosen at compile time (STANDARDS "Client config is compile-time"), never at runtime.
const syncMode = String.fromEnvironment('ZEN_SYNC');
final sync = syncMode == 'folder'
    ? await ZenFolderCloud.start(store, developmentFolder)
    : await ZenCloudKitSync.start(store, containerId: 'iCloud.com.example.app');
```

A missing iCloud account is not a start failure: sync starts and its `status` says why it is
waiting. Every reason sync stops — no account, iCloud Keychain off, the account switched, the cloud
data deleted, storage full, a record from a newer app version — is a `ZenSyncStatus` that
`zen_ui_store`'s `ZenSyncStatusBanner` shows. An account switch stops sync rather than uploading one
person's data into another's account; deleted cloud data stops sync rather than deleting the
device's.

## 🔑 What the app must declare

The CloudKit capability with one container, in each runner's entitlements
(`ios/Runner/*.entitlements`, `macos/Runner/*.entitlements`), the container created in the Apple
Developer portal and enabled for the app id:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.com.example.app</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
```

Adding the CloudKit capability in Xcode also adds Push Notifications, which `CKSyncEngine` uses to
learn of other devices' changes. Both need a **paid Apple Developer Program membership**; until
then, develop two-device sync through `ZenFolderCloud` in `zen_store`.

## 🧪 Test

```sh
cd client/zen_store_cloudkit && flutter test
```

The suite drives the Dart half against every message the Swift half sends — fetched, saved,
refused, status, a reset of the cloud copy, a record from a newer version — with a real `ZenStore`
underneath, and pins the Keychain key. Syncing through real CloudKit needs a signed build on two
devices and is not covered by any suite here.
