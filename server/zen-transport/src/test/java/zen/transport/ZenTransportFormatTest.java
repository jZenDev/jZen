package zen.transport;

import static org.junit.jupiter.api.Assertions.assertEquals;

import jakarta.ws.rs.core.MediaType;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for {@link ZenTransportFormat#negotiate}, in particular the Content-Type sniff
 * fallback that runs when no {@code X-Zen-Transport} header is present.
 */
class ZenTransportFormatTest {

  @Test
  void header_takesPriorityOverContentType() {
    assertEquals(
        ZenTransportFormat.PROTOBUF,
        ZenTransportFormat.negotiate("protobuf", MediaType.APPLICATION_JSON_TYPE));
  }

  @Test
  void unparseableHeader_fallsThroughToContentTypeSniff() {
    assertEquals(
        ZenTransportFormat.PROTOBUF,
        ZenTransportFormat.negotiate("nonsense", new MediaType("application", "x-protobuf")));
  }

  @Test
  void contentType_applicationXProtobuf_sniffsAsProtobuf() {
    assertEquals(
        ZenTransportFormat.PROTOBUF,
        ZenTransportFormat.negotiate(null, new MediaType("application", "x-protobuf")));
  }

  @Test
  void contentType_applicationJson_sniffsAsJson() {
    assertEquals(
        ZenTransportFormat.JSON,
        ZenTransportFormat.negotiate(null, MediaType.APPLICATION_JSON_TYPE));
  }

  @Test
  void contentType_structuredJsonSuffix_sniffsAsJson() {
    assertEquals(
        ZenTransportFormat.JSON,
        ZenTransportFormat.negotiate(null, new MediaType("application", "vnd.api+json")));
  }

  @Test
  void contentType_lookalikeSubtype_doesNotMatchProtobuf() {
    /* The named edge case: a subtype that merely contains "protobuf" as a substring must not be
     * sniffed as binary protobuf, or an unrelated media type would silently pick the wrong codec. */
    assertEquals(
        ZenTransportFormat.JSON,
        ZenTransportFormat.negotiate(null, new MediaType("text", "protobuf-notes")));
  }

  @Test
  void noHeaderNoContentType_defaultsToJson() {
    assertEquals(ZenTransportFormat.JSON, ZenTransportFormat.negotiate(null, null));
  }
}
