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
