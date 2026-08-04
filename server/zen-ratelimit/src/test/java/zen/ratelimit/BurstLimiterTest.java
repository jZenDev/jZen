package zen.ratelimit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

/**
 * The burst tier's arithmetic, proved against a clock the test advances by hand rather than by
 * sleeping — a limiter test that slept would be slow and flaky at the same time, and the thing
 * being asserted is a statement about instants.
 */
class BurstLimiterTest {

  private final MutableClock clock = new MutableClock(Instant.parse("2026-08-03T10:00:00Z"));

  /** A caller whose exact address never matters to the arithmetic. */
  private static final String CALLER = "203.0.113.7";

  private BurstLimiter limiterAllowing(int perMinute) {
    return new BurstLimiter(new StubConfig(perMinute), clock);
  }

  @Test
  void requestsUpToTheLimitArePermittedAndTheNextIsNot() {
    BurstLimiter limiter = limiterAllowing(3);
    for (int i = 1; i <= 3; i++) {
      assertTrue(limiter.check(RateLimitRule.AUTH, CALLER).permitted(), "request " + i);
    }
    assertFalse(limiter.check(RateLimitRule.AUTH, CALLER).permitted(), "the fourth is over");
  }

  @Test
  void aRefusalSaysWhenToComeBackAndNeverSaysNow() {
    BurstLimiter limiter = limiterAllowing(1);
    limiter.check(RateLimitRule.AUTH, CALLER);
    RateLimitDecision refused = limiter.check(RateLimitRule.AUTH, CALLER);

    assertFalse(refused.permitted());
    assertEquals(RateLimitDecision.BURST, refused.tier());
    // Retry-After: 0 reads as "immediately", which is an invitation to hammer.
    assertTrue(refused.retryAfterSeconds() >= 1, "Retry-After must never be 0");
    assertTrue(refused.retryAfterSeconds() <= 60, "and must not outlive the window");
  }

  @Test
  void theWindowResetsWhenItCloses() {
    BurstLimiter limiter = limiterAllowing(2);
    limiter.check(RateLimitRule.AUTH, CALLER);
    limiter.check(RateLimitRule.AUTH, CALLER);
    assertFalse(limiter.check(RateLimitRule.AUTH, CALLER).permitted());

    clock.advance(Duration.ofMinutes(1));
    assertTrue(limiter.check(RateLimitRule.AUTH, CALLER).permitted(), "a new window is a new budget");
  }

  @Test
  void oneCallerRunningOutDoesNotAffectAnother() {
    // The failure this guards against is the "blocks everyone" half: a subject key that collapses
    // distinct callers together throttles the whole internet as one.
    BurstLimiter limiter = limiterAllowing(1);
    assertTrue(limiter.check(RateLimitRule.AUTH, "198.51.100.1").permitted());
    assertFalse(limiter.check(RateLimitRule.AUTH, "198.51.100.1").permitted());
    assertTrue(limiter.check(RateLimitRule.AUTH, "198.51.100.2").permitted());
  }

  @Test
  void bucketsAreCountedSeparatelyFromEachOther() {
    // Exhausting the auth budget must not lock the same caller out of ordinary API traffic.
    BurstLimiter limiter = limiterAllowing(1);
    assertTrue(limiter.check(RateLimitRule.AUTH, CALLER).permitted());
    assertFalse(limiter.check(RateLimitRule.AUTH, CALLER).permitted());
    assertTrue(limiter.check(RateLimitRule.GLOBAL, CALLER).permitted());
  }

  @Test
  void theTrackedSubjectCeilingIsEnforcedRatherThanGrowingUnbounded() {
    // The map's size is attacker-controlled, and an out-of-memory kill on a 256Mi instance is a
    // strictly worse outcome than any decision this limiter could make about one request.
    BurstLimiter limiter = new BurstLimiter(new StubConfig(1000, 10), clock);
    for (int i = 0; i < 50; i++) {
      limiter.check(RateLimitRule.GLOBAL, "10.0.0." + i);
    }
    assertTrue(
        limiter.trackedSubjects() <= 10,
        "the burst table grew past its ceiling: " + limiter.trackedSubjects());
  }

  @Test
  void aZeroLimitDisablesTheBucketRatherThanBlockingEverything() {
    // The %test profile relies on this reading: a limit of 0 must not mean "refuse every request".
    BurstLimiter limiter = limiterAllowing(0);
    assertTrue(limiter.check(RateLimitRule.AUTH, CALLER).permitted());
  }

  /** A hand-written {@link RateLimitConfig} — the interface is small enough not to need a mock. */
  private record StubConfig(int burstLimit, int maxTrackedSubjects) implements RateLimitConfig {

    StubConfig(int burstLimit) {
      this(burstLimit, 100_000);
    }

    @Override
    public boolean enabled() {
      return true;
    }

    @Override
    public int forwardedHops() {
      return 0;
    }

    @Override
    public Duration counterRetention() {
      return Duration.ofHours(48);
    }

    @Override
    public Limits global() {
      return limits();
    }

    @Override
    public Limits auth() {
      return limits();
    }

    @Override
    public Limits jobTrigger() {
      return limits();
    }

    private Limits limits() {
      return new StubLimits(burstLimit);
    }
  }

  /** Burst-only: the durable tier has its own test and needs a database. */
  private record StubLimits(int burstLimit) implements RateLimitConfig.Limits {

    @Override
    public Duration burstWindow() {
      return Duration.ofMinutes(1);
    }

    @Override
    public int durableLimit() {
      return 0;
    }

    @Override
    public Duration durableWindow() {
      return Duration.ofHours(1);
    }
  }

  /** A clock the test moves, so windows can be crossed without waiting for them. */
  private static final class MutableClock extends Clock {

    private Instant now;

    MutableClock(Instant now) {
      this.now = now;
    }

    void advance(Duration by) {
      now = now.plus(by);
    }

    @Override
    public ZoneId getZone() {
      return ZoneOffset.UTC;
    }

    @Override
    public Clock withZone(ZoneId zone) {
      return this;
    }

    @Override
    public Instant instant() {
      return now;
    }
  }
}
