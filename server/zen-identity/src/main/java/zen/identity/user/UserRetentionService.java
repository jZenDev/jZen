package zen.identity.user;

import jakarta.enterprise.context.ApplicationScoped;
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

/**
 * GDPR Art. 5(1)(e) data retention: warn the owners of long-dormant accounts twice, then anonymise
 * what is still dormant. A focused re-implementation of the donor's retention pass
 * (../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/user/UserCleanupService.java and
 * .../DataRetentionJob.java), reduced to the part the {@code users} table actually models: the two
 * warning timestamps and the terminal anonymisation. The donor's fourth phase - deleting
 * unconfirmed identities through the Supabase admin API - needs a service-role key and is not part
 * of this work (DECISIONS ADR-007).
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
   * Finds every account dormant longer than the configured window that has not been warned yet.
   * Read-only: nothing is stamped until the warning is confirmed delivered.
   */
  @Transactional
  public List<AccountDeletionWarning> findAccountsDueFirstWarning() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(warningDays);
    List<User> due =
        User.list(
            "lastLoginAt < ?1 and deletionWarningSentAt is null" + NOT_PREMIUM + NOT_ANONYMISED,
            cutoff);

    List<AccountDeletionWarning> warnings = new ArrayList<>(due.size());
    for (User user : due) {
      warnings.add(warning(user, Stage.FIRST, finalWarningOffsetDays + anonymiseOffsetDays));
    }
    if (!warnings.isEmpty()) {
      LOG.infof("Data retention: first warning due for %d dormant accounts", warnings.size());
    }
    return warnings;
  }

  /**
   * Finds every already-warned account that stayed dormant past the grace period and has not had
   * its final warning yet. Read-only, for the same reason as above.
   */
  @Transactional
  public List<AccountDeletionWarning> findAccountsDueFinalWarning() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(finalWarningOffsetDays);
    List<User> due =
        User.list(
            "deletionWarningSentAt < ?1 and finalWarningSentAt is null" + NOT_PREMIUM + NOT_ANONYMISED,
            cutoff);

    List<AccountDeletionWarning> warnings = new ArrayList<>(due.size());
    for (User user : due) {
      warnings.add(warning(user, Stage.FINAL, anonymiseOffsetDays));
    }
    if (!warnings.isEmpty()) {
      LOG.infof("Data retention: final warning due for %d dormant accounts", warnings.size());
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
   * @return how many accounts were anonymised
   */
  @Transactional
  public int anonymiseExpiredAccounts() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(anonymiseOffsetDays);
    List<User> expired =
        User.list("finalWarningSentAt < ?1" + NOT_PREMIUM + NOT_ANONYMISED, cutoff);

    for (User user : expired) {
      user.email = ANONYMISED_EMAIL_PREFIX + user.id + ANONYMISED_EMAIL_DOMAIN;
      user.nickname = ANONYMISED_NICKNAME;
      user.displayName = null;
      user.avatarUrl = null;
      user.emailVerified = false;
    }
    if (!expired.isEmpty()) {
      LOG.infof("Data retention: anonymised %d expired accounts", expired.size());
    }
    return expired.size();
  }

  private AccountDeletionWarning warning(User user, Stage stage, int daysUntilAnonymisation) {
    return new AccountDeletionWarning(
        user.id, user.email, user.language, stage, daysUntilAnonymisation, new DeliveryReceipt());
  }
}
