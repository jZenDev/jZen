package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.response.Response;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * Proves the limiter actually refuses a request, end to end, in an assembled application.
 *
 * <p><strong>Why this test has to set its own limits.</strong> {@code %test} deliberately runs
 * loose ones: the backend suite drives hundreds of requests from {@code 127.0.0.1} in a few
 * seconds, and production limits would turn every other test into a test of this module. That
 * leaves a gap — a suite that never trips the limiter cannot tell a working limiter from an absent
 * one. A {@link QuarkusTestProfile} closes it honestly: this class, and only this class, boots
 * with limits small enough to hit deliberately, so the loose values elsewhere are a configuration
 * choice rather than a hole.
 *
 * <p>The alternatives were considered and refused, because each buys a green suite by making the
 * product worse: relaxing production limits so the existing tests pass, exempting a path in
 * production, deleting assertions, or inserting sleeps.
 *
 * <p>The endpoint driven is {@code POST /api/v1/jobs/trigger} with no credential — a 401 path, on
 * purpose. It shows the counter is charged <em>before</em> authentication, which is the whole
 * point on this bucket: secret guessing against the endpoint that anonymises accounts consists
 * entirely of requests that fail, so a limiter counting only successes would count only the
 * traffic that was never the problem.
 */
@QuarkusTest
@TestProfile(RateLimitEnforcementTest.TightLimits.class)
class RateLimitEnforcementTest {

  /** How many trigger calls this profile permits per burst window. */
  private static final int BURST_LIMIT = 3;

  /**
   * Limits small enough to hit on purpose, applied to this test class alone.
   *
   * <p>{@code forwarded-hops} stays at 0 to match {@code %test}'s lack of proxy forwarding —
   * {@code RateLimitAddressGuard} refuses to boot on the inconsistent pairing, so a profile that
   * changed one without the other would fail here rather than mislead.
   */
  public static class TightLimits implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "zen.ratelimit.job-trigger.burst-limit", String.valueOf(BURST_LIMIT),
          "zen.ratelimit.job-trigger.burst-window", "1m",
          "zen.ratelimit.job-trigger.durable-limit", "10000",
          "zen.ratelimit.auth.burst-limit", "10000",
          "zen.ratelimit.global.burst-limit", "10000");
    }
  }

  @Test
  void theJobTriggerIsThrottledOnceItsBurstBudgetIsSpent() {
    for (int attempt = 1; attempt <= BURST_LIMIT; attempt++) {
      assertEquals(
          401,
          trigger().statusCode(),
          "attempt " + attempt + " is within budget and should reach the endpoint's own 401");
    }

    Response throttled = trigger();
    assertEquals(429, throttled.statusCode(), "the call past the budget must be refused outright");

    // A 429 that does not say when to come back trains clients to retry immediately, which is the
    // behaviour the limiter exists to stop.
    String retryAfter = throttled.getHeader("Retry-After");
    assertTrue(retryAfter != null && Long.parseLong(retryAfter) >= 1, "Retry-After: " + retryAfter);

    // The body is a ZenError like every other error in the system, not a container default page.
    assertTrue(
        throttled.getBody().asString().contains("rate_limited"),
        "expected a ZenError body, got: " + throttled.getBody().asString());

    // Buckets are counted separately, asserted here rather than in a second test method because
    // both would share one burst window from one address and the second to run would inherit the
    // first's spent budget — an ordering dependency, which is a flaky test waiting to happen.
    // Exhausting the trigger's budget must not take the rest of the application down with it,
    // which would turn the limiter itself into the denial of service.
    given().header("X-Zen-Transport", "json").when().get("/api/v1/health").then().statusCode(200);
  }

  private Response trigger() {
    return given().header("X-Zen-Transport", "json").when().post("/api/v1/jobs/trigger").andReturn();
  }
}
