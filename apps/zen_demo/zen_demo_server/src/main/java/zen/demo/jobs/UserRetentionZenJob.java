package zen.demo.jobs;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.time.Duration;
import zen.identity.user.UserRetentionJob;
import zen.jobs.ZenJob;

/**
 * Registers the framework's GDPR retention cycle as a scheduled job for this application.
 *
 * <p>This one small class is the whole opt-in, and it is the application's to make. {@code
 * zen-identity} offers {@code runCycle()} as a plain callable and knows nothing about scheduling;
 * {@code zen-jobs} knows how to run things when they are due and nothing about users. Neither
 * depends on the other - the application, which is the only party that knows it wants dormant
 * accounts erased, joins them. That is the same shape as {@code DemoMailer}, where the framework
 * says a warning is due and the application decides what to say (ADR-007, ADR-008).
 *
 * <p>Being a job rather than a cron is what finally discharges the obligation in production: the
 * trigger comes from outside the container, so it fires whether or not an instance happened to be
 * awake, and a cycle missed while scaled to zero is caught up on the next tick.
 */
@ApplicationScoped
public class UserRetentionZenJob implements ZenJob {

  /** Stable job id; also the {@code zen_jobs} primary key an operator would edit. */
  static final String JOB_ID = "user-retention";

  /**
   * Daily. The retention windows are measured in hundreds of days (330 / 23 / 7), so checking more
   * often would cost container starts and change nothing an owner would notice.
   */
  private static final Duration INTERVAL = Duration.ofDays(1);

  private final UserRetentionJob retention;

  @Inject
  public UserRetentionZenJob(UserRetentionJob retention) {
    this.retention = retention;
  }

  @Override
  public String id() {
    return JOB_ID;
  }

  @Override
  public Duration defaultInterval() {
    return INTERVAL;
  }

  @Override
  public void run() {
    retention.runCycle();
  }
}
