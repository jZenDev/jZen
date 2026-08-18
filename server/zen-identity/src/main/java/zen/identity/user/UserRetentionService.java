package zen.identity.user;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Event;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import zen.identity.event.AccountDeletionWarning;
import zen.identity.event.AccountDeletionWarning.Stage;
import zen.identity.event.DeliveryReceipt;
import zen.identity.event.UserAnonymised;

/**
 * GDPR Art. 5(1)(e) data retention: warn the owners of long-dormant accounts twice, then anonymise
 * what is still dormant. Scoped to what the {@code users} table models: the two warning
 * timestamps and the terminal anonymisation. Deleting the identity itself from {@code auth.users}
 * is deliberately out of scope - it needs a service-role key and reaches into a table Supabase
 * owns, not jZen (DECISIONS ADR-007).
 *
 * <p><strong>Finding and stamping are separate operations, and the warning happens in between</strong>
 * (ADR-008). {@code findAccountsDue*} only reads; {@link UserRetentionJob} fires the warning and
 * calls {@code stamp*} only for accounts whose warning was confirmed delivered. That ordering is
 * what guarantees no account is ever anonymised without having been warned: an undelivered warning
 * leaves the timestamp null, so the account is found again next cycle instead of ageing toward
 * erasure. Previously the stamp was written first and the mail was fired afterwards, which meant a
 * broken relay erased people silently.
 *
 * <p>Each stamp is its own short transaction, taken <em>after</em> the send has returned, so a
 * database transaction never stays open across an SMTP conversation - the same rule that keeps
 * {@code IdentityService}'s outbound Supabase call outside {@link UserStore}'s transaction.
 *
 * <p>Premium accounts are never touched, and an already-anonymised row is never reprocessed.
 *
 * <p>Anonymisation fires a {@link zen.identity.event.UserAnonymised} event per row so an
 * application can cascade its own cleanup of anything it keeps keyed on {@code userId} - the
 * mirror of {@link zen.identity.event.UserRegistered} for the account's exit rather than its entry
 * (DECISIONS ADR-007). See {@link #anonymiseExpiredAccounts()}.
 *
 * <p><strong>Every query is bounded, and the bound does not touch the ordering above.</strong> All
 * three used to load whatever matched, in full, into a list on a 256Mi instance — a shape whose
 * cost is set by how many dormant accounts exist rather than by anything the code does. Each now
 * reads at most {@code zen.identity.retention.batch-size} rows, <em>oldest first</em>, and the
 * phase order is unchanged: still find, then warn, then stamp only what was delivered. That is the
 * whole reason batching is safe here — a batch is a smaller find, not an earlier stamp, and an
 * account that does not fit in this cycle's batch is simply found again next cycle exactly as an
 * account whose warning failed to send already is.
 *
 * <p>Oldest-first is what makes the bound fair rather than arbitrary. Without an order, PostgreSQL
 * may return any matching rows, so a limit could keep handing back the same ones and starve the
 * rest indefinitely; ordering by the timestamp each phase measures dormancy from means the most
 * overdue account is always in the batch.
 *
 * <p>A saturated batch is logged at INFO with what remains implied, because a backlog that drains
 * silently over many cycles and a backlog that never drains look identical from outside.
 */
@ApplicationScoped
public class UserRetentionService {

  private static final Logger LOG = Logger.getLogger(UserRetentionService.class);

  /** Local-part prefix marking an anonymised account. */
  static final String ANONYMISED_EMAIL_PREFIX = "anon_";

  /** Reserved TLD (RFC 2606), so an anonymised address can never route anywhere. */
  private static final String ANONYMISED_EMAIL_DOMAIN = "@deleted.invalid";

  /** Replaces the nickname of an anonymised account. */
  static final String ANONYMISED_NICKNAME = "Deleted User";

  /**
   * Excludes rows already anonymised. The escape character matters: {@code _} is a single-character
   * wildcard in HQL, so an unescaped {@code 'anon_%'} would also exclude live addresses such as
   * {@code anonymous@example.com}.
   */
  private static final String NOT_ANONYMISED = " and email not like 'anon!_%' escape '!'";

  /** Retention never applies to paying accounts. */
  private static final String NOT_PREMIUM = " and isPremium = false";

  @ConfigProperty(name = "zen.identity.retention.warning-days")
  int warningDays;

  @ConfigProperty(name = "zen.identity.retention.final-warning-offset-days")
  int finalWarningOffsetDays;

  @ConfigProperty(name = "zen.identity.retention.anonymise-offset-days")
  int anonymiseOffsetDays;

  /**
   * The most rows any one phase of one cycle will read. Bounds memory on a 256Mi instance; the
   * remainder is picked up by the next cycle, which is safe precisely because the job is
   * idempotent and a find is not a stamp.
   */
  @ConfigProperty(name = "zen.identity.retention.batch-size")
  int batchSize;

  private final Event<UserAnonymised> anonymisations;

  @Inject
  public UserRetentionService(Event<UserAnonymised> anonymisations) {
    this.anonymisations = anonymisations;
  }

  /**
   * Finds up to one batch of accounts dormant longer than the configured window that have not been
   * warned yet, most overdue first. Read-only: nothing is stamped until the warning is confirmed
   * delivered.
   */
  @Transactional
  public List<AccountDeletionWarning> findAccountsDueFirstWarning() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(warningDays);
    List<User> due =
        User.find(
                "lastLoginAt < ?1 and deletionWarningSentAt is null"
                    + NOT_PREMIUM
                    + NOT_ANONYMISED
                    + " order by lastLoginAt asc",
                cutoff)
            .page(0, batchSize)
            .list();

    List<AccountDeletionWarning> warnings = new ArrayList<>(due.size());
    for (User user : due) {
      warnings.add(warning(user, Stage.FIRST, finalWarningOffsetDays + anonymiseOffsetDays));
    }
    if (!warnings.isEmpty()) {
      LOG.infof("Data retention: first warning due for %d dormant accounts", warnings.size());
      logIfBatchWasFull(warnings.size(), "first warning");
    }
    return warnings;
  }

  /**
   * Finds up to one batch of already-warned accounts that stayed dormant past the grace period and
   * have not had their final warning yet, most overdue first. Read-only, for the same reason as
   * above.
   */
  @Transactional
  public List<AccountDeletionWarning> findAccountsDueFinalWarning() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(finalWarningOffsetDays);
    List<User> due =
        User.find(
                "deletionWarningSentAt < ?1 and finalWarningSentAt is null"
                    + NOT_PREMIUM
                    + NOT_ANONYMISED
                    + " order by deletionWarningSentAt asc",
                cutoff)
            .page(0, batchSize)
            .list();

    List<AccountDeletionWarning> warnings = new ArrayList<>(due.size());
    for (User user : due) {
      warnings.add(warning(user, Stage.FINAL, anonymiseOffsetDays));
    }
    if (!warnings.isEmpty()) {
      LOG.infof("Data retention: final warning due for %d dormant accounts", warnings.size());
      logIfBatchWasFull(warnings.size(), "final warning");
    }
    return warnings;
  }

  /**
   * Records that the first warning reached its recipient. Only this stamp starts the countdown
   * toward the final warning, so it is written for delivered messages and nothing else.
   */
  @Transactional
  public void stampFirstWarningDelivered(UUID userId) {
    User user = User.findById(userId);
    if (user != null) {
      user.deletionWarningSentAt = OffsetDateTime.now();
    }
  }

  /**
   * Records that the final warning reached its recipient. This is the stamp
   * {@link #anonymiseExpiredAccounts()} counts from, so an account can only ever be anonymised on
   * the strength of a warning that was actually delivered.
   */
  @Transactional
  public void stampFinalWarningDelivered(UUID userId) {
    User user = User.findById(userId);
    if (user != null) {
      user.finalWarningSentAt = OffsetDateTime.now();
    }
  }

  /**
   * Anonymises every account that is still dormant after its final warning: the address becomes an
   * unroutable placeholder and the personal fields are cleared. The row itself is kept so foreign
   * references and aggregate counts stay intact.
   *
   * <p>Fires a {@link UserAnonymised} event per row, synchronously and from inside this same
   * transaction, so an application observer can cascade cleanup of its own tables keyed on
   * {@code userId}. Synchronous and in-transaction, not {@code fireAsync} as {@link
   * zen.identity.event.UserRegistered} is: an observer here is doing something that must either
   * commit with the anonymisation or roll it back, not something that can safely lag behind it.
   *
   * @return how many accounts were anonymised
   */
  @Transactional
  public int anonymiseExpiredAccounts() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(anonymiseOffsetDays);
    List<User> expired =
        User.find(
                "finalWarningSentAt < ?1"
                    + NOT_PREMIUM
                    + NOT_ANONYMISED
                    + " order by finalWarningSentAt asc",
                cutoff)
            .page(0, batchSize)
            .list();

    for (User user : expired) {
      // The user id, which is the primary key, is what makes the placeholder unique. A constant
      // here would make every anonymised row collide with every other one under the UNIQUE
      // constraint on users.email, and the second account of a batch could never be anonymised.
      user.email = ANONYMISED_EMAIL_PREFIX + user.id + ANONYMISED_EMAIL_DOMAIN;
      user.nickname = ANONYMISED_NICKNAME;
      user.displayName = null;
      user.avatarUrl = null;
      user.emailVerified = false;
      anonymisations.fire(new UserAnonymised(user.id));
    }
    if (!expired.isEmpty()) {
      LOG.infof("Data retention: anonymised %d expired accounts", expired.size());
      logIfBatchWasFull(expired.size(), "anonymisation");
    }
    return expired.size();
  }

  /**
   * Says so when a phase filled its batch, because from outside a backlog that drains over the next
   * few hourly cycles and a backlog that never drains look exactly alike. Retention windows are
   * measured in hundreds of days, so waiting a cycle costs nothing; not knowing does.
   */
  private void logIfBatchWasFull(int found, String phase) {
    if (found >= batchSize) {
      LOG.infof(
          "Data retention: the %s batch was full at %d; the remainder is carried to the next"
              + " cycle (zen.identity.retention.batch-size)",
          phase, batchSize);
    }
  }

  private AccountDeletionWarning warning(User user, Stage stage, int daysUntilAnonymisation) {
    return new AccountDeletionWarning(
        user.id, user.email, user.language, stage, daysUntilAnonymisation, new DeliveryReceipt());
  }
}
