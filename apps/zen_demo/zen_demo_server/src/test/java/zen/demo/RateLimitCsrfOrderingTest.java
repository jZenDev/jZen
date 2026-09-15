package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.Map;
import java.util.Set;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;
import zen.identity.auth.SessionService;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.user.UserRole;

/**
 * Proves {@code RateLimitFilter} runs strictly before {@code CsrfFilter} on an <em>authenticated</em>
 * path — the interaction {@link RateLimitEnforcementTest} cannot exercise, since every request it
 * drives is anonymous and CSRF never engages for those (F5).
 *
 * <p>{@code POST /api/v1/auth/logout} is authenticated, mutating (so CSRF applies to it), and
 * falls into the {@code global} bucket rather than {@code auth} (see {@code RateLimitRule}'s
 * javadoc on why logout is not bucketed with the credential endpoints) — so the profile below
 * tightens {@code global} instead of {@code auth}.
 *
 * <p>The proof: every call below is sent with an authenticated identity but <em>no</em> CSRF
 * header, so {@code CsrfFilter} refuses each one with 403. If {@code RateLimitFilter} charges the
 * bucket before {@code CsrfFilter} gets to abort the request — the ordering F5 fixes — the budget
 * still runs out, and the call past it comes back 429 instead of a further 403. Were the filters
 * to run in the other order, {@code CsrfFilter} would abort every call before {@code
 * RateLimitFilter} ever ran, the bucket would never be charged, and every call — forever — would
 * answer 403, never 429.
 */
@QuarkusTest
@TestProfile(RateLimitCsrfOrderingTest.TightGlobalLimit.class)
class RateLimitCsrfOrderingTest {

  private static final int BURST_LIMIT = 3;
  private static final String USER_ID = "3f4a1b2c-0000-4000-8000-00000000rc01";

  /** Kept hermetic: logout calls the provider, and this suite must not need one running. */
  @InjectMock @RestClient SupabaseAuthClient authClient;

  public static class TightGlobalLimit implements QuarkusTestProfile {
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      // Reuses RateLimitEnforcementTest's window-boundary-proof frozen clock; the reasoning for
      // needing it is identical here.
      return Set.of(RateLimitEnforcementTest.FrozenClock.class);
    }

    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "zen.ratelimit.global.burst-limit", String.valueOf(BURST_LIMIT),
          "zen.ratelimit.global.burst-window", "1m",
          "zen.ratelimit.global.durable-limit", "10000");
    }
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void anAuthenticatedRequestWithNoCsrfHeaderIsStillChargedAgainstItsBucket() {
    for (int attempt = 1; attempt <= BURST_LIMIT; attempt++) {
      assertEquals(
          403,
          logoutWithNoCsrfHeader().statusCode(),
          "attempt " + attempt + " is within budget and should reach CsrfFilter's own 403");
    }

    Response throttled = logoutWithNoCsrfHeader();
    assertEquals(
        429,
        throttled.statusCode(),
        "the call past the budget must be refused by RateLimitFilter, proving it charged every"
            + " prior 403 rather than being skipped because CsrfFilter aborted first");
  }

  private Response logoutWithNoCsrfHeader() {
    return given()
        .header("X-Zen-Transport", "json")
        .cookie(SessionService.CSRF_COOKIE, "some-csrf-cookie-value")
        .when()
        .post("/api/v1/auth/logout")
        .andReturn();
  }
}
