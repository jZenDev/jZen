// The client half of the negotiation seam (docs/architecture/BLUEPRINT.md "The dual-mode
// transport seam"). These values must match the Quarkus server's ZenTransportFormat.
import 'zen_transport_exception.dart';

/// The header name used for transport format negotiation.
const String zenTransportHeaderName = 'X-Zen-Transport';

/// Valid transport format values.
enum ZenTransportFormat {
  /// Canonical proto3 JSON.
  json('json'),

  /// Protobuf binary.
  protobuf('protobuf');

  const ZenTransportFormat(this.value);

  /// The string value used in headers.
  final String value;

  /// The MIME type for request/response bodies in this format.
  String get contentType => switch (this) {
    ZenTransportFormat.json => 'application/json',
    ZenTransportFormat.protobuf => 'application/x-protobuf',
  };

  /// Parses a header value into a [ZenTransportFormat].
  ///
  /// Throws [ZenTransportException] if the value is invalid.
  static ZenTransportFormat parse(String value) {
    switch (value.toLowerCase()) {
      case 'json':
        return ZenTransportFormat.json;
      case 'protobuf':
        return ZenTransportFormat.protobuf;
      default:
        throw ZenTransportException(
          'Invalid transport format: "$value". Expected "json" or "protobuf".',
        );
    }
  }
}
