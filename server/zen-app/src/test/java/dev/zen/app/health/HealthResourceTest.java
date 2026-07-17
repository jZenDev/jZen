package dev.zen.app.health;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.util.JsonFormat;
import dev.zen.proto.v1.HealthStatus;
import dev.zen.transport.ZenTransportFormat;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;

/**
 * Proves the dual-mode transport seam end to end: one resource, one proto model, two
 * wire formats selected by {@code X-Zen-Transport}. Boots the full app (Dev Services
 * provides Postgres), so it also proves the skeleton starts.
 */
@QuarkusTest
class HealthResourceTest {

  private static final String PATH = "/api/v1/health";

  @Test
  void jsonMode_returnsCanonicalProto3Json() throws Exception {
    Response resp =
        given().header(ZenTransportFormat.HEADER, "json").when().get(PATH).andReturn();

    assertEquals(200, resp.statusCode());
    assertTrue(
        resp.getContentType().startsWith("application/json"),
        "expected JSON content type, got " + resp.getContentType());
    // The response echoes the negotiated format.
    assertEquals("json", resp.getHeader(ZenTransportFormat.HEADER));

    // Body must be canonical proto3 JSON: parseable straight back into the proto.
    HealthStatus.Builder parsed = HealthStatus.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertEquals("ok", parsed.getStatus());
    assertEquals("zen-app", parsed.getService());
    assertTrue(parsed.getTimestampMs() > 0);
  }

  @Test
  void protobufMode_returnsParseableBinary() throws Exception {
    Response resp =
        given().header(ZenTransportFormat.HEADER, "protobuf").when().get(PATH).andReturn();

    assertEquals(200, resp.statusCode());
    assertTrue(
        resp.getContentType().startsWith("application/x-protobuf"),
        "expected protobuf content type, got " + resp.getContentType());
    assertEquals("protobuf", resp.getHeader(ZenTransportFormat.HEADER));

    // Body must be valid protobuf binary: parse it back with the generated type.
    HealthStatus parsed = HealthStatus.parseFrom(resp.getBody().asByteArray());
    assertEquals("ok", parsed.getStatus());
    assertEquals("zen-app", parsed.getService());
    assertTrue(parsed.getTimestampMs() > 0);
  }

  @Test
  void noHeader_defaultsToJson() {
    given().when().get(PATH).then().statusCode(200).header(ZenTransportFormat.HEADER, equalTo("json"));
  }
}
