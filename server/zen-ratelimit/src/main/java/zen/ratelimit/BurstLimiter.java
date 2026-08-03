package zen.ratelimit;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.Clock;
import java.time.Duration;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.jboss.logging.Logger;

/**
 * The in-memory tier: fixed windows, second- to minute-scale, no I/O.
 *
 * <p><strong>Why memory is legitimate here.</strong> At most one instance ever runs
 * ({@code --max-instances=1}), so one counter is <em>the</em> counter — the same reason
 * {@code JobScheduler}'s overlap flag is correct. ADR-028 records what raising max-instances
 * silently costs: N instances keep N independent counters and the effective limit becomes N times
 * the configured one, with nothing anywhere reporting it. That is the trigger to move this tier
 * out, and it is a deployment decision rather than a code smell.
 *
 * <p><strong>Why it cannot be the only tier.</strong> Under {@code --min-instances=0} the live
 * service's process is replaced roughly every hour (ADR-027, measured). A counter whose window is
 * an hour would therefore reset itself about as often as it filled — it would look like protection
 * and provide none. Anything hour-scale lives in {@link DurableLimiter}.
 *
 * <p>Fixed windows rather than sliding ones, deliberately: a sliding window needs per-request
 * timestamps, which is unbounded memory driven by attacker traffic. A fixed window is two longs
 * per caller, and its known weakness — up to twice the limit across a window boundary — is
 * absorbed by the durable tier on exactly the buckets where it would matter.
 */
@ApplicationScoped
public class BurstLimiter {

  private static final Logger LOG = Logger.getLogger(BurstLimiter.class);

  private final Map<String, Window> windows = new ConcurrentHashMap<>();

  private final RateLimitConfig config;
  private final Clock clock;

  @Inject
  public BurstLimiter(RateLimitConfig config, Clock clock) {
    this.config = config;
    this.clock = clock;
  }

  /**
   * Charges one request against {@code subject} in {@code rule}'s bucket and says whether it may
   * proceed.
   *
   * <p>Charged on every request, including ones that will go on to fail authentication. That is
   * the point: on the credential buckets it is the failures that constitute the attack, so a
   * limiter that only counted successes would count only the traffic that was never the problem.
   */
  public RateLimitDecision check(RateLimitRule rule, String subject) {
    RateLimitConfig.Limits limits = rule.limitsIn(config);
    long windowMs = limits.burstWindow().toMillis();
    if (limits.burstLimit() <= 0 || windowMs <= 0) {
      return RateLimitDecision.permit();
    }

    long now = clock.millis();
    long windowStart = now - Math.floorMod(now, windowMs);
    String key = rule.key() + '|' + subject;

    note(key);
    Window window = windows.computeIfAbsent(key, k -> new Window(windowStart));
    long count = window.increment(windowStart);

    if (count <= limits.burstLimit()) {
      return RateLimitDecision.permit();
    }
    long retryAfter = Duration.ofMillis(windowStart + windowMs - now).toSeconds();
    return RateLimitDecision.refuse(retryAfter, RateLimitDecision.BURST);
  }

  /**
   * Keeps the map bounded before inserting into it.
   *
   * <p>The ceiling exists because the map's size is driven by how many distinct addresses reach
   * the service, which is attacker-controlled. Unbounded, a flood from a large address pool
   * exhausts a 256Mi instance — and an out-of-memory kill takes the whole service down, which is
   * a strictly worse outcome than any decision this limiter could make about a single request.
   *
   * <p>At the ceiling it first drops windows that have already expired, which is free and usually
   * enough. If the map is <em>still</em> full, every entry is live, meaning more distinct callers
   * are active right now than the configured ceiling — a flood in progress, and by then the
   * durable tier is the tier doing the work on the buckets that matter. It clears the map and says
   * so at WARN. This is a bounded, stated degradation, not a swallowed failure: the cost is at most
   * one burst window of forgiveness, it is logged every time, and the alternative is no service.
   */
  private void note(String incoming) {
    if (windows.size() < config.maxTrackedSubjects() || windows.containsKey(incoming)) {
      return;
    }
    long now = clock.millis();
    sweepExpired(now);
    if (windows.size() < config.maxTrackedSubjects()) {
      return;
    }
    LOG.warnf(
        "Burst rate-limit table is full at %d live subjects and is being cleared; this means more"
            + " distinct client addresses are active than zen.ratelimit.max-tracked-subjects,"
            + " which is itself a sign of a distributed flood. Up to one burst window of requests"
            + " may go uncounted; the durable tier is unaffected.",
        windows.size());
    windows.clear();
  }

  /** Drops windows whose period has already closed. They can only ever permit from here. */
  private void sweepExpired(long now) {
    long longestWindowMs =
        Math.max(
            config.global().burstWindow().toMillis(),
            Math.max(
                config.auth().burstWindow().toMillis(),
                config.jobTrigger().burstWindow().toMillis()));
    Iterator<Window> it = windows.values().iterator();
    while (it.hasNext()) {
      if (now - it.next().startedAt() > longestWindowMs) {
        it.remove();
      }
    }
  }

  /** Test seam: how many subjects the burst tier is currently tracking. */
  int trackedSubjects() {
    return windows.size();
  }

  /**
   * One caller's counter in one bucket.
   *
   * <p>{@code start} and {@code count} are guarded together by {@code synchronized} rather than
   * held as two independent atomics, because they must roll over as one: two concurrent requests
   * either side of a window boundary must not leave the new window's count carrying the old
   * window's total. Contention is per caller per bucket and the critical section is two field
   * writes, so this is cheaper than the atomics it replaces would have been correct.
   */
  private static final class Window {

    private long start;
    private long count;

    Window(long start) {
      this.start = start;
    }

    synchronized long increment(long windowStart) {
      if (windowStart != start) {
        start = windowStart;
        count = 0;
      }
      return ++count;
    }

    synchronized long startedAt() {
      return start;
    }
  }
}
