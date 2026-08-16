package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.response.Response;
import jakarta.enterprise.inject.Alternative;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import java.util.Set;
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

    /**
     * Freezes time for this class, which is what makes the assertions below deterministic.
     *
     * <p>{@code BurstLimiter}'s window is a TUMBLING window aligned to the epoch — {@code
     * windowStart = now - floorMod(now, windowMs)} — so with a one-minute window the counter resets
     * at every wall-clock minute, not one minute after a caller's first request. Each test here
     * spends its budget and then asserts the next call is refused; if a minute boundary happened to
     * fall between those two, {@code Window.increment} reset the count and the call that should
     * have been refused was permitted, arriving as the endpoint's own 401 instead of a 429.
     *
     * <p>That is not a bug in the limiter — a fixed window forgiving up to 2x the limit across a
     * boundary is the tradeoff it is chosen for — it is this test asserting as though the window
     * began at its first request. It failed roughly one CI run in ten, on whichever pull request
     * had the bad luck to straddle the boundary (2026-08-15 and 2026-08-16, on two unrelated
     * dependabot branches; the same commit passed and then failed). It never reproduced locally,
     * because the sequence runs far faster there and so is exposed for less of the minute.
     *
     * <p>A sleep that waits out the boundary would also work and is rejected for the reason given
     * above: this class does not buy green by inserting sleeps. Substituting the clock is the
     * pattern the codebase already uses for exactly this (see {@code JobSchedulerTest}'s driven
     * clock, and {@code JobClock}'s note that {@code Clock} is injected so it can be replaced).
     */
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      return Set.of(FrozenClock.class);
    }

    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "zen.ratelimit.job-trigger.burst-limit", String.valueOf(BURST_LIMIT),
          "zen.ratelimit.job-trigger.burst-window", "1m",
          "zen.ratelimit.job-trigger.durable-limit", "10000",
          // The auth bucket is tight here too, so the dead-cookie case below can spend a budget of
          // its own. Buckets are counted separately, which is what keeps the two test methods
          // independent of each other's order — the reason the assertions above share one method.
          "zen.ratelimit.auth.burst-limit", String.valueOf(BURST_LIMIT),
          "zen.ratelimit.auth.durable-limit", "10000",
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

  @Test
  void aRequestCarryingADeadSessionCookieIsStillCounted() {
    /*
     * The bypass this closes was measured rather than imagined. While an unverifiable access-token
     * cookie was rejected by proactive auth before the JAX-RS chain, RateLimitFilter never ran and
     * the durable counter did not move: attaching any junk value as zen_access_token made a request
     * unmetered on EVERY endpoint while still occupying one of the 200 concurrency slots that are
     * the entire capacity of the service (ADR-027). A limiter with a one-cookie opt-out.
     *
     * SessionCookieAuthenticationMechanism turns that cookie into "anonymous" rather than an error,
     * so the request reaches the filter and is charged like any other. The proof is that the budget
     * runs out at all: if these were still uncounted, every call below would answer 401 forever.
     */
    for (int attempt = 1; attempt <= BURST_LIMIT; attempt++) {
      assertEquals(
          401,
          refreshWithDeadCookie().statusCode(),
          "attempt " + attempt + " is within budget and should reach the endpoint's own 401");
    }

    assertEquals(
        429,
        refreshWithDeadCookie().statusCode(),
        "a dead session cookie must not buy an unmetered request");
  }

  /**
   * A clock stopped on a window boundary, replacing the framework's {@code JobClock} producer.
   *
   * <p>The instant is deliberately ON a minute boundary, so {@code floorMod(now, 60_000) == 0} and
   * the frozen "now" is the window's own start: every request in a test lands in the first
   * millisecond of the same window, and {@code Retry-After} is the full window rather than a
   * rounded-down remainder that could reach zero and fail the assertion for a second reason.
   *
   * <p>Nothing else in an assembled {@code %test} application reads this clock in a way that
   * freezing breaks: the in-process job tick is off in {@code %test} on purpose ("no tick may fire
   * behind a test's back"), so {@code JobScheduler} and {@code RateLimitCleanupJob} never run here,
   * and {@code DurableLimiter}'s budget is set to 10000 below — far out of reach of these few
   * requests — so its window never matters either.
   */
  @Alternative
  @Singleton
  public static class FrozenClock {

    private static final Instant ON_A_WINDOW_BOUNDARY = Instant.parse("2026-01-01T00:00:00Z");

    @Produces
    @Singleton
    public Clock frozenClock() {
      return Clock.fixed(ON_A_WINDOW_BOUNDARY, ZoneOffset.UTC);
    }
  }

  private Response trigger() {
    return given().header("X-Zen-Transport", "json").when().post("/api/v1/jobs/trigger").andReturn();
  }

  /** A refresh with no refresh cookie: the endpoint's own answer is 401, so a 429 is the limiter. */
  private Response refreshWithDeadCookie() {
    return given()
        .header("X-Zen-Transport", "json")
        .cookie("zen_access_token", "expired.or.garbage")
        .when()
        .post("/api/v1/auth/refresh")
        .andReturn();
  }
}
