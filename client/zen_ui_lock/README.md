# zen_ui_lock

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**No sign-in, but not open to whoever picks up the phone: an optional PIN for a light jZen app.**

A light application (ADR-065) has no account and no login. This package lets its user close it
with a PIN anyway — off by default, turned on from settings.

## 🚀 Use

```dart
final lock = (await ZenPinLock.load()).dataOrNull!;

MaterialApp(
  localizationsDelegates: [lockLocaleDelegate, ...],
  builder: (context, child) => ZenLockGate(lock: lock, child: child!),
  home: ...,
);

// In settings:
ZenPinLockSwitch(lock: lock)        // on → set a PIN; off → enter the current one
showZenPinSetup(context, lock)      // change the PIN
```

`ZenLockGate` goes in `builder`, above the navigator, so every route is covered.

## 🔐 What it does

- **Starts locked** when a PIN is set, and **locks again** after the app has been in the
  background for `relockAfter` (a minute by default).
- **Covers the app in the app switcher**, so the snapshot does not show what the PIN protects.
- **Keeps the app mounted** while locked — a half-typed form survives — but not painted, not
  tappable and not read by a screen reader.
- **Stores only a salted PBKDF2-HMAC-SHA256 hash**, in the Keychain with
  `first_unlock_this_device`: off backups and off every other device, so each device has its own
  PIN.
- **Shuts out guessing**: from the fifth wrong PIN, attempts wait 30 s, doubling to at most an
  hour, and the count survives a restart.
- **"Forgot PIN?"** asks for the device's own passcode, Face ID or Touch ID, then removes the PIN.
  There is no server to recover through, and whoever can unlock the device already holds what the
  PIN protects. The app must declare `NSFaceIDUsageDescription` in its iOS `Info.plist`.

## 🧪 Test

```sh
cd client/zen_ui_lock && flutter test --dart-define=ZEN_PLATFORM=ios
```
