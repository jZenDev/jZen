import 'package:http/http.dart' as http;
import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart';

/// Calls the Quarkus demo endpoints (GET /api/v1/demo/{ping,terms,profile} and the /ws echo)
/// through zen_transport, replacing DartZen's
/// ../DartZen/apps/ZenDemo/dartzen_demo_client/lib/src/api_client.dart (which hand-rolled
/// package:http). Auth is handled separately by SupabaseIdentityRepository.
///
/// It holds two [ZenClient]s that share one session [http.Client]: one pinned to JSON and one
/// to Protobuf. Pinning the format at construction is how the demo forces each transport mode
/// explicitly (ZenClient negotiates a single format per instance). Sharing the session client
/// means the cookie set at login flows to the auth-gated /profile call - the round trip the
/// native cookie jar exists to make work off-web.
class DemoRepository {
  DemoRepository({required String baseUrl, required http.Client session})
    : _wsUri = _webSocketUri(baseUrl),
      _json = ZenClient(
        baseUrl: baseUrl,
        format: ZenTransportFormat.json,
        httpClient: session,
      ),
      _protobuf = ZenClient(
        baseUrl: baseUrl,
        format: ZenTransportFormat.protobuf,
        httpClient: session,
      );

  static const String _pingPath = '/api/v1/demo/ping';
  static const String _termsPath = '/api/v1/demo/terms';
  static const String _profilePath = '/api/v1/demo/profile';

  final ZenClient _json;
  final ZenClient _protobuf;
  final Uri _wsUri;

  /// Pings the server in the given transport [format], localized by [language]. Both modes hit
  /// the same typed endpoint; only the wire format differs.
  Future<ZenResult<Ping>> ping({
    required ZenTransportFormat format,
    required String language,
  }) {
    final client = format == ZenTransportFormat.protobuf ? _protobuf : _json;
    return client.send<Ping>(
      Ping.new,
      method: ZenHttpMethod.get,
      path: _pingPath,
      headers: {'Accept-Language': language},
    );
  }

  /// Loads the localized Markdown terms of service.
  Future<ZenResult<Terms>> terms({required String language}) => _json.send<Terms>(
    Terms.new,
    method: ZenHttpMethod.get,
    path: _termsPath,
    headers: {'Accept-Language': language},
  );

  /// Loads the authenticated user's demo profile. Returns a ZenError when the session cookie is
  /// missing or rejected (the demo's error path).
  Future<ZenResult<DemoProfile>> profile() => _json.send<DemoProfile>(
    DemoProfile.new,
    method: ZenHttpMethod.get,
    path: _profilePath,
  );

  /// Opens the demo WebSocket echo. Frames are binary Protobuf on every platform (the server
  /// endpoint is single-format), so the format is forced rather than negotiated.
  ZenWebSocket connectWebSocket() =>
      ZenWebSocket(_wsUri, format: ZenTransportFormat.protobuf);

  static Uri _webSocketUri(String baseUrl) {
    final base = Uri.parse(baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return base.replace(scheme: scheme, path: '/api/v1/demo/ws');
  }
}
