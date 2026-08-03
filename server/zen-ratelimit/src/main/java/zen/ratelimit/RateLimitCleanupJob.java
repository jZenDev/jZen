package zen.ratelimit;

import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.Clock;
import java.time.Duration;
import java.time.OffsetDateTime;
import org.jboss.logging.Logger;
import zen.jobs.ZenJob;

/**
 * Removes durable counter rows whose window closed long enough ago to be of no further use.
 *
 * <p><strong>A {@link ZenJob}, never {@code @Scheduled}.</strong> Under {@code --min-instances=0}
 * the container exists only while it is serving a request, so an in-process cron has no thread
 * alive at the hour it names: it usually does not fire, and when it does that is an accident of
 * traffic rather than a schedule. That is the entire reason zen-jobs exists (STANDARDS "Deployment
 * model", ADR-008), and it applies with particular force here — the table this job bounds is the
 * one that grows fastest under exactly the attack the limiter exists to survive.
 *
 * <p><strong>Idempotent, as the {@link ZenJob} contract requires.</strong> An external scheduler
 * delivers at-least-once and jZen never suppresses a retry. This body is a single {@code DELETE}
 * over a time predicate: running it twice in a row deletes nothing the second time and is
 * indistinguishable from running it once.
 *
 * <p>The interval here only seeds the row. After the first boot the {@code zen_jobs} table owns
 * the schedule, so an operator changes the cadence or stops the job with an {@code UPDATE} rather
 * than a redeploy.
 */
@ApplicationScoped
public class RateLimitCleanupJob implements ZenJob {

  private static final Logger LOG = Logger.getLogger(RateLimitCleanupJob.class);

  /** Stable handle for the operator and the primary key of the {@code zen_jobs} row. */
  static final String JOB_ID = "zen-ratelimit-cleanup";

  private final RateLimitConfig config;
  private final Clock clock;

  @Inject
  public RateLimitCleanupJob(RateLimitConfig config, Clock clock) {
    this.config = config;
    this.clock = clock;
  }

  @Override
  public String id() {
    return JOB_ID;
  }

  /**
   * Hourly. Matched to the durable windows rather than chosen for tidiness: sweeping much less
   * often lets the table carry many windows' worth of dead rows, and sweeping much more often
   * spends writes on a table that changes slowly once retention has been reached.
   */
  @Override
  public Duration defaultInterval() {
    return Duration.ofHours(1);
  }

  @Override
  public void run() {
    OffsetDateTime cutoff = OffsetDateTime.now(clock).minus(config.counterRetention());
    long removed =
        QuarkusTransaction.requiringNew()
            .call(() -> RateLimitCounter.deleteClosedBefore(cutoff));
    if (removed > 0) {
      LOG.infof("Removed %d rate-limit counter row(s) whose window closed before %s", removed, cutoff);
    }
  }
}
