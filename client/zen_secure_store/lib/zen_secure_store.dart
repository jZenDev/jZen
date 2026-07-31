/// Keystore-backed session persistence for the jZen client.
///
/// One class, and a package to itself for one mechanical reason: it reaches the platform
/// keystore through a Flutter plugin, so its import graph contains `dart:ui`, and a `dart:ui`
/// import cannot be compiled by the Dart VM at all — `dart test` fails while *loading* such a
/// file, called or not. `task test:e2e`, the release gate, is a plain `dart test` process that
/// imports `zen_transport`. Putting this class in `zen_transport` would therefore not degrade
/// the gate, it would end it.
///
/// So `zen_transport` declares the [TokenStore] port and this package implements it, with the
/// app's `main` wiring the two together. The seam is not taste; it is the shape the toolchain
/// forces, and it is why the port carries a default that touches nothing.
library;

export 'src/secure_token_store.dart' show SecureTokenStore;
