// Native session client (dart:io). package:http on native does not persist cookies, and its
// http.Response folds multiple Set-Cookie headers into one comma-joined string, which is lossy
// because a cookie's `Expires=` attribute itself contains a comma. So the jar is built directly
// on a dart:io HttpClient, whose HttpClientResponse.cookies parses Set-Cookie properly into
// List<Cookie>. This closes the native session gap (ROADMAP step 4) while keeping the
// compile-time platform selection intact - this file is only ever compiled into a native build.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:zen_core/zen_core.dart';

import 'csrf.dart';
import 'token_store.dart';
import 'zen_session_client.dart';

/// Native: a cookie-jar-backed [http.Client].
ZenSessionClient createPlatformSessionClient({TokenStore? store}) =>
    CookieJarClient(store: store);

/// An [http.BaseClient] that persists Set-Cookie responses and resends them as Cookie headers
/// on subsequent requests, backed by a `dart:io` [HttpClient].
///
/// The jar itself is a map keyed by cookie name, sufficient for a single-origin session
/// (`zen_access_token`, `zen_refresh_token`, `XSRF-TOKEN`). A cookie with `Max-Age <= 0` (what
/// the server sends to clear a cookie on logout) is removed rather than stored.
///
/// **Only the refresh token outlives the process, and only when a [TokenStore] is supplied.**
/// A browser persists every session cookie to disk for its `Max-Age`; nothing does that on
/// native, so without this a user re-authenticates on every launch. What is deliberately *not*
/// persisted is the access token: it lasts an hour and is re-obtainable from the refresh token,
/// so writing it down widens what sits at rest to buy one saved round trip. The refresh token
/// has to be written down, because it is the only thing that can rebuild a session.
///
/// This is defence in depth rather than a rule from a standard. What *is* a rule: OWASP
/// MASVS-STORAGE-1 requires any token that is persisted to live in platform secure storage, so
/// a [TokenStore] backed by a plain file would be worse than no persistence at all. And because
/// a native app is a public client, the OAuth 2.0 Security BCP (RFC 9700) wants refresh tokens
/// rotated — Supabase issues a new one on every refresh, and [restore] feeding straight into
/// `POST /auth/refresh` is what makes a token lifted from an old backup go stale.
class CookieJarClient extends ZenSessionClient {
  CookieJarClient({HttpClient? inner, TokenStore? store})
      : _inner = inner ?? HttpClient(),
        _store = store ?? InMemoryTokenStore();

  /// The cookie the server rebuilds a session from. Must match the server's
  /// `session.cookie.refresh-name` (`SessionService.REFRESH_COOKIE`).
  static const String refreshCookieName = 'zen_refresh_token';

  final HttpClient _inner;
  final TokenStore _store;
  final Map<String, Cookie> _jar = {};

  /// The cookies currently held by the jar. Exposed for tests.
  List<Cookie> get cookies => List.unmodifiable(_jar.values);

  /// Seeds the jar from the [TokenStore] so the next request carries the refresh cookie.
  ///
  /// Call this before the first request of a launch. It restores *only* the refresh cookie, so
  /// the caller must follow with `POST /api/v1/auth/refresh` to obtain a usable access token;
  /// the jar cannot do that itself without knowing the API's shape.
  ///
  /// Returns whether a token was restored, so a caller can skip the refresh round trip entirely
  /// when there was never a session to resume.
  ///
  /// A stored token past its expiry is discarded rather than sent: it cannot succeed, and an
  /// expired credential is not a thing to keep lying around. Expiry travels with the value
  /// because a `Cookie` reconstructed from a bare string has none — it would look eternal.
  @override
  Future<bool> restore() async {
    // A keystore is a platform service and can refuse: a locked or unavailable Keychain, a
    // sandbox without the entitlement to reach its own items, a device in an odd state. That must
    // not take the launch down with it. It is reported, not hidden — "no session to resume" is a
    // real and ordinary answer, and the user simply signs in.
    final String? raw;
    try {
      raw = await _store.read();
    } on Exception catch (e, s) {
      ZenLogger.instance.error(
        'Could not read the persisted session; continuing without one',
        error: e,
        stackTrace: s,
      );
      return false;
    }
    if (raw == null || raw.isEmpty) return false;

    final _StoredToken? stored = _StoredToken.decode(raw);
    if (stored == null || stored.hasExpired(DateTime.now().toUtc())) {
      // Unreadable or dead: drop it, so a corrupt entry cannot wedge every future launch.
      await _tryDelete();
      return false;
    }

    _jar[refreshCookieName] = Cookie(refreshCookieName, stored.value)
      ..path = '/'
      ..httpOnly = true
      ..expires = stored.expires;
    return true;
  }

  /// Forgets the session everywhere: the in-process jar and the persistent store.
  ///
  /// Logout already clears the jar through the server's `Max-Age=0` cookies, but that path only
  /// runs when the server answers. This is the one to call when the client decides the session
  /// is over — a refresh that was refused, or a user signing out offline.
  @override
  Future<void> clear() async {
    _jar.clear();
    await _tryDelete();
  }

  /// Deletes the stored token, reporting rather than throwing when the keystore refuses.
  ///
  /// Every caller is already on a path that ends the session — a dead token, a refused refresh,
  /// a sign-out. Throwing here would turn "your session ended" into a crash, and the in-memory
  /// jar has been cleared either way.
  Future<void> _tryDelete() async {
    try {
      await _store.delete();
    } on Exception catch (e, s) {
      ZenLogger.instance.error(
        'Could not clear the persisted session; a stale token may remain at rest',
        error: e,
        stackTrace: s,
      );
    }
  }

  /// The jar's cookies as a `Cookie:` request header, for a WebSocket handshake.
  ///
  /// The handshake is an ordinary HTTP request and jZen's socket endpoint requires the same
  /// session as every other route, but a `dart:io` WebSocket shares nothing with this jar — so
  /// without this the upgrade goes out anonymous and the server closes it. Returns an empty map
  /// when there is no session, rather than an empty `Cookie:` header, because a header present
  /// but blank is not the same thing as no header and some servers treat it differently.
  @override
  Map<String, String> handshakeHeaders() {
    if (_jar.isEmpty) return const {};
    return {
      HttpHeaders.cookieHeader:
          _jar.values.map((c) => '${c.name}=${c.value}').join('; '),
    };
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();

    final ioRequest = await _inner.openUrl(request.method, request.url);
    ioRequest.followRedirects = request.followRedirects;
    ioRequest.maxRedirects = request.maxRedirects;

    request.headers.forEach(ioRequest.headers.set);
    ioRequest.cookies.addAll(_jar.values);

    // Echo the CSRF cookie back as a header on mutating requests.
    //
    // Native gains no protection from this: there is no other origin to forge a request from and
    // no ambient cookie store a hostile page could ride. What it buys is on the server, which can
    // then enforce one rule for every client instead of exempting a platform - and a per-platform
    // exemption is the kind that quietly becomes the way in, since the exemption cannot check
    // which platform is really calling.
    //
    // A caller's own header wins, so an explicit per-call value is never overwritten.
    final csrf = _jar[csrfCookieName]?.value;
    if (csrf != null &&
        csrf.isNotEmpty &&
        isMutatingMethod(request.method) &&
        !request.headers.keys.any((k) => k.toLowerCase() == csrfHeaderName.toLowerCase())) {
      ioRequest.headers.set(csrfHeaderName, csrf);
    }

    if (bodyBytes.isNotEmpty) {
      ioRequest.add(bodyBytes);
    }

    final ioResponse = await ioRequest.close();
    await _storeCookies(ioResponse.cookies);

    final headers = <String, String>{};
    ioResponse.headers.forEach((name, values) {
      // Set-Cookie is already captured into the jar; skip it to avoid the lossy comma-join.
      if (name.toLowerCase() == HttpHeaders.setCookieHeader) return;
      headers[name] = values.join(', ');
    });

    return http.StreamedResponse(
      ioResponse,
      ioResponse.statusCode,
      contentLength: ioResponse.contentLength == -1 ? null : ioResponse.contentLength,
      request: request,
      headers: headers,
      isRedirect: ioResponse.isRedirect,
      persistentConnection: ioResponse.persistentConnection,
      reasonPhrase: ioResponse.reasonPhrase,
    );
  }

  Future<void> _storeCookies(List<Cookie> cookies) async {
    for (final cookie in cookies) {
      final bool expired = cookie.maxAge != null && cookie.maxAge! <= 0;
      if (expired) {
        _jar.remove(cookie.name);
      } else {
        _jar[cookie.name] = cookie;
      }

      if (cookie.name != refreshCookieName) continue;
      // The refresh token rotates: every /auth/refresh mints a new one, and the old one stops
      // working. Persisting on each arrival is what keeps the stored copy the live one.
      //
      // A failure here costs only persistence: the jar already holds the cookie, so the session
      // in progress is unaffected and it is the next launch that will ask for a sign-in. Worth
      // saying out loud, and not worth failing the request the user actually made.
      if (expired) {
        await _tryDelete();
        continue;
      }
      try {
        await _store.write(_StoredToken.fromCookie(cookie).encode());
      } on Exception catch (e, s) {
        ZenLogger.instance.error(
          'Could not persist the session; it will not survive a restart',
          error: e,
          stackTrace: s,
        );
      }
    }
  }

  @override
  void close() {
    _inner.close(force: true);
    super.close();
  }
}

/// A refresh token plus the moment it dies, as one opaque string.
///
/// JSON rather than the raw token because the expiry has to survive with it, and a token stored
/// without one is indistinguishable from a fresh one no matter how old it is.
class _StoredToken {
  const _StoredToken(this.value, this.expires);

  final String value;
  final DateTime? expires;

  static _StoredToken fromCookie(Cookie cookie) {
    DateTime? expires = cookie.expires?.toUtc();
    final int? maxAge = cookie.maxAge;
    if (expires == null && maxAge != null && maxAge > 0) {
      expires = DateTime.now().toUtc().add(Duration(seconds: maxAge));
    }
    return _StoredToken(cookie.value, expires);
  }

  static _StoredToken? decode(String raw) {
    try {
      final Object? parsed = jsonDecode(raw);
      if (parsed is! Map<String, dynamic>) return null;
      final Object? value = parsed['value'];
      if (value is! String || value.isEmpty) return null;
      final Object? expires = parsed['expires'];
      return _StoredToken(
        value,
        expires is String ? DateTime.tryParse(expires)?.toUtc() : null,
      );
    } on FormatException {
      return null;
    }
  }

  String encode() => jsonEncode({
        'value': value,
        if (expires != null) 'expires': expires!.toIso8601String(),
      });

  bool hasExpired(DateTime now) => expires != null && !expires!.isAfter(now);
}
