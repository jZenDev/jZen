package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.enterprise.inject.spi.BeanManager;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;
import zen.identity.auth.SessionService;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.security.SessionCookieAuthenticationMechanism;

/**
 * An access-token cookie that does not verify must mean "anonymous", not "401 before anything
 * runs".
 *
 * <p>A cookie is ambient — the browser attaches it with nobody deciding to — so a stale one is the
 * most ordinary state a session reaches, and the default treatment of it as an authentication
 * <em>error</em> broke three things that were measured against a running server: sign-out, session
 * recovery, and the rate limiter's coverage. {@link SessionCookieAuthenticationMechanism} carries
 * the reasoning; this carries the proof, in both directions.
 *
 * <p>A garbage cookie value stands in for an expired one deliberately: to the JWT layer they fail
 * identically (neither verifies), and a genuinely expired Supabase token cannot be produced in a
 * hermetic suite. What matters is that verification fails, not why.
 */
@QuarkusTest
class ExpiredSessionCookieTest {

  private static final String HEADER = "X-Zen-Transport";
  private static final String DEAD_COOKIE = "expired.or.garbage";

  @InjectMock @RestClient SupabaseAuthClient authClient;

  @Inject BeanManager beanManager;

  @Test
  void theMechanismIsTheActiveOneInTheAssembledApp() {
    // It replaces the default JWT mechanism by @Alternative/@Priority, and it lives in
    // zen-identity — so it is discovered only while that module runs jandex-maven-plugin. Lose
    // either and the default returns silently, taking the three fixes below with it.
    assertNotNull(
        beanManager.resolve(beanManager.getBeans(SessionCookieAuthenticationMechanism.class)),
        "zen-identity's session-cookie mechanism was not discovered — an expired cookie is back to"
            + " being a 401 before any route runs, and nothing else will say so");
  }

  @Test
  void signOutWorksWithADeadCookie() {
    // The one action that ends a stale session used to be the one action a stale session could not
    // perform. It is also where the upstream revocation now happens.
    given()
        .header(HEADER, "json")
        .cookie(SessionService.ACCESS_COOKIE, DEAD_COOKIE)
        .when()
        .post("/api/v1/auth/logout")
        .then()
        .statusCode(204);
  }

  @Test
  void refreshWorksWithADeadAccessCookieBesideALiveRefreshCookie() {
    when(authClient.token(eq("refresh_token"), any()))
        .thenReturn(
            new SupabaseSessionResponse(
                "fresh-access",
                "fresh-refresh",
                new SupabaseSessionResponse.UserPayload(
                    UUID.randomUUID().toString(),
                    "renewed@example.com",
                    "authenticated",
                    "2024-01-01T00:00:00Z",
                    Map.of()),
                null,
                null,
                null,
                null,
                null,
                null));

    // The sharpest of the three. This endpoint exists to be called *after* the access token dies,
    // and its credential is the refresh cookie — but the dead access cookie travelling beside it
    // used to kill the request first, making a seven-day refresh token unreachable from any client
    // still holding the expired one. A 200 here is only possible if the resource actually ran.
    given()
        .header(HEADER, "json")
        .cookie(SessionService.ACCESS_COOKIE, DEAD_COOKIE)
        .cookie(SessionService.REFRESH_COOKIE, "live-refresh-token")
        .when()
        .post("/api/v1/auth/refresh")
        .then()
        .statusCode(200);
  }

  @Test
  void theIdentityProbeAnswersAnonymousRatherThanRefusing() {
    // "Is anyone signed in?" has an answer when the cookie is stale, and the answer is "no".
    given()
        .header(HEADER, "json")
        .cookie(SessionService.ACCESS_COOKIE, DEAD_COOKIE)
        .when()
        .get("/api/v1/auth/identity")
        .then()
        .statusCode(204);
  }

  @Test
  void anAuthenticatedRouteStillRefuses() {
    // The other direction, and the one that matters most: recovering from the failure produces NO
    // identity, never an assumed one. The route refuses on its own terms instead of the transport
    // layer refusing on everyone's — refusing later is not refusing less.
    given()
        .header(HEADER, "json")
        .cookie(SessionService.ACCESS_COOKIE, DEAD_COOKIE)
        .when()
        .get("/api/v1/demo/profile")
        .then()
        .statusCode(401);
  }

  @Test
  void anAdminRouteStillRefuses() {
    given()
        .header(HEADER, "json")
        .cookie(SessionService.ACCESS_COOKIE, DEAD_COOKIE)
        .when()
        .get("/api/v1/admin/users")
        .then()
        .statusCode(401);
  }

  @Test
  void aForgedCookieGrantsNothing() {
    // A structurally valid but unsigned JWT: the shape an attacker would actually try. It must be
    // no more useful than the garbage above — anonymous, and refused by anything that needs a user.
    String unsigned =
        "eyJhbGciOiJub25lIn0."
            + "eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTQwMDAtODAwMC0wMDAwMDAwMDAwMDEiLCJyb2xlIjoiYWRtaW4ifQ.";

    given()
        .header(HEADER, "json")
        .cookie(SessionService.ACCESS_COOKIE, unsigned)
        .when()
        .get("/api/v1/admin/users")
        .then()
        .statusCode(401);
  }
}
