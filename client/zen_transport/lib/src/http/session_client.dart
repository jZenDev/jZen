// The compile-time platform seam for session persistence, structured exactly like
// zen_codec_selector.dart (docs/architecture/STANDARDS.md): a default library that
// imports the stub, with `dart.library.io` / `dart.library.js_interop` swapping in the native or
// web implementation so the toolchain tree-shakes the wrong platform's code out of each bundle.
// The web branch keys on `dart.library.js_interop`, not `dart.library.html`: the latter is defined
// only by dart2js, so under dart2wasm it would miss and fall through to the stub, which throws.
// `js_interop` is defined by every web compiler (dart2js AND dart2wasm) and by none of the native
// ones, so it is the portable "this is a web build" signal.
//
// The gap this closes (ROADMAP step 4): the Supabase session lives in httpOnly cookies the
// server sets; SupabaseIdentityRepository relies on them being resent on later requests. On
// the web the browser does that automatically - but only if the client sends credentials
// cross-origin - and on native nothing did it at all, so a login -> getCurrentIdentity round
// trip could not hold a session off-web. createSessionClient() returns the right http.Client
// for the platform: a native cookie jar, or a credentialed browser client.
import 'session_client_stub.dart'
    if (dart.library.js_interop) 'session_client_web.dart'
    if (dart.library.io) 'session_client_io.dart';
import 'token_store.dart';
import 'zen_session_client.dart';

/// Returns an [http.Client] that persists and resends the session cookies for the current
/// platform, so a `ZenClient` built with it maintains a Supabase session across requests.
///
/// - Native (`dart:io`): a cookie jar backed by a `dart:io` `HttpClient`, reading `Set-Cookie`
///   and attaching `Cookie` on subsequent requests to the same host.
/// - Web (`dart:html`): a `BrowserClient` with `withCredentials = true`, so the browser sends
///   the httpOnly session cookies cross-origin.
/// - Other: a plain client (the stub); it should never be selected in practice.
///
/// [store] makes the session outlive the process on native, where nothing else does: pass a
/// keystore-backed [TokenStore] and the refresh token is kept across launches (see
/// `CookieJarClient`). Omit it and behaviour is exactly as before — the session ends with the
/// process. It is optional rather than required because the implementation worth having drags
/// `dart:ui` into the import graph, which the pure-VM release gate cannot compile; injecting it
/// at the app's composition root is what keeps that gate runnable.
///
/// On web the argument is ignored: the browser already persists the cookies itself.
ZenSessionClient createSessionClient({TokenStore? store}) =>
    createPlatformSessionClient(store: store);
