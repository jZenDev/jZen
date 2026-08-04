import 'package:http/http.dart' as http;

/// The session-bearing [http.Client] every platform returns, and the reason the app can talk
/// about resuming a session without knowing which platform it is on.
///
/// The persistence work only exists on native — a browser does it itself, and the stub platform
/// has nothing to do it with — but the *app* is one codebase compiled for all of them. Without a
/// neutral type the composition root would have to name `CookieJarClient`, which does not exist
/// in a web build, so the seam would leak straight into `main`.
///
/// Hence: both operations are always callable, and on the platforms with nothing to do they do
/// nothing and say so ([restore] returns false). A caller writes one launch sequence.
abstract class ZenSessionClient extends http.BaseClient {
  /// Reloads a persisted session into this client, if there is one and it is still valid.
  ///
  /// Returns whether anything was restored, so a caller can skip the refresh round trip when
  /// there was no session to resume. A restored client holds only the refresh token: the caller
  /// must exchange it (`POST /api/v1/auth/refresh`) before making an authenticated request.
  Future<bool> restore();

  /// Ends the session in this client and in any persistent store behind it.
  Future<void> clear();

  /// Headers that carry this client's session onto a WebSocket handshake.
  ///
  /// A WebSocket upgrade is an ordinary HTTP request, so a server can require the same session
  /// cookie there that it requires everywhere else — and jZen's does. Whether the cookie is
  /// *attached* is where the platforms diverge sharply, which is why this is a method on the
  /// session client rather than something a caller assembles:
  ///
  /// - **Native** has to send it explicitly. Nothing shares state between the cookie jar and a
  ///   `dart:io` WebSocket, so without this the handshake is anonymous and the server closes it.
  /// - **Web** must send nothing. The browser attaches its own cookies to a same-origin
  ///   handshake automatically, and the browser WebSocket API accepts no custom headers at all —
  ///   so the default below is not a gap, it is the only correct answer there.
  ///
  /// Empty by default for exactly that reason: a platform with nothing to add returns nothing.
  Map<String, String> handshakeHeaders() => const {};
}

/// A [ZenSessionClient] that just forwards to [inner]: the shape for platforms where session
/// persistence is either automatic (the browser) or impossible (the stub).
class PassthroughSessionClient extends ZenSessionClient {
  PassthroughSessionClient(this.inner);

  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => inner.send(request);

  @override
  Future<bool> restore() async => false;

  @override
  Future<void> clear() async {}

  @override
  void close() {
    inner.close();
    super.close();
  }
}
