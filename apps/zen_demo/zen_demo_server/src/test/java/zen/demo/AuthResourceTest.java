package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.google.protobuf.util.JsonFormat;
import zen.identity.auth.SessionService;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.auth.UserUpdateRequest;
import zen.proto.v1.Identity;
import zen.proto.v1.LoginRequest;
import zen.proto.v1.RegisterRequest;
import zen.proto.v1.SessionExchangeRequest;
import zen.proto.v1.SetPasswordRequest;
import zen.proto.v1.ZenError;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
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

  /** An auto-confirm signup / login response: a session with a confirmed nested user. */
  private SupabaseSessionResponse session(String email) {
    return new SupabaseSessionResponse(
        "access-jwt",
        "refresh-jwt",
        new SupabaseSessionResponse.UserPayload(
            UUID.randomUUID().toString(), email, "authenticated", "2024-01-01T00:00:00Z", Map.of()),
        null,
        null,
        null,
        null,
        null,
        null);
  }

  /**
   * GoTrue's bare-user signup response when email confirmation is required: the user at the top
   * level, no session, {@code email_confirmed_at} null (unconfirmed).
   */
  private SupabaseSessionResponse pendingConfirmation(String email) {
    return new SupabaseSessionResponse(
        null, null, null, null, null, UUID.randomUUID().toString(), email, null, Map.of());
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
    assertTrue(parsed.getEmailVerified(), "auto-confirm signup returns a verified identity");
  }

  @Test
  void register_emailConfirmationRequired_returns202AndUnverifiedIdentityWithNoSession()
      throws Exception {
    // Supabase requires email confirmation: signup creates the account but returns no session.
    when(authClient.signup(any(), any())).thenReturn(pendingConfirmation("pending@example.com"));

    RegisterRequest body =
        RegisterRequest.newBuilder()
            .setEmail("pending@example.com")
            .setPassword("secret1")
            .build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/register")
            .andReturn();

    // 202 Accepted: the account exists, but the user is not signed in until they confirm.
    assertEquals(202, resp.statusCode());
    Identity.Builder parsed = Identity.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertFalse(parsed.getId().isEmpty(), "account created, so the identity id is present");
    assertFalse(parsed.getEmailVerified(), "confirmation pending: email is not verified");

    // No session cookies: registration did not sign the user in.
    List<String> setCookies = resp.getHeaders().getValues("Set-Cookie");
    assertTrue(
        setCookies == null
            || setCookies.stream().noneMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=")),
        "no access cookie is set when email confirmation is pending");
  }

  @Test
  void register_existingEmail_returnsNeutral202AndDoesNotEnumerate() throws Exception {
    // Supabase (enumeration protection off) rejects a re-registration with an "email exists" 4xx.
    // The framework must NOT surface that: registering an existing address has to look identical to
    // a fresh registration (a 202 with no session), so a caller cannot tell that the account exists.
    when(authClient.signup(any(), any()))
        .thenThrow(
            new WebApplicationException(
                jakarta.ws.rs.core.Response.status(422)
                    .entity("{\"error_code\":\"email_exists\",\"msg\":\"A user with this email address has already been registered\"}")
                    .build()));

    RegisterRequest body =
        RegisterRequest.newBuilder().setEmail("taken@example.com").setPassword("secret1").build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/register")
            .andReturn();

    // Same shape as a genuine pending confirmation: 202, unverified identity, no session cookies.
    assertEquals(202, resp.statusCode(), "an existing email must return the neutral 202, not a 409");
    Identity.Builder parsed = Identity.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertFalse(parsed.getEmailVerified(), "confirmation-pending shape: email is not verified");

    List<String> setCookies = resp.getHeaders().getValues("Set-Cookie");
    assertTrue(
        setCookies == null
            || setCookies.stream().noneMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=")),
        "no session is issued for an existing-email registration");
    // No enumeration and no upstream leak anywhere in the response body.
    String lower = resp.getBody().asString().toLowerCase();
    assertFalse(lower.contains("already"), "must not reveal the account already exists");
    assertFalse(lower.contains("supabase"), "must not name the auth provider");
  }

  @Test
  void authCallback_landsOnAppRoot() {
    // The Supabase email-confirmation link redirects here; it must not 404, it must send the
    // browser to the app so the confirmed user can sign in.
    Response resp = given().redirects().follow(false).when().get("/auth/callback").andReturn();
    assertEquals(303, resp.statusCode());
    assertEquals("/?auth=email-confirmed", resp.getHeader("Location"));
  }

  @Test
  void sessionExchange_validLinkToken_signsInAndSetsCookies() throws Exception {
    // The tokens an email link left in the URL fragment, handed back by the client. Supabase
    // vouches for the access token; only then does a session exist.
    when(authClient.getUser("Bearer link-jwt"))
        .thenReturn(
            new SupabaseSessionResponse.UserPayload(
                UUID.randomUUID().toString(),
                "confirmed@example.com",
                "authenticated",
                "2024-01-01T00:00:00Z",
                Map.of()));

    SessionExchangeRequest body =
        SessionExchangeRequest.newBuilder()
            .setAccessToken("link-jwt")
            .setRefreshToken("link-refresh")
            .build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/session")
            .andReturn();

    assertEquals(200, resp.statusCode());
    Identity.Builder parsed = Identity.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertFalse(parsed.getId().isEmpty(), "the confirmed user gets a profile row like any login");
    assertEquals(List.of("user"), parsed.getRolesList());

    // The whole point: the token stops being a URL parameter and becomes an httpOnly cookie.
    List<String> setCookies = resp.getHeaders().getValues("Set-Cookie");
    assertTrue(
        setCookies.stream().anyMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=link-jwt")));
    assertTrue(
        setCookies.stream()
            .anyMatch(c -> c.startsWith(SessionService.REFRESH_COOKIE + "=link-refresh")));
    assertTrue(
        setCookies.stream()
            .anyMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=") && c.contains("HttpOnly")),
        "the exchanged token must not be readable by page scripts");
  }

  @Test
  void sessionExchange_rejectedToken_returns401WithNoSession() throws Exception {
    // A forged or expired token: Supabase refuses it, so no cookie is issued. This is what stops
    // the endpoint being an open door despite being @PermitAll.
    when(authClient.getUser(any())).thenThrow(new WebApplicationException(401));

    SessionExchangeRequest body =
        SessionExchangeRequest.newBuilder().setAccessToken("forged").build();

    Response resp =
        given()
            .header(HEADER, "json")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/session")
            .andReturn();

    assertEquals(401, resp.statusCode());
    assertTrue(
        resp.getHeaders().getValues("Set-Cookie").stream()
            .noneMatch(c -> c.startsWith(SessionService.ACCESS_COOKIE + "=forged")),
        "a refused token must never reach a cookie");
    ZenError.Builder err = ZenError.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), err);
    assertFalse(err.getMessage().toLowerCase().contains("supabase"));
  }

  @Test
  void sessionExchange_missingToken_returns401() throws Exception {
    SessionExchangeRequest body = SessionExchangeRequest.newBuilder().build();

    given()
        .header(HEADER, "json")
        .contentType("application/json")
        .body(JsonFormat.printer().print(body))
        .when()
        .post("/api/v1/auth/session")
        .then()
        .statusCode(401);
  }

  @Test
  @TestSecurity(user = "11111111-1111-1111-1111-111111111111", roles = "user")
  void setPassword_withSession_updatesWithTheSessionsOwnToken() throws Exception {
    SetPasswordRequest body = SetPasswordRequest.newBuilder().setPassword("a-new-secret").build();

    given()
        .header(HEADER, "json")
        .contentType("application/json")
        .cookie(SessionService.ACCESS_COOKIE, "session-jwt")
        .body(JsonFormat.printer().print(body))
        .when()
        .post("/api/v1/auth/password")
        .then()
        .statusCode(204);

    // Supabase is told to change the password of whoever the session's own token belongs to —
    // there is no user id in the request, so one session can never change another's password.
    verify(authClient).updateUser("Bearer session-jwt", new UserUpdateRequest("a-new-secret"));
  }

  @Test
  void setPassword_withoutSession_is401() throws Exception {
    SetPasswordRequest body = SetPasswordRequest.newBuilder().setPassword("a-new-secret").build();

    given()
        .header(HEADER, "json")
        .contentType("application/json")
        .body(JsonFormat.printer().print(body))
        .when()
        .post("/api/v1/auth/password")
        .then()
        .statusCode(401);
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
    // A Supabase 4xx with no readable body maps to a safe, generic 401 — never the provider name.
    when(authClient.token(eq("password"), any())).thenThrow(new WebApplicationException(400));

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
    // Security: the client-facing message must never leak the auth provider or a raw upstream text.
    assertFalse(err.getMessage().toLowerCase().contains("supabase"));
  }

  @Test
  void login_invalidCredentialsBody_isClassifiedAndDoesNotLeak() throws Exception {
    // A Supabase 4xx whose body identifies the cause: classify it to a specific, safe code.
    when(authClient.token(eq("password"), any()))
        .thenThrow(
            new WebApplicationException(
                jakarta.ws.rs.core.Response.status(400)
                    .entity("{\"error_code\":\"invalid_credentials\",\"msg\":\"Invalid login credentials\"}")
                    .build()));

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
    assertEquals("invalid_credentials", err.getCode());
    assertFalse(err.getMessage().toLowerCase().contains("supabase"));
    assertFalse(err.getMessage().toLowerCase().contains("invalid login credentials"));
  }

  private static Identity assertDoesNotThrowParse(byte[] bytes) {
    try {
      return Identity.parseFrom(bytes);
    } catch (Exception e) {
      throw new AssertionError("response body was not parseable protobuf", e);
    }
  }
}
