@TestOn('browser')
library;

// The web half of the CSRF seam, compiled and run by a real browser.
//
// This file exists because the native half is invisible proof of nothing here: `session_client_io`
// and `session_client_web` are selected by a compile-time conditional import, so the VM suite that
// covers one never compiles the other. A web-only mistake - an interop declaration that does not
// resolve, a dart2wasm-incompatible construct - is a green `task test` and a broken app. Run it
// with `dart test -p chrome` (and again with `--compiler dart2wasm`); `task test:client:matrix`
// does both.
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:zen_transport/src/http/csrf.dart';
import 'package:zen_transport/src/http/session_client_web.dart';

@JS('document')
external _Document get _document;

extension type _Document._(JSObject _) implements JSObject {
  external String get cookie;
  external set cookie(String value);
}

void main() {
  setUp(() {
    // Cookies are per-document and survive between tests; expire it so each case starts clean.
    _document.cookie = '$csrfCookieName=; Max-Age=0; path=/';
  });

  test('reads the CSRF token the server left in a JS-readable cookie', () {
    _document.cookie = '$csrfCookieName=csrf-token; path=/';

    // The whole reason the token is issued with httpOnly=false: the app's own code can read it
    // and a cross-site page's cannot.
    expect(readCsrfCookie(), 'csrf-token');
  });

  test('returns null when the browser holds no token', () {
    // What an anonymous visitor has, and what everyone has once the token expires. Null is an
    // ordinary answer: the server only enforces the echo while the access cookie it was issued
    // with is still present, and the two share one lifetime.
    expect(readCsrfCookie(), isNull);
  });

  test('finds the token among other cookies rather than only as the first', () {
    _document.cookie = 'other=first; path=/';
    _document.cookie = '$csrfCookieName=csrf-token; path=/';
    _document.cookie = 'zzz_after=last; path=/';

    expect(readCsrfCookie(), 'csrf-token');
  });

  test('the web session client is the credentialed browser client', () {
    final client = createPlatformSessionClient();
    addTearDown(client.close);

    // Without withCredentials the httpOnly session cookies never leave the browser on a
    // cross-origin API call, and without the CSRF echo every mutating call is refused.
    expect(client, isA<BrowserSessionClient>());
  });
}
