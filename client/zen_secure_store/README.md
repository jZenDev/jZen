# zen_secure_store

Keystore-backed session persistence for the jZen client: the platform secure storage
implementation of `zen_transport`'s `TokenStore` port.

## Why this is its own package

It reaches Keychain (iOS/macOS) and Keystore-backed storage (Android) through a Flutter plugin,
so its import graph contains `dart:ui`. The Dart VM cannot compile `dart:ui` at all — `dart test`
fails while *loading* such a file, whether or not the code is ever called — and `task test:e2e`,
the release gate, is a plain `dart test` process that imports `zen_transport`.

Putting this class in `zen_transport` would therefore not degrade the release gate, it would end
it. So `zen_transport` declares the port with a do-nothing default, this package implements it,
and the app's `main` wires the two together. Conditional imports do not help: they select *code*,
while a pubspec dependency is unconditional.

## Use

```dart
final TokenStore? tokens = zenIsWeb ? null : SecureTokenStore();
final ZenSessionClient session = createSessionClient(store: tokens);
```

`zenIsWeb` is a compile-time constant, so a web build folds the branch away entirely and carries
no keystore code. Null on web is correct rather than a gap: the browser persists the session
cookies itself, and the web session client ignores the store for that reason.

Then hand the *same* client to `sessionClientProvider`, so `IdentitySessionStore` can resume the
session on the next launch.

## What is stored

Only the refresh token, and only ever one value. The access token stays in memory: it lasts an
hour and is re-obtainable from the refresh token, so writing it down would widen what sits at
rest to save a single round trip.

Persisting to the OS store rather than a file is a requirement, not a preference — OWASP
MASVS-STORAGE-1. An app-support file is readable by any process running as the user on macOS and
rides along in device backups on mobile, which would make persistence a downgrade.

## Platform setup

macOS only: a sandboxed app gets no keychain without the `keychain-access-groups` entitlement, in
**both** `DebugProfile.entitlements` and `Release.entitlements`. It fails at runtime, not at
build. iOS and Android need nothing.

## Tests

The port's behaviour — persistence, rotation, expiry, logout — is tested in `zen_transport`
against a fake store, where it runs on the VM. See `test/session_persistence_test.dart` there.
