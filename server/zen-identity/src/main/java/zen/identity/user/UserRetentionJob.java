package zen.identity.user;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Event;
import jakarta.inject.Inject;
import java.util.List;
import java.util.function.Consumer;
import java.util.UUID;
import org.jboss.logging.Logger;
import zen.identity.event.AccountDeletionWarning;

/**
 * Drives the data-retention cycle and gates each account's progress on a warning that was actually
 * delivered.
 *
 * <p>Deliberately thin: {@link UserRetentionService} owns the transactions and the policy, this
 * class owns the sequencing and the fan-out. One cycle is: find the accounts due a first warning,
 * warn each, stamp the ones that were warned; the same for the final warning; then anonymise
 * whatever is still dormant past its delivered final warning.
 *
 * <p><strong>No trigger of its own.</strong> There is no {@code @Scheduled} here any more (ADR-008).
 * A cron in this process could not fire under {@code --min-instances=0}, so the trigger moved
 * outside: an application registers {@link #runCycle()} as a {@code ZenJob}, and {@code zen-jobs}
 * runs it when it is due. {@code runCycle()} stays a plain public method, which is what lets the
 * trigger be a deployment choice - and lets a test drive the cycle directly.
 *
 * <p><strong>Idempotent</strong>, as every job must be: each phase's query excludes the accounts
 * the previous run already stamped, so running the cycle twice in a row warns nobody twice and
 * anonymises nobody twice.
 */
@ApplicationScoped
public class UserRetentionJob {

  private static final Logger LOG = Logger.getLogger(UserRetentionJob.class);

  private final UserRetentionService retention;
  private final Event<AccountDeletionWarning> warnings;

  @Inject
  public UserRetentionJob(UserRetentionService retention, Event<AccountDeletionWarning> warnings) {
    this.retention = retention;
    this.warnings = warnings;
  }

  /**
   * Runs one full cycle: first warnings, then final warnings, then anonymisation. Public so an
   * application (or a test) can drive it deterministically instead of waiting for a trigger.
   *
   * @return how many accounts were anonymised by this cycle
   */
  public int runCycle() {
    warn(retention.findAccountsDueFirstWarning(), retention::stampFirstWarningDelivered);
    warn(retention.findAccountsDueFinalWarning(), retention::stampFinalWarningDelivered);
    return retention.anonymiseExpiredAccounts();
  }

  /**
   * Warns each account and stamps only those whose warning came back confirmed.
   *
   * <p>The fire is synchronous so the receipt is readable before the next line - an asynchronous
   * fire could only be followed by hope. An observer that throws costs that one account its warning
   * this cycle and nothing more: the loop continues, and the unstamped account is found again next
   * time.
   */
  private void warn(List<AccountDeletionWarning> due, Consumer<UUID> stamp) {
    for (AccountDeletionWarning warning : due) {
      try {
        warnings.fire(warning);
      } catch (RuntimeException e) {
        LOG.errorf(e, "Retention warning for account %s failed to dispatch", warning.userId());
      }
      if (warning.receipt().isConfirmed()) {
        stamp.accept(warning.userId());
      } else {
        /* The account deliberately does not advance. Anonymising someone who was never reachable
         * is the failure this whole ordering exists to prevent (ADR-008). */
        LOG.warnf(
            "Retention %s warning for account %s was not confirmed delivered; not advancing it"
                + " toward anonymisation",
            warning.stage(), warning.userId());
      }
    }
  }
}
