package zen.transport;

import jakarta.ws.rs.core.MediaType;
import java.util.Locale;

/**
 * The two wire formats behind the {@code X-Zen-Transport} negotiation seam.
 *
 * <p>These values are the server half of the seam and must stay in step with the client's
 * {@code ZenTransportFormat} in {@code zen_transport}. Parsing is case-insensitive and an
 * unrecognised value falls back to JSON, so an unknown header can never fail a request.
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
   * <p>Negotiation order: explicit {@code X-Zen-Transport} header, then a sniff of the request
   * Content-Type, then default JSON. An unparseable header value falls through rather than
   * failing, so a client that sends nonsense gets JSON rather than an error. The Content-Type
   * sniff compares the subtype exactly (plus the {@code +json} structured-syntax suffix) rather
   * than by substring, so a made-up subtype like {@code text/protobuf-notes} does not get routed
   * to binary protobuf.
   */
  public static ZenTransportFormat negotiate(String header, MediaType contentType) {
    ZenTransportFormat fromHeader = parseOrNull(header);
    if (fromHeader != null) {
      return fromHeader;
    }
    if (contentType != null) {
      String subtype = contentType.getSubtype().toLowerCase(Locale.ROOT);
      if (subtype.equals("x-protobuf") || subtype.equals("protobuf")) {
        return PROTOBUF;
      }
      if (subtype.equals("json") || subtype.endsWith("+json")) {
        return JSON;
      }
    }
    return JSON;
  }

  private static ZenTransportFormat parseOrNull(String value) {
    if (value == null || value.isBlank()) {
      return null;
    }
    switch (value.trim().toLowerCase(Locale.ROOT)) {
      case "json":
        return JSON;
      case "protobuf":
        return PROTOBUF;
      default:
        return null;
    }
  }
}
