package zen.identity.user;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import zen.identity.event.AccountDeletionWarning;
import zen.identity.event.AccountDeletionWarning.Stage;

/**
 * GDPR Art. 5(1)(e) data retention: warn the owners of long-dormant accounts twice, then anonymise
 * what is still dormant. A focused re-implementation of the donor's retention pass
 * (../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/user/UserCleanupService.java and
 * .../DataRetentionJob.java), reduced to the part the {@code users} table actually models: the two
 * warning timestamps and the terminal anonymisation. The donor's fourth phase - deleting
 * unconfirmed identities through the Supabase admin API - needs a service-role key and is not part
 * of this step (DECISIONS ADR-007).
 *
 * <p>Each phase is its own short transaction that commits the timestamps and <em>returns</em> the
 * recipients rather than mailing them, exactly as {@code IdentityService} keeps the outbound
 * Supabase call outside {@link UserStore}'s transaction: a database transaction must not stay open
 * across an SMTP conversation, and a warning must never be mailed for a row whose stamp then rolls
 * back. {@link UserRetentionJob} fires the returned events once the stamp is committed.
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
   * Stamps {@code deletion_warning_sent_at} on every account dormant longer than the configured
   * window and returns one event per stamped account.
   */
  @Transactional
  public List<AccountDeletionWarning> stampFirstWarnings() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(warningDays);
    List<User> due =
        User.list(
            "lastLoginAt < ?1 and deletionWarningSentAt is null" + NOT_PREMIUM + NOT_ANONYMISED,
            cutoff);

    List<AccountDeletionWarning> warnings = new ArrayList<>(due.size());
    for (User user : due) {
      user.deletionWarningSentAt = OffsetDateTime.now();
      warnings.add(warning(user, Stage.FIRST, finalWarningOffsetDays + anonymiseOffsetDays));
    }
    if (!warnings.isEmpty()) {
      LOG.infof("Data retention: first warning due for %d dormant accounts", warnings.size());
    }
    return warnings;
  }

  /**
   * Stamps {@code final_warning_sent_at} on every already-warned account that stayed dormant and
   * returns one event per stamped account.
   */
  @Transactional
  public List<AccountDeletionWarning> stampFinalWarnings() {
    OffsetDateTime cutoff = OffsetDateTime.now().minusDays(finalWarningOffsetDays);
    List<User> due =
        User.list(
            "deletionWarningSentAt < ?1 and finalWarningSentAt is null" + NOT_PREMIUM + NOT_ANONYMISED,
            cutoff);

    List<AccountDeletionWarning> warnings = new ArrayList<>(due.size());
    for (User user : due) {
      user.finalWarningSentAt = OffsetDateTime.now();
      warnings.add(warning(user, Stage.FINAL, anonymiseOffsetDays));
    }
    if (!warnings.isEmpty()) {
      LOG.infof("Data retention: final warning due for %d dormant accounts", warnings.size());
    }
    return warnings;
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
        user.id, user.email, user.language, stage, daysUntilAnonymisation);
  }
}
