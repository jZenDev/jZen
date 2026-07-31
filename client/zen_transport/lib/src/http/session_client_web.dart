// Web session client. The browser owns the cookie store; the only thing missing for httpOnly
// session cookies to flow on a cross-origin API call is `withCredentials`, which BrowserClient
// exposes. The server's CORS config sets Access-Control-Allow-Credentials for this to work.
import 'package:http/browser_client.dart';

import 'token_store.dart';
import 'zen_session_client.dart';

/// Web: a [BrowserClient] that sends credentials (cookies) with cross-origin requests.
///
/// [store] is accepted for signature parity across the seam and deliberately ignored: the
/// browser already persists the session cookies to disk for their `Max-Age`, and the tokens are
/// httpOnly, so there is nothing here to read and nowhere better to put it. `restore()`
/// correspondingly reports false — not "no session", but "nothing for the app to do", since a
/// surviving cookie is already attached to the very next request.
ZenSessionClient createPlatformSessionClient({TokenStore? store}) =>
    PassthroughSessionClient(BrowserClient()..withCredentials = true);
