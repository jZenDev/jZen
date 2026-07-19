// Native session client (dart:io). package:http on native does not persist cookies, and its
// http.Response folds multiple Set-Cookie headers into one comma-joined string, which is lossy
// because a cookie's `Expires=` attribute itself contains a comma. So the jar is built directly
// on a dart:io HttpClient, whose HttpClientResponse.cookies parses Set-Cookie properly into
// List<Cookie>. This closes the native session gap (ROADMAP step 4) while keeping the
// compile-time platform selection intact - this file is only ever compiled into a native build.
import 'dart:io';

import 'package:http/http.dart' as http;

/// Native: a cookie-jar-backed [http.Client].
http.Client createPlatformSessionClient() => CookieJarClient();

/// An [http.BaseClient] that persists Set-Cookie responses and resends them as Cookie headers
/// on subsequent requests, backed by a `dart:io` [HttpClient].
///
/// The jar is a simple in-memory map keyed by cookie name, sufficient for a single-origin demo
/// session (`zen_access_token`, `zen_refresh_token`, `XSRF-TOKEN`). A cookie with `Max-Age <= 0`
/// (what the server sends to clear a cookie on logout) is removed from the jar rather than stored.
class CookieJarClient extends http.BaseClient {
  CookieJarClient({HttpClient? inner}) : _inner = inner ?? HttpClient();

  final HttpClient _inner;
  final Map<String, Cookie> _jar = {};

  /// The cookies currently held by the jar. Exposed for tests.
  List<Cookie> get cookies => List.unmodifiable(_jar.values);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bodyBytes = await request.finalize().toBytes();

    final ioRequest = await _inner.openUrl(request.method, request.url);
    ioRequest.followRedirects = request.followRedirects;
    ioRequest.maxRedirects = request.maxRedirects;

    request.headers.forEach(ioRequest.headers.set);
    ioRequest.cookies.addAll(_jar.values);
    if (bodyBytes.isNotEmpty) {
      ioRequest.add(bodyBytes);
    }

    final ioResponse = await ioRequest.close();
    _storeCookies(ioResponse.cookies);

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

  void _storeCookies(List<Cookie> cookies) {
    for (final cookie in cookies) {
      if (cookie.maxAge != null && cookie.maxAge! <= 0) {
        _jar.remove(cookie.name);
      } else {
        _jar[cookie.name] = cookie;
      }
    }
  }

  @override
  void close() {
    _inner.close(force: true);
    super.close();
  }
}
