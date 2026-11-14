# zen_store_key

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**The key a jZen Local application's `zen_store` encrypts its files with, on iOS, macOS, Android,
Windows and Linux.**

`ZenDeviceStoreKey.load` returns this device's 256-bit key, made on first use and kept in the
platform's secret storage (via `flutter_secure_storage`), never beside the data:

| Platform | Where | Notes |
|---|---|---|
| iOS, macOS | Keychain, `unlocked_this_device` | readable only while unlocked; never in a backup |
| Android | Keystore-wrapped value in private storage | not bound to the screen lock; keep the app out of Auto Backup |
| Windows | `.secure` file under `%APPDATA%`, key in Credential Manager | useless on another machine |
| Linux | libsecret (GNOME Keyring, KWallet, portal) | needs `libsecret-1` and a running keyring |

**It never makes a key over existing files.** A missing key beside a data directory that already
holds files, an unreadable store, a value that is not 32 bytes, a key that cannot be saved, a
missing or locked secret service: each is a `ZenError` from `load`, and the application shows it.
A new key would leave the existing files unreadable for good. The reasoning, and what each plugin
does on failure, is in `docs/architecture/DECISIONS.md` ADR-075.

```dart
final directory = await getApplicationSupportDirectory();
final key = (await ZenDeviceStoreKey.load(dataDirectory: directory)).dataOrNull!;
final store = (await ZenStore.open(directory, deviceName: 'Laptop', key: key)).dataOrNull!;
```

## Why this is its own package

A plugin imports `dart:ui`, which `dart test` cannot load, so it cannot live in `zen_store`; and it
is not in `zen_store_cloudkit` because CloudKit is Apple's and every Local platform needs a key.

## Test

```sh
cd client/zen_store_key && flutter test
```

The suite pins what the class does with every answer a plugin can give. The native halves
(Keystore, Credential Manager, libsecret) are not exercised by it.
