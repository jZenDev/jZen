// Web session client. The browser owns the cookie store; the only thing missing for httpOnly
// session cookies to flow on a cross-origin API call is `withCredentials`, which BrowserClient
// exposes. The server's CORS config sets Access-Control-Allow-Credentials for this to work.
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

/// Web: a [BrowserClient] that sends credentials (cookies) with cross-origin requests.
http.Client createPlatformSessionClient() => BrowserClient()..withCredentials = true;
