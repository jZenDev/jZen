package zen.identity.user;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Event;
import jakarta.inject.Inject;
import zen.identity.event.AccountDeletionWarning;

/**
 * Drives the data-retention cycle on a schedule and publishes what it stamped.
 *
 * <p>Deliberately thin: {@link UserRetentionService} owns the transactions and the policy, this
 * class owns only the trigger and the fan-out. Events are fired <em>after</em> each phase's
 * transaction has committed, so no warning is mailed for a stamp that did not survive.
 *
 * <p><strong>Opt-in.</strong> The cron expression defaults to {@code off} in this library's
 * {@code META-INF/microprofile-config.properties}, so a framework consumer never starts deleting
 * user data by accident; an application turns retention on by setting
 * {@code zen.identity.retention.cron}. Because prod runs a single instance by design (STANDARDS
 * "Deployment model"), no distributed lock is needed - the trigger to add one is raising
 * {@code --max-instances} above 1.
 */
@ApplicationScoped
public class UserRetentionJob {

  private final UserRetentionService retention;
  private final Event<AccountDeletionWarning> warnings;

  @Inject
  public UserRetentionJob(UserRetentionService retention, Event<AccountDeletionWarning> warnings) {
    this.retention = retention;
    this.warnings = warnings;
  }

  @Scheduled(cron = "{zen.identity.retention.cron}", identity = "zen-user-retention")
  void scheduled() {
    runCycle();
  }

  /**
   * Runs one full cycle: first warnings, then final warnings, then anonymisation. Public so an
   * application (or a test) can drive it deterministically instead of waiting for the cron.
   *
   * @return how many accounts were anonymised by this cycle
   */
  public int runCycle() {
    retention.stampFirstWarnings().forEach(warnings::fireAsync);
    retention.stampFinalWarnings().forEach(warnings::fireAsync);
    return retention.anonymiseExpiredAccounts();
  }
}
