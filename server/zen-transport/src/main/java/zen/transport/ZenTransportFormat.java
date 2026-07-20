package zen.transport;

import jakarta.ws.rs.core.MediaType;

/**
 * The two wire formats behind the {@code X-Zen-Transport} negotiation seam.
 *
 * <p>The negotiation logic is ported from DartZen's {@code ZenTransportFormat}
 * ({@code ../DartZen/packages/dartzen_transport/lib/src/zen_transport_header.dart:7}),
 * with two changes: the binary codec is Protobuf rather than MessagePack, and the header
 * is renamed {@code X-DZ-Transport -> X-Zen-Transport} because "DZ" stood for DartZen,
 * which jZen no longer is.
 */
public enum ZenTransportFormat {
  JSON("json", MediaType.APPLICATION_JSON),
  PROTOBUF("protobuf", "application/x-protobuf");

  /** Transport-format negotiation header. */
  public static final String HEADER = "X-Zen-Transport";

  private final String wire;
  private final String mediaType;

  ZenTransportFormat(String wire, String mediaType) {
    this.wire = wire;
    this.mediaType = mediaType;
  }

  /** The {@code X-Zen-Transport} header value, e.g. "json". */
  public String wire() {
    return wire;
  }

  /** The HTTP media type this format serializes to, e.g. "application/json". */
  public String mediaType() {
    return mediaType;
  }

  /**
   * Resolves the response format for a request.
   *
   * <p>Negotiation order is ported from DartZen's server middleware
   * ({@code dartzen_server/.../transport_middleware.dart:75-99}):
   * explicit {@code X-Zen-Transport} header, then a sniff of the request Content-Type,
   * then default JSON. An unparseable header value falls through rather than failing —
   * matching the Dart middleware, which silently ignores a bad header.
   */
  public static ZenTransportFormat negotiate(String header, MediaType contentType) {
    ZenTransportFormat fromHeader = parseOrNull(header);
    if (fromHeader != null) {
      return fromHeader;
    }
    if (contentType != null) {
      String ct = contentType.getType() + "/" + contentType.getSubtype();
      if (ct.contains("protobuf")) {
        return PROTOBUF;
      }
      if (ct.contains("json")) {
        return JSON;
      }
    }
    return JSON;
  }

  private static ZenTransportFormat parseOrNull(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    switch (value.trim().toLowerCase()) {
      case "json":
        return JSON;
      case "protobuf":
      case "msgpack": // legacy DartZen native value; treated as the binary format
        return PROTOBUF;
      default:
        return null;
    }
  }
}
