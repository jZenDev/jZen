// The client's failure type. STANDARDS "Failures surface; nothing is swallowed" requires that a decode
// failure - and any error response - surface a ZenError from common.proto rather than a
// silent null. ZenTransportError is a zen_core ZenError (so it fits ZenResult<T>) that also
// carries the wire proto ZenError, reachable via [zenError].
import 'package:zen_core/zen_core.dart';

import 'generated/zen/v1/common.pb.dart' as pb;

/// Machine-readable codes the client itself attaches to a synthesized [pb.ZenError] when a
/// request never reaches a server-supplied error body. Centralized so no code string is
/// hand-written at the call sites; each maps to its wire value via [wire].
enum ZenTransportErrorCode {
  /// The request failed before a response was received (connection, DNS, timeout).
  network('network_error'),

  /// A response body (or its X-Zen-Transport header) could not be decoded.
  decode('decode_error'),

  /// A non-2xx response arrived with no decodable body.
  http('http_error');

  const ZenTransportErrorCode(this.wire);

  /// The stable string value carried in [pb.ZenError.code].
  final String wire;
}

/// A transport-layer failure that wraps the wire [pb.ZenError] (common.proto).
class ZenTransportError extends ZenError {
  /// The wire error payload: `code`, `message`, and optional field-level violations.
  final pb.ZenError zenError;

  /// Wraps [zenError], surfacing its `message` as the [ZenError.message] and its `code`
  /// (plus any field errors) as [ZenError.internalData].
  ZenTransportError(this.zenError)
    : super(
        zenError.message,
        internalData: {
          'code': zenError.code,
          if (zenError.fieldErrors.isNotEmpty)
            'fieldErrors': Map<String, String>.from(zenError.fieldErrors),
        },
      );

  @override
  String toString() =>
      'ZenTransportError(code: ${zenError.code}, message: ${zenError.message})';
}
