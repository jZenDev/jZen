# zen_store_key

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**The key a jZen Local application's `zen_store` encrypts its files with, on iOS, macOS, Android,
Windows and Linux.**

`ZenDeviceStoreKey.load` returns this device's 256-bit key, made on first use and kept in the
platform's secret storage (via `flutter_secure_storage`), never beside the data:

| Platform | Where | Notes |
|---|---|---|
| iOS, macOS (not a dev build) | Keychain, `unlocked_this_device` | readable only while unlocked; never in a backup |
| macOS, non-release dev build (`ZEN_ENV=dev`, not `--release`) | login (file) keychain | works with no signing identity; **can be in a backup** (ADR-087) |
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

## macOS: a dev build opens, a signed build is not verified

A sandboxed, ad-hoc-signed macOS app got `PlatformException(... Code: -34018, A required entitlement
is not present)` from the data-protection Keychain, because that needs the `keychain-access-groups`
entitlement and a signing identity (seen on 2026-11-17 running `zen_demo_local`). So the macOS
Keychain is chosen **at compile time** (ADR-087): a **non-release dev build** (`ZEN_ENV=dev` and not `--release`; `ZEN_ENV` alone is not enough, since `Taskfile.app.yml` defaults it to `dev`)
uses the login (file) keychain, which needs no entitlement, and every other build, a `--release` build made with the default `ZEN_ENV=dev` included, keeps the
data-protection Keychain with `unlocked_this_device`. The file keychain can be in a backup; for a
dev build that is accepted, since the data it protects is the developer's own test data.

A release build with no signing identity therefore fails with `-34018` and says so; it never falls back.

The two keychains do not see each other's items. A Mac that runs a dev build and then a release
build (or the reverse) finds the key missing beside existing files, and `load` refuses to open the
data instead of making a new key; erase this device's copy and sync again. A **signed** macOS build
(data-protection Keychain, `keychain-access-groups`) has **not been run**. It was tried with the
free personal team on this Mac and Xcode refused to provision it (`No Accounts`, no `Mac Development`
certificate, no profile), and a hand-signed copy would not launch (`Launch failed`, POSIX 163); the
exact errors are in ADR-087. Adding an account in Xcode is what the next attempt needs.

## Why this is its own package

A plugin imports `dart:ui`, which `dart test` cannot load, so it cannot live in `zen_store`; and it
is not in `zen_store_cloudkit` because CloudKit is Apple's and every Local platform needs a key.

## Test

```sh
cd client/zen_store_key && flutter test
```

The suite pins what the class does with every answer a plugin can give. The native halves
(Keystore, Credential Manager, libsecret) are not exercised by it.
