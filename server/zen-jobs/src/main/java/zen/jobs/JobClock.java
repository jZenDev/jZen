package zen.jobs;

import jakarta.enterprise.inject.Produces;
import jakarta.inject.Singleton;
import java.time.Clock;

/**
 * Supplies the {@link Clock} the scheduler reads "now" from.
 *
 * <p>It exists so that time is an injected dependency rather than a static call: due-ness, the
 * catch-up rule, and the recorded {@code last_run_at} are all assertions about specific instants,
 * and a test that proved them by sleeping would be slow and flaky at once. {@code JobSchedulerTest}
 * substitutes a clock it advances by hand.
 *
 * <p>Scoped to this module rather than promoted into {@code zen-core}, which is deliberately a
 * zero-dependency pure-Java library (see its pom) and would have had to become a CDI bean archive
 * to host this. {@code zen-jobs} is the only module that needs a controllable clock today; a second
 * consumer is the trigger to promote it, on evidence (DECISIONS ADR-008).
 */
@Singleton
public class JobClock {

  /**
   * UTC, always. Job schedules are intervals rather than wall-clock times, so a zone offset would
   * add nothing but an opportunity for a daylight-saving bug.
   */
  @Produces
  @Singleton
  public Clock systemClock() {
    return Clock.systemUTC();
  }
}
