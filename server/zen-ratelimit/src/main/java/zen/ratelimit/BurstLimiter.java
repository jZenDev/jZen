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
 *
 * <p><strong>The windows are aligned to the epoch, not to each caller's first request.</strong>
 * {@code windowStart = now - floorMod(now, windowMs)}, so a one-minute window turns over at every
 * wall-clock minute for everyone at once, rather than one minute after each caller arrived. Two
 * consequences follow, and neither is a defect. Callers refused near a boundary are all forgiven
 * at the same instant, so their retries arrive together — the tier below is what sees that, and
 * it is why the durable tier exists on the buckets that matter. And a caller's first window is a
 * partial one: arriving at :59.9 buys a full budget for 100ms and another at :00.
 *
 * <p>The same alignment is why a test that spends a budget and asserts the next call is refused
 * must pin the {@link Clock} rather than trust wall time — if a boundary lands mid-sequence the
 * count resets and the call that should have been refused is permitted. That cost one flaky CI
 * failure per ten runs before {@code RateLimitEnforcementTest} froze its clock; the alternative
 * of sleeping past the boundary buys the same green far more slowly.
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
    Window window = windows.computeIfAbsent(key, k -> new Window(windowStart, now));
    long count = window.increment(windowStart, now);

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
   * durable tier is the tier doing the work on the buckets that matter.
   *
   * <p><strong>The single least-recently-active entry is evicted, not the whole table.</strong> A
   * full clear used to forgive every tracked caller at once on every insert past the ceiling — the
   * table never actually settles at the ceiling under sustained pressure, it oscillates between
   * full and empty, and an attacker flooding past the ceiling gets the exact same one-window
   * forgiveness as every legitimate caller whose counter was cleared alongside them. Evicting one
   * entry costs one caller's recency at a time and never resets anyone who is still being counted;
   * a legitimate caller who was active more recently than the flood's oldest address survives.
   * This state lives only as long as this process instance ({@code --max-instances=1},
   * {@code --min-instances=0}) — a redeploy or scale-to-zero clears it exactly as it always has,
   * which is unrelated to this eviction policy and not a regression it introduces.
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
    evictLeastRecentlyActive();
  }

  /** Removes the one entry least recently touched by {@link #check}, to make room for a new one. */
  private void evictLeastRecentlyActive() {
    String oldestKey = null;
    long oldestAccess = Long.MAX_VALUE;
    for (Map.Entry<String, Window> entry : windows.entrySet()) {
      long accessedAt = entry.getValue().lastAccessedAt();
      if (accessedAt < oldestAccess) {
        oldestAccess = accessedAt;
        oldestKey = entry.getKey();
      }
    }
    if (oldestKey != null && windows.remove(oldestKey) != null) {
      LOG.debugf(
          "Burst rate-limit table is full at %d live subjects; evicted the least recently active"
              + " one to make room. This means more distinct client addresses are active than"
              + " zen.ratelimit.max-tracked-subjects, which is itself a sign of a distributed"
              + " flood; the durable tier is unaffected.",
          config.maxTrackedSubjects());
    }
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
   *
   * <p>{@code lastAccessMs} is a plain {@code volatile}, not folded into the same critical
   * section: it is read by {@link #evictLeastRecentlyActive()} from a different thread while
   * this window may be mid-increment, and a torn read of "roughly when this was last touched" is
   * harmless — the worst it costs is evicting a slightly wrong entry among ones that were all
   * about to be evicted regardless. It is millis from the same {@link Clock} {@code check} reads
   * everything else from — not the coarser {@code windowStart} bucket, which is often identical
   * for many callers touched within the same window and so useless for ordering them by recency.
   */
  private static final class Window {

    private long start;
    private long count;
    private volatile long lastAccessMs;

    Window(long start, long now) {
      this.start = start;
      this.lastAccessMs = now;
    }

    synchronized long increment(long windowStart, long now) {
      if (windowStart != start) {
        start = windowStart;
        count = 0;
      }
      lastAccessMs = now;
      return ++count;
    }

    synchronized long startedAt() {
      return start;
    }

    long lastAccessedAt() {
      return lastAccessMs;
    }
  }
}
