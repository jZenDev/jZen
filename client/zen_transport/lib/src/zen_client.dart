// Two invariants of the client, both required by docs/architecture/STANDARDS.md
// "The client never swallows a failure" and covered by tests:
//   1. The default format comes from selectDefaultCodec() (the compile-time platform
//      selector), NOT a hardcoded ZenTransportFormat.json.
//   2. A decode failure surfaces a ZenError (from common.proto) via ZenResult.err - it is
//      never silently swallowed into a null payload.
//
// The {id,status,data,error} envelope is dropped: the caller sends and receives typed
// protobuf messages directly. HTTP status carries the status, X-Request-ID carries the id,
// and the shared ZenError proto carries errors.
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:protobuf/protobuf.dart';
import 'package:zen_core/zen_core.dart';

import 'generated/zen/v1/common.pb.dart' as pb;
import 'zen_codec_selector.dart';
import 'zen_http_method.dart';
import 'zen_proto_codec.dart';
import 'zen_transport_error.dart';
import 'zen_transport_header.dart';

/// Standard HTTP header for request IDs.
const String requestIdHeaderName = 'X-Request-ID';

/// Standard HTTP header carrying the caller's preferred locale.
const String acceptLanguageHeaderName = 'Accept-Language';

/// HTTP client for jZen dual-mode transport.
///
/// A caller sends a typed protobuf request and receives a typed protobuf response; the wire
/// format (canonical proto3 JSON or Protobuf binary) is chosen by [format] and announced via
/// the `X-Zen-Transport` header. The server echoes the header, and the response is decoded
/// with the negotiated format.
///
/// Example:
/// ```dart
/// final client = ZenClient(baseUrl: 'http://localhost:8080');
/// final result = await client.get(HealthStatus.new, '/api/v1/health');
/// result.fold(
///   (status) => print(status.service),
///   (error) => print('Error: ${error.message}'),
/// );
/// ```
class ZenClient {
  /// Creates a new [ZenClient].
  ///
  /// [baseUrl] is the base URL for all requests. [format] defaults to
  /// [selectDefaultCodec], the compile-time platform selector. [httpClient]
  /// allows injecting a custom HTTP client for testing. [language] supplies the caller's
  /// current locale for [acceptLanguageHeaderName]; see the field.
  ZenClient({
    required this.baseUrl,
    ZenTransportFormat? format,
    http.Client? httpClient,
    this.language,
  }) : format = format ?? selectDefaultCodec(),
       _httpClient = httpClient ?? http.Client();

  /// Base URL for all requests.
  final String baseUrl;

  /// Transport format used for outbound requests and as the fallback for decoding
  /// responses that do not echo an `X-Zen-Transport` header.
  final ZenTransportFormat format;

  /// Supplies the caller's current locale, sent as `Accept-Language` on every request.
  ///
  /// A callback rather than a value because the locale is live app state: the user switches
  /// language mid-session and the next request must reflect it. Leave it null and the header is
  /// simply omitted, so the server falls back on its own default.
  ///
  /// This is ambient request context, exactly like the request id and the transport format:
  /// the locale belongs to the *request*, not to any one endpoint's arguments. That is why it
  /// lives here instead of on each repository method - it reaches every endpoint at once,
  /// including the ones whose server side reads it without the client ever knowing (the
  /// registration that seeds `users.language`, which in turn localizes email). A per-call
  /// `headers:` entry still wins, so a caller that needs a specific locale can override it.
  final String Function()? language;

  final http.Client _httpClient;
  int _requestCounter = 0;

  /// Generates a unique request ID.
  String _generateRequestId() {
    _requestCounter++;
    return 'req-${DateTime.now().millisecondsSinceEpoch}-$_requestCounter';
  }

  /// Sends an HTTP request and decodes the response into a message of type [T].
  ///
  /// [createEmpty] is the response message constructor tear-off (e.g. `HealthStatus.new`);
  /// [body] is an optional typed proto request payload. Returns [ZenResult.ok] with the
  /// decoded message on 2xx, or [ZenResult.err] carrying a [ZenTransportError] on a non-2xx
  /// response or a decode failure.
  Future<ZenResult<T>> send<T extends GeneratedMessage>(
    T Function() createEmpty, {
    required ZenHttpMethod method,
    required String path,
    GeneratedMessage? body,
    Map<String, String>? headers,
  }) async {
    final requestId = _generateRequestId();
    final uri = Uri.parse('$baseUrl$path');
    final requestHeaders = _buildHeaders(headers, requestId);
    final Uint8List? encodedBody = body == null ? null : ZenProtoCodec.encode(body, format);

    final http.Response response;
    try {
      response = switch (method) {
        ZenHttpMethod.get => await _httpClient.get(uri, headers: requestHeaders),
        ZenHttpMethod.post => await _httpClient.post(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        ),
        ZenHttpMethod.put => await _httpClient.put(uri, headers: requestHeaders, body: encodedBody),
        ZenHttpMethod.delete => await _httpClient.delete(
          uri,
          headers: requestHeaders,
          body: encodedBody,
        ),
      };
    } catch (e) {
      // Network / I/O failure never yields a null payload.
      return ZenResult.err(
        ZenTransportError(
          pb.ZenError(code: ZenTransportErrorCode.network.wire, message: 'Request failed: $e'),
        ),
      );
    }
    return _buildResult(response, createEmpty);
  }

  /// Sends a GET request and decodes the response into [T].
  Future<ZenResult<T>> get<T extends GeneratedMessage>(
    T Function() createEmpty,
    String path, {
    Map<String, String>? headers,
  }) => send(createEmpty, method: ZenHttpMethod.get, path: path, headers: headers);

  /// Sends a POST request with an optional typed [body] and decodes the response into [T].
  Future<ZenResult<T>> post<T extends GeneratedMessage>(
    T Function() createEmpty,
    String path, {
    GeneratedMessage? body,
    Map<String, String>? headers,
  }) => send(createEmpty, method: ZenHttpMethod.post, path: path, body: body, headers: headers);

  /// Sends a PUT request with an optional typed [body] and decodes the response into [T].
  Future<ZenResult<T>> put<T extends GeneratedMessage>(
    T Function() createEmpty,
    String path, {
    GeneratedMessage? body,
    Map<String, String>? headers,
  }) => send(createEmpty, method: ZenHttpMethod.put, path: path, body: body, headers: headers);

  /// Sends a DELETE request and decodes the response into [T].
  Future<ZenResult<T>> delete<T extends GeneratedMessage>(
    T Function() createEmpty,
    String path, {
    GeneratedMessage? body,
    Map<String, String>? headers,
  }) => send(createEmpty, method: ZenHttpMethod.delete, path: path, body: body, headers: headers);

  /// Closes the HTTP client.
  void close() => _httpClient.close();

  Map<String, String> _buildHeaders(Map<String, String>? customHeaders, String requestId) {
    // Resolved per request, not cached: the user can switch language mid-session.
    final locale = language?.call();
    return {
      'Content-Type': format.contentType,
      'Accept': format.contentType,
      zenTransportHeaderName: format.value,
      requestIdHeaderName: requestId,
      if (locale != null && locale.isNotEmpty) acceptLanguageHeaderName: locale,
      // Spread last, so an explicit per-call header overrides the ambient ones.
      ...?customHeaders,
    };
  }

  /// Builds a typed [ZenResult] from an HTTP [response].
  ///
  /// The response format is re-negotiated from the response's own `X-Zen-Transport` header,
  /// falling back to the client's [format].
  ZenResult<T> _buildResult<T extends GeneratedMessage>(
    http.Response response,
    T Function() createEmpty,
  ) {
    final statusCode = response.statusCode;
    final bytes = Uint8List.fromList(response.bodyBytes);

    // Re-negotiate the response format from its own header. The http package lowercases
    // response header keys.
    final headerValue = response.headers[zenTransportHeaderName.toLowerCase()];
    final ZenTransportFormat responseFormat;
    if (headerValue != null) {
      try {
        responseFormat = ZenTransportFormat.parse(headerValue);
      } catch (e) {
        // An unrecognized negotiation header is a protocol error, surfaced as a ZenError
        // rather than guessed at.
        return ZenResult.err(
          ZenTransportError(
            pb.ZenError(
              code: ZenTransportErrorCode.decode.wire,
              message: 'Unrecognized $zenTransportHeaderName header: "$headerValue"',
            ),
          ),
        );
      }
    } else {
      responseFormat = format;
    }

    // Error responses carry a ZenError (common.proto).
    if (statusCode >= 400) {
      if (bytes.isEmpty) {
        return ZenResult.err(
          ZenTransportError(
            pb.ZenError(
              code: ZenTransportErrorCode.http.wire,
              message: response.reasonPhrase ?? 'HTTP $statusCode',
            ),
          ),
        );
      }
      try {
        final err = ZenProtoCodec.decode(bytes, responseFormat, pb.ZenError.new);
        return ZenResult.err(ZenTransportError(err));
      } catch (e) {
        return ZenResult.err(
          ZenTransportError(
            pb.ZenError(
              code: ZenTransportErrorCode.decode.wire,
              message: 'Failed to decode error response ($statusCode): $e',
            ),
          ),
        );
      }
    }

    // Success. An empty body (e.g. 204 No Content) yields an empty message.
    if (bytes.isEmpty) {
      return ZenResult.ok(createEmpty());
    }
    try {
      final message = ZenProtoCodec.decode(bytes, responseFormat, createEmpty);
      return ZenResult.ok(message);
    } catch (e) {
      // A decode failure surfaces a ZenError, never a silent null.
      return ZenResult.err(
        ZenTransportError(
          pb.ZenError(
            code: ZenTransportErrorCode.decode.wire,
            message: 'Failed to decode response body: $e',
          ),
        ),
      );
    }
  }
}
