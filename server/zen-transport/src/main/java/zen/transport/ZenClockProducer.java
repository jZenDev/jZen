package zen.transport;

import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.time.Clock;

/**
 * Supplies the {@link Clock} every module reads "now" from.
 *
 * <p>It exists so that time is an injected dependency rather than a static call: due-ness, retry
 * windows, and dormancy cutoffs are all assertions about specific instants, and a test that proved
 * them by sleeping would be slow and flaky at once. A consumer's test substitutes a clock it
 * advances by hand instead.
 *
 * <p>Originally scoped to {@code zen-jobs} (as {@code JobClock}), which was the only module that
 * needed a controllable clock; a second consumer, {@code zen-identity}'s {@code
 * UserRetentionService}, was the trigger to promote it (DECISIONS ADR-008, ADR-051). It lives here
 * rather than in a new {@code zen-time} module because every current and prospective consumer
 * already depends on {@code zen-transport} for the dual-mode HTTP seam, so hosting it here adds no
 * module edge. {@code zen-core} is ruled out: it is deliberately zero-dependency pure Java and
 * would have to become a CDI bean archive to host a producer.
 */
@Singleton
public class ZenClockProducer {

  /**
   * UTC, always. Consumers read intervals and cutoffs rather than wall-clock times, so a zone
   * offset would add nothing but an opportunity for a daylight-saving bug.
   */
  @Produces
  @Singleton
  public Clock systemClock() {
    return Clock.systemUTC();
  }
}
