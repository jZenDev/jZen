// The compile-time platform seam for this package's one class, structured exactly like
// zen_transport's session_client.dart (docs/architecture/STANDARDS.md "Client config is
// compile-time"): a default library that exports the stub, with `dart.library.io` /
// `dart.library.js_interop` swapping in the native or web implementation so the toolchain
// tree-shakes the wrong platform's code out of each bundle.
//
// The web branch keys on `dart.library.js_interop`, never `dart.library.html`: the latter is
// defined only by dart2js, so under dart2wasm it would miss and fall through to the stub — which
// is harmless here only because the stub also refuses, but relying on that would be an accident,
// not a guarantee. `js_interop` is defined by every web compiler (dart2js AND dart2wasm) and by
// no native one, so it is the portable "this is a web build" signal.
//
// WHY THE WEB BRANCH REFUSES INSTEAD OF FALLING BACK. Before this seam existed, this file
// unconditionally wrapped `FlutterSecureStorage`, which resolves to `flutter_secure_storage_web`
// on a web build — storing the refresh token in `window.localStorage`, readable by any XSS, with
// `KeychainAccessibility.first_unlock_this_device` silently meaningless because there is no
// Keychain (2026-08-13 architectural security review, F4). The property this class promises —
// "the refresh token lives in platform secure storage" — was true only because every caller so
// far remembered to guard construction on web (`zenIsWeb ? null : SecureTokenStore()` in
// zen_demo's `main.dart`). A second application that wrote the natural `SecureTokenStore()` with
// no guard would get that property silently revoked. Throwing loudly on web moves the guarantee
// into the class itself, where the promise is made, instead of leaving it to every call site to
// remember. zen_demo's ternary stays in place as belt-and-braces; it is redundant now, not wrong.
export 'secure_token_store_stub.dart'
    if (dart.library.js_interop) 'secure_token_store_web.dart'
    if (dart.library.io) 'secure_token_store_io.dart';
