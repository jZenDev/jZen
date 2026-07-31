/// Where a native build keeps the refresh token between runs.
///
/// **This is a port, and the reason it is a port is mechanical, not stylistic.** The only
/// implementation worth having on a device is the platform keystore (Keychain on iOS/macOS,
/// Keystore-backed storage on Android), and reaching it means a Flutter plugin, which means
/// `package:flutter/services.dart`, which means `dart:ui`. A `dart:ui` import anywhere in the
/// graph cannot be compiled by the Dart VM at all — `dart test` fails while *loading* the file,
/// whether or not the code is ever called — and `task test:e2e`, the release gate, is a plain
/// `dart test` process. So the implementation is injected at the composition root (the app's
/// `main`), never imported from here.
///
/// Conditional imports do not solve this: they select *code*, while a pubspec dependency is
/// unconditional, so a plugin imported behind `if (dart.library.io)` is still in the graph.
///
/// The default is [InMemoryTokenStore], which touches nothing and keeps the gate honest.
library;

/// A minimal secure key-value slot for one secret.
///
/// Deliberately not a general storage API: one value, three operations, no enumeration. A
/// smaller surface is a smaller thing to get wrong, and nothing here needs more.
abstract interface class TokenStore {
  /// The stored refresh token, or null when there is none.
  Future<String?> read();

  /// Persists [token], replacing anything already stored.
  Future<void> write(String token);

  /// Removes the stored token. Must succeed even when nothing is stored.
  Future<void> delete();
}

/// The default: keeps the token for the life of the process and no longer.
///
/// This is the correct implementation for the web (the browser persists the cookie itself) and
/// for tests, and it is what a native build falls back to when no secure store is injected —
/// behaviour identical to having no persistence at all, which is what shipped before.
class InMemoryTokenStore implements TokenStore {
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}
