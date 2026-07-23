package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import com.google.protobuf.util.JsonFormat;
import zen.identity.auth.SessionService;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.proto.v1.Identity;
import zen.proto.v1.LoginRequest;
import zen.proto.v1.RegisterRequest;
import zen.proto.v1.ZenError;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import jakarta.ws.rs.WebApplicationException;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;

/**
 * End-to-end proof of the identity surface: the same proto endpoints answer in both transport
 * modes, each token gets its own normally-named cookie, and the error path returns a
 * {@code ZenError}.
 * The {@code @RegisterRestClient SupabaseAuthClient} is mocked (real Supabase is exercised by
 * {@code zen_demo}, ROADMAP step 4); Dev Services provisions Postgres and Flyway migrates.
 */
@QuarkusTest
class AuthResourceTest {

  private static final String PROTOBUF = "application/x-protobuf";
  private static final String HEADER = "X-Zen-Transport";

  @InjectMock @RestClient SupabaseAuthClient authClient;

  private SupabaseSessionResponse session(String email) {
    return new SupabaseSessionResponse(
        "access-jwt",
        "refresh-jwt",
        new SupabaseSessionResponse.UserPayload(
            UUID.randomUUID().toString(), email, "authenticated", Map.of()),
        null,
        null);
  }

  @Test
  void login_jsonMode_returnsIdentityAndTa4Cookies() throws Exception {
    when(authClient.token(eq("password"), any())).thenReturn(session("json@example.com"));

    LoginRequest body =
        LoginRequest.newBuilder().setEmail("json@example.com").setPassword("secret1").build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/login")
            .andReturn();

    assertEquals(200, resp.statusCode());
    assertEquals("json", resp.getHeader(HEADER));
    assertTrue(resp.getContentType().startsWith("application/json"));

    Identity.Builder parsed = Identity.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertFalse(parsed.getId().isEmpty(), "identity id should be the Supabase user id");
    assertEquals(List.of("user"), parsed.getRolesList(), "first login upserts a USER row");

    // One normally-named cookie per token; nothing packs several tokens into one.
    List<String> setCookies = resp.getHeaders().getValues("Set-Cookie");
    assertTrue(setCookies.stream().anyMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=")));
    assertTrue(setCookies.stream().anyMatch(c -> c.startsWith(SessionService.REFRESH_COOKIE + "=")));
    assertTrue(setCookies.stream().noneMatch(c -> c.contains("__session")));
    assertTrue(
        setCookies.stream().noneMatch(c -> c.contains("access-jwt|refresh-jwt")),
        "access|refresh packing must not be reintroduced");
    // The access cookie carries the bare JWT SmallRye reads via mp.jwt.token.cookie.
    assertTrue(
        setCookies.stream()
            .anyMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=access-jwt")));
  }

  @Test
  void login_protobufMode_returnsParseableBinaryIdentity() {
    when(authClient.token(eq("password"), any())).thenReturn(session("proto@example.com"));

    LoginRequest body =
        LoginRequest.newBuilder().setEmail("proto@example.com").setPassword("secret1").build();

    Response resp =
        given()
            .header(HEADER, "protobuf")
            .contentType(PROTOBUF)
            .body(body.toByteArray())
            .when()
            .post("/api/v1/auth/login")
            .andReturn();

    assertEquals(200, resp.statusCode());
    assertEquals("protobuf", resp.getHeader(HEADER));
    assertTrue(resp.getContentType().startsWith(PROTOBUF));

    Identity identity = assertDoesNotThrowParse(resp.getBody().asByteArray());
    assertFalse(identity.getId().isEmpty());
    assertEquals(List.of("user"), identity.getRolesList());
  }

  @Test
  void register_jsonMode_returnsIdentity() throws Exception {
    when(authClient.signup(any(), any())).thenReturn(session("new@example.com"));

    RegisterRequest body =
        RegisterRequest.newBuilder().setEmail("new@example.com").setPassword("secret1").build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/register")
            .andReturn();

    assertEquals(200, resp.statusCode());
    Identity.Builder parsed = Identity.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertFalse(parsed.getId().isEmpty());
  }

  @Test
  void logout_clearsCookies() {
    Response resp = given().header(HEADER, "json").when().post("/api/v1/auth/logout").andReturn();

    assertEquals(204, resp.statusCode());
    List<String> setCookies = resp.getHeaders().getValues("Set-Cookie");
    assertTrue(
        setCookies.stream()
            .anyMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=") && c.contains("Max-Age=0")));
  }

  @Test
  void getCurrentIdentity_anonymous_returns204() {
    given()
        .header(HEADER, "json")
        .when()
        .get("/api/v1/auth/identity")
        .then()
        .statusCode(204);
  }

  @Test
  void login_badCredentials_returnsZenError() throws Exception {
    // Supabase 4xx surfaces as a WebApplicationException; IdentityService maps it to 401.
    when(authClient.token(eq("password"), any()))
        .thenThrow(new WebApplicationException(400));

    LoginRequest body =
        LoginRequest.newBuilder().setEmail("bad@example.com").setPassword("wrong1").build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/login")
            .andReturn();

    assertEquals(401, resp.statusCode());
    ZenError.Builder err = ZenError.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), err);
    assertEquals("unauthorized", err.getCode());
    assertNotNull(err.getMessage());
  }

  private static Identity assertDoesNotThrowParse(byte[] bytes) {
    try {
      return Identity.parseFrom(bytes);
    } catch (Exception e) {
      throw new AssertionError("response body was not parseable protobuf", e);
    }
  }
}
