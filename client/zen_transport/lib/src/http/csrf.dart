// The double-submit CSRF contract, shared by both halves of the session-client seam.
//
// The server issues a random token in a JS-readable `XSRF-TOKEN` cookie alongside the httpOnly
// access-token cookie, and requires the same value echoed in `X-CSRF-Token` on a mutating request
// that carries a session. The point is that a cross-site page can *cause* the cookie to be sent
// but cannot *read* it, so it cannot produce the header - while the app's own code, running on
// the origin that owns the cookie, can.
//
// Reading that cookie is where the platforms diverge, which is why the echo lives in the session
// client rather than in `ZenClient`: on native the cookie is in `CookieJarClient`'s jar, and on
// web it is in the browser's own store, reachable only through `document.cookie`. One runtime API
// does not express both. Putting it in the client that owns the cookies also means no caller can
// forget it - every request the app makes goes through `send`.

/// The JS-readable cookie the server issues. Must match `SessionService.CSRF_COOKIE`.
const String csrfCookieName = 'XSRF-TOKEN';

/// The companion request header. Must match `SessionService.CSRF_HEADER`.
const String csrfHeaderName = 'X-CSRF-Token';

/// Whether [method] is one the server enforces CSRF on.
///
/// GET and HEAD are safe by definition and carry no CSRF risk, so they are not asked to echo
/// anything; everything else is treated as mutating. Deliberately a positive list of the safe
/// methods rather than of the unsafe ones: a method nobody thought about should end up protected,
/// not exempt.
bool isMutatingMethod(String method) {
  final upper = method.toUpperCase();
  return upper != 'GET' && upper != 'HEAD';
}
