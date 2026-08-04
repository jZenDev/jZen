package zen.ratelimit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;

import org.junit.jupiter.api.Test;

/** Which bucket claims which path — the coverage decision, pinned. */
class RateLimitRuleTest {

  @Test
  void theJobTriggerGetsItsOwnBucket() {
    // The highest-consequence endpoint in the system: a successful call anonymises accounts.
    assertSame(RateLimitRule.JOB_TRIGGER, RateLimitRule.resolve("/api/v1/jobs/trigger"));
  }

  @Test
  void everyCredentialBearingAuthEndpointIsCovered() {
    for (String path :
        new String[] {
          "/api/v1/auth/login",
          "/api/v1/auth/register",
          "/api/v1/auth/restore-password",
          "/api/v1/auth/password",
          "/api/v1/auth/session",
          "/api/v1/auth/refresh"
        }) {
      assertSame(RateLimitRule.AUTH, RateLimitRule.resolve(path), path + " must be an AUTH bucket");
    }
  }

  @Test
  void identityAndLogoutAreOrdinaryTrafficRatherThanGuessingSurfaces() {
    // Neither accepts a guess, and a client calls identity on every launch. Bucketing them with
    // login would charge ordinary use to an abuse budget.
    assertSame(RateLimitRule.GLOBAL, RateLimitRule.resolve("/api/v1/auth/identity"));
    assertSame(RateLimitRule.GLOBAL, RateLimitRule.resolve("/api/v1/auth/logout"));
  }

  @Test
  void anythingElseUnderApiFallsToTheGlobalBucket() {
    assertSame(RateLimitRule.GLOBAL, RateLimitRule.resolve("/api/v1/demo/ping"));
    assertSame(RateLimitRule.GLOBAL, RateLimitRule.resolve("api/v1/admin/users"));
  }

  @Test
  void nonApiPathsAreNotCountedAtAll() {
    // Static assets, the health probe and /openapi are not the abuse surface, and counting the
    // Flutter web bundle's own asset requests against a caller would exhaust the budget on load.
    assertNull(RateLimitRule.resolve("/q/health"));
    assertNull(RateLimitRule.resolve("/openapi"));
    assertNull(RateLimitRule.resolve("/"));
    assertNull(RateLimitRule.resolve(null));
  }

  @Test
  void aLeadingOrTrailingSlashDoesNotChangeTheBucket() {
    // UriInfo.getPath() differs between runtimes on the leading slash; a bucket that depended on
    // that would silently stop covering the trigger.
    assertSame(RateLimitRule.JOB_TRIGGER, RateLimitRule.resolve("api/v1/jobs/trigger"));
    assertSame(RateLimitRule.JOB_TRIGGER, RateLimitRule.resolve("/api/v1/jobs/trigger/"));
  }

  @Test
  void theBucketKeyIsStableBecauseItIsWrittenToTheDatabase() {
    assertEquals("job_trigger", RateLimitRule.JOB_TRIGGER.key());
    assertEquals("auth", RateLimitRule.AUTH.key());
    assertEquals("global", RateLimitRule.GLOBAL.key());
  }
}
