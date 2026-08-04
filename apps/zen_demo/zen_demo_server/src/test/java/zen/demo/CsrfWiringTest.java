package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import jakarta.enterprise.inject.spi.BeanManager;
import jakarta.inject.Inject;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;
import zen.identity.auth.CsrfFilter;
import zen.identity.auth.SessionService;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.user.UserRole;

/**
 * Proves the CSRF check is discovered in an assembled application, and enforced there.
 *
 * <p><b>Discovery is the half that fails silently.</b> {@link CsrfFilter} lives in
 * {@code zen-identity}, so Quarkus sees it only while that module carries
 * {@code META-INF/jandex.idx} — which it does only while its pom still runs
 * {@code jandex-maven-plugin}. Drop that plugin and the class stays on the classpath, still
 * compiles, still imports, and is never instantiated: no error, no warning, a green suite, and a
 * token that is still issued and still never checked. That is precisely the defect this closes, so
 * from outside the two states are identical.
 *
 * <p><b>{@code @TestSecurity} supplies the one thing enforcement needs</b>, which is an accepted
 * identity — the filter keys on that rather than on a cookie being present. No access-token cookie
 * is sent at all here, and none is needed: a fabricated one would not authenticate anyone, and a
 * genuine one would make this suite depend on a live identity provider.
 */
@QuarkusTest
class CsrfWiringTest {

  private static final String HEADER = "X-Zen-Transport";
  private static final String USER_ID = "3f4a1b2c-0000-4000-8000-00000000cs01";

  /** Kept hermetic: logout calls the provider, and this suite must not need one running. */
  @InjectMock @RestClient SupabaseAuthClient authClient;

  @Inject BeanManager beanManager;

  @Test
  void theCsrfFilterIsAnActiveProviderInTheAssembledApp() {
    assertNotNull(
        beanManager.resolve(beanManager.getBeans(CsrfFilter.class)),
        "zen-identity's CSRF filter was not discovered — check that the module still runs"
            + " jandex-maven-plugin, or the token is issued and never checked and nothing says so");
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void anAuthenticatedMutatingCallWithNoHeaderIsRefused() {
    given()
        .header(HEADER, "json")
        .cookie(SessionService.CSRF_COOKIE, UUID.randomUUID().toString())
        .when()
        .post("/api/v1/auth/logout")
        .then()
        .statusCode(403);
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void anAuthenticatedMutatingCallWithAMismatchedHeaderIsRefused() {
    // The forged case: a cross-site page can cause the cookies to be sent but the same-origin
    // policy stops it reading them, so the best it can do is guess.
    given()
        .header(HEADER, "json")
        .cookie(SessionService.CSRF_COOKIE, UUID.randomUUID().toString())
        .header(SessionService.CSRF_HEADER, UUID.randomUUID().toString())
        .when()
        .post("/api/v1/auth/logout")
        .then()
        .statusCode(403);
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void aMatchingHeaderPasses() {
    String token = UUID.randomUUID().toString();

    given()
        .header(HEADER, "json")
        .cookie(SessionService.CSRF_COOKIE, token)
        .header(SessionService.CSRF_HEADER, token)
        .when()
        .post("/api/v1/auth/logout")
        .then()
        .statusCode(204);
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void aReadIsNeverChecked() {
    // Ordinary traffic — every page load. If this ever returns 403 the app stops working entirely
    // rather than partially.
    given()
        .header(HEADER, "json")
        .cookie(SessionService.CSRF_COOKIE, UUID.randomUUID().toString())
        .when()
        .get("/api/v1/auth/identity")
        .then()
        .statusCode(204);
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void theJobTriggerIsExemptEvenWhenTheCallerHoldsASession() {
    // The exemption is by route, not by "this caller looks like a machine" — Cloud Scheduler has no
    // cookie jar and no token, and enforcing here would break scheduled retention in production and
    // the end-to-end gate with it. Called with a stray CSRF cookie and no shared secret, the answer
    // must be the endpoint's own 401 and not the filter's 403.
    given()
        .cookie(SessionService.CSRF_COOKIE, UUID.randomUUID().toString())
        .when()
        .post("/api/v1/jobs/trigger")
        .then()
        .statusCode(401);
  }

  @Test
  void anAnonymousMutatingCallIsNotChecked() {
    // Nothing the server accepts, so nothing to forge. Logout answers 204 rather than 403 — had the
    // check been unconditional, a client whose session had lapsed could never sign out.
    given()
        .header(HEADER, "json")
        .when()
        .post("/api/v1/auth/logout")
        .then()
        .statusCode(204);
  }
}
