// Web session client. The browser owns the cookie store; the only thing missing for httpOnly
// session cookies to flow on a cross-origin API call is `withCredentials`, which BrowserClient
// exposes. The server's CORS config sets Access-Control-Allow-Credentials for this to work.
//
// The one cookie this file reads is the CSRF token, and it is readable precisely because the
// server issues it with httpOnly=false - the session tokens next to it are not, and nothing here
// tries to read them.
import 'dart:js_interop';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'csrf.dart';
import 'token_store.dart';
import 'zen_session_client.dart';

/// Web: a [BrowserClient] that sends credentials (cookies) with cross-origin requests, and echoes
/// the double-submit CSRF token on mutating ones.
///
/// [store] is accepted for signature parity across the seam and deliberately ignored: the
/// browser already persists the session cookies to disk for their `Max-Age`, and the tokens are
/// httpOnly, so there is nothing here to read and nowhere better to put it. `restore()`
/// correspondingly reports false — not "no session", but "nothing for the app to do", since a
/// surviving cookie is already attached to the very next request.
ZenSessionClient createPlatformSessionClient({TokenStore? store}) =>
    BrowserSessionClient(BrowserClient()..withCredentials = true);

/// The web session client: a credentialed [BrowserClient] plus the CSRF echo.
///
/// **This is the platform the echo actually defends.** A browser attaches the session cookie to
/// any request to jZen's origin, including one a page on some other site caused — that is what
/// cross-site request forgery is. The token breaks the symmetry: the same-origin policy lets this
/// code read `XSRF-TOKEN` from `document.cookie` and lets the hostile page's code not.
class BrowserSessionClient extends PassthroughSessionClient {
  BrowserSessionClient(super.inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final csrf = readCsrfCookie();
    if (csrf != null &&
        isMutatingMethod(request.method) &&
        !request.headers.keys.any((k) => k.toLowerCase() == csrfHeaderName.toLowerCase())) {
      // A caller's own header wins, so an explicit per-call value is never overwritten.
      request.headers[csrfHeaderName] = csrf;
    }
    return super.send(request);
  }
}

/// The current value of the [csrfCookieName] cookie, or null when the browser has none.
///
/// Null is an ordinary answer, not a failure: it is what an anonymous visitor has, and what
/// everyone has once the token's `Max-Age` runs out. The server only enforces the echo while the
/// access-token cookie it was issued with is still there, and the two share one lifetime — so a
/// missing token here means the request was not going to be enforced either.
String? readCsrfCookie() {
  // `document.cookie` is one string of `name=value` pairs separated by "; ". There is no API that
  // returns a single cookie, so parsing is the only option available.
  for (final pair in _document.cookie.split(';')) {
    final separator = pair.indexOf('=');
    if (separator < 0) continue;
    if (pair.substring(0, separator).trim() != csrfCookieName) continue;
    final value = pair.substring(separator + 1).trim();
    return value.isEmpty ? null : Uri.decodeComponent(value);
  }
  return null;
}

@JS('document')
external _Document get _document;

/// The one member of `document` this file needs. Declared here rather than pulled in with
/// `package:web` so the web branch of the seam adds no dependency to a package the native and
/// stub branches also compile; `dart:js_interop` ships with the SDK and works under both dart2js
/// and dart2wasm.
extension type _Document._(JSObject _) implements JSObject {
  external String get cookie;
}
