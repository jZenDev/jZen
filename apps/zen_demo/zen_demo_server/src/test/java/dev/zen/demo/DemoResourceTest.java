package dev.zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.util.JsonFormat;
import dev.zen.proto.v1.Ping;
import dev.zen.proto.v1.Terms;
import dev.zen.proto.v1.ZenError;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;

/**
 * End-to-end proof of the demo surface used by {@code zen_demo}: {@code /ping} answers in both
 * transport modes with a message localized from {@code Accept-Language}, {@code /terms} serves
 * localized Markdown, and {@code /profile} returns a {@code ZenError} when anonymous (the demo's
 * asserted error path). No mock is needed - these endpoints are self-contained; Dev Services
 * provisions Postgres. The live login -> authenticated {@code /profile} round trip is proven by
 * the pure-Dart e2e suite (task test:e2e), which exercises the real Supabase stack.
 */
@QuarkusTest
class DemoResourceTest {

  private static final String PROTOBUF = "application/x-protobuf";
  private static final String HEADER = "X-Zen-Transport";

  @Test
  void ping_jsonMode_returnsLocalizedMessage() throws Exception {
    Response resp =
        given()
            .header(HEADER, "json")
            .header("Accept-Language", "en")
            .when()
            .get("/api/v1/demo/ping")
            .andReturn();

    assertEquals(200, resp.statusCode());
    assertEquals("json", resp.getHeader(HEADER));
    assertTrue(resp.getContentType().startsWith("application/json"));

    Ping.Builder parsed = Ping.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertEquals("Server is alive", parsed.getMessage());
    assertTrue(parsed.getTimestampMs() > 0);
  }

  @Test
  void ping_protobufMode_returnsParseableBinary() {
    Response resp =
        given()
            .header(HEADER, "protobuf")
            .header("Accept-Language", "en")
            .when()
            .get("/api/v1/demo/ping")
            .andReturn();

    assertEquals(200, resp.statusCode());
    assertEquals("protobuf", resp.getHeader(HEADER));
    assertTrue(resp.getContentType().startsWith(PROTOBUF));

    Ping ping = assertDoesNotThrowParsePing(resp.getBody().asByteArray());
    assertEquals("Server is alive", ping.getMessage());
    assertTrue(ping.getTimestampMs() > 0);
  }

  @Test
  void ping_ukrainianLocale_differsFromEnglish() throws Exception {
    String en = pingMessage("en");
    String uk = pingMessage("uk");
    assertEquals("Server is alive", en);
    assertNotEquals(en, uk, "the ping message must be localized per Accept-Language");
    assertFalse(uk.isBlank());
  }

  @Test
  void terms_returnsLocalizedMarkdown() throws Exception {
    Terms en = terms("en");
    Terms uk = terms("uk");
    assertEquals("text/markdown", en.getContentType());
    assertTrue(en.getContent().contains("Terms of Service"));
    assertTrue(uk.getContent().contains("Умови використання"));
    assertNotEquals(en.getContent(), uk.getContent(), "terms content must be localized");
  }

  @Test
  void profile_anonymous_returnsZenError() throws Exception {
    Response resp =
        given().header(HEADER, "json").when().get("/api/v1/demo/profile").andReturn();

    assertEquals(401, resp.statusCode());
    ZenError.Builder err = ZenError.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), err);
    assertEquals("unauthorized", err.getCode());
    assertNotNull(err.getMessage());
    assertFalse(err.getMessage().isBlank());
  }

  private String pingMessage(String locale) throws Exception {
    Response resp =
        given()
            .header(HEADER, "json")
            .header("Accept-Language", locale)
            .when()
            .get("/api/v1/demo/ping")
            .andReturn();
    assertEquals(200, resp.statusCode());
    Ping.Builder parsed = Ping.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    return parsed.getMessage();
  }

  private Terms terms(String locale) throws Exception {
    Response resp =
        given()
            .header(HEADER, "json")
            .header("Accept-Language", locale)
            .when()
            .get("/api/v1/demo/terms")
            .andReturn();
    assertEquals(200, resp.statusCode());
    Terms.Builder parsed = Terms.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    return parsed.build();
  }

  private static Ping assertDoesNotThrowParsePing(byte[] bytes) {
    try {
      return Ping.parseFrom(bytes);
    } catch (Exception e) {
      throw new AssertionError("response body was not parseable protobuf", e);
    }
  }
}
