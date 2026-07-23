package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.MockMailbox;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRole;

/**
 * Proves the GDPR data-retention cycle (ROADMAP step 6, DECISIONS ADR-007): dormant accounts are
 * warned twice in their own language and then anonymised, while paying accounts are left alone.
 *
 * <p>Nothing schedules the cycle behind a test's back - {@code zen.jobs.tick.cron} is off in
 * {@code %test} - and each case drives {@link UserRetentionJob#runCycle()} directly, which makes
 * the whole flow deterministic. Mail is captured by {@link MockMailbox}.
 *
 * <p>Since ADR-008 the warning observer is <em>synchronous</em>, because the cycle now stamps an
 * account only once delivery is confirmed. So the mail is in the mailbox by the time
 * {@code runCycle()} returns, and the polling this test used to need is gone.
 */
@QuarkusTest
class UserRetentionTest {

  /** Longer than the configured 330-day dormancy window. */
  private static final int DORMANT_DAYS = 400;

  /** Longer than the configured 23-day gap between the first and the final warning. */
  private static final int SINCE_FIRST_WARNING_DAYS = 30;

  /** Longer than the configured 7-day gap between the final warning and anonymisation. */
  private static final int SINCE_FINAL_WARNING_DAYS = 10;

  @Inject UserRetentionJob retentionJob;
  @Inject MockMailbox mailbox;

  @BeforeEach
  void clearMailbox() {
    mailbox.clear();
  }

  @Test
  void dormantAccount_getsFirstWarningInItsOwnLanguage() {
    String email = "retention-first-uk@example.com";
    UUID id = persistUser(email, "uk", dormant(), null, null, false);

    retentionJob.runCycle();

    Mail mail = singleMailTo(email);
    /* 23 days to the final warning plus 7 more to anonymisation. */
    assertEquals("Ваш обліковий запис jZen буде заархівовано через 30 днів", mail.getSubject());
    assertTrue(mail.getHtml().contains("30"), "the body states the same countdown as the subject");
    assertNotNull(reload(id).deletionWarningSentAt, "the first warning is stamped");
    assertNull(reload(id).finalWarningSentAt, "the final warning is not due yet");
  }

  @Test
  void alreadyWarnedAccount_getsFinalWarningAndIsThenAnonymised() {
    String email = "retention-final-en@example.com";
    UUID id =
        persistUser(
            email, "en", dormant(), OffsetDateTime.now().minusDays(SINCE_FIRST_WARNING_DAYS), null, false);

    retentionJob.runCycle();

    Mail mail = singleMailTo(email);
    assertEquals("Last chance - your jZen account is deleted in 7 days", mail.getSubject());
    assertNotNull(reload(id).finalWarningSentAt, "the final warning is stamped");
    assertEquals(email, reload(id).email, "a warned account is not anonymised in the same cycle");

    /* Backdate the final warning past the last grace period; the next cycle must anonymise. */
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = User.findById(id);
              user.finalWarningSentAt = OffsetDateTime.now().minusDays(SINCE_FINAL_WARNING_DAYS);
            });

    assertEquals(1, retentionJob.runCycle(), "one account anonymised");
    User anonymised = reload(id);
    assertEquals("anon_" + id + "@deleted.invalid", anonymised.email);
    assertEquals("Deleted User", anonymised.nickname);
  }

  @Test
  void premiumAccount_isNeverWarned() {
    String email = "retention-premium@example.com";
    UUID id = persistUser(email, "en", dormant(), null, null, true);

    retentionJob.runCycle();

    assertNull(reload(id).deletionWarningSentAt, "retention does not apply to paying accounts");
    assertEquals(List.of(), mailbox.getMailsSentTo(email));
  }

  /**
   * The "already anonymised" filter matches the literal prefix {@code anon_}. Without an escape
   * clause the underscore is an HQL wildcard, and this perfectly live address would be skipped
   * forever.
   */
  @Test
  void addressBeginningWithAnon_isStillWarned() {
    String email = "anonymous@example.com";
    UUID id = persistUser(email, "en", dormant(), null, null, false);

    retentionJob.runCycle();

    assertNotNull(reload(id).deletionWarningSentAt);
    assertEquals("Your jZen account will be archived in 30 days", singleMailTo(email).getSubject());
  }

  /**
   * The idempotency every {@code ZenJob} promises, asserted rather than assumed. An external
   * scheduler delivers at-least-once and jZen never suppresses a retry, so a duplicate trigger is a
   * normal event: the second cycle must warn nobody twice and anonymise nobody twice.
   */
  @Test
  void runningTheCycleTwiceIsHarmless() {
    String warned = "retention-idempotent-warned@example.com";
    UUID warnedId = persistUser(warned, "en", dormant(), null, null, false);
    String expiring = "retention-idempotent-expiring@example.com";
    UUID expiringId =
        persistUser(
            expiring,
            "en",
            dormant(),
            OffsetDateTime.now().minusDays(SINCE_FIRST_WARNING_DAYS),
            OffsetDateTime.now().minusDays(SINCE_FINAL_WARNING_DAYS),
            false);

    assertEquals(1, retentionJob.runCycle(), "the first cycle anonymises the expired account");
    OffsetDateTime firstStamp = reload(warnedId).deletionWarningSentAt;
    assertNotNull(firstStamp);

    assertEquals(0, retentionJob.runCycle(), "the second cycle finds nothing left to anonymise");

    assertEquals(
        firstStamp, reload(warnedId).deletionWarningSentAt, "the warning stamp is not moved");
    assertEquals(1, mailbox.getMailsSentTo(warned).size(), "and nobody is warned twice");
    assertEquals(
        "anon_" + expiringId + "@deleted.invalid",
        reload(expiringId).email,
        "an already-anonymised account is not reprocessed");
  }

  private OffsetDateTime dormant() {
    return OffsetDateTime.now().minusDays(DORMANT_DAYS);
  }

  private UUID persistUser(
      String email,
      String language,
      OffsetDateTime lastLoginAt,
      OffsetDateTime deletionWarningSentAt,
      OffsetDateTime finalWarningSentAt,
      boolean premium) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = email;
              user.language = language;
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now().minusDays(DORMANT_DAYS + 1);
              user.lastLoginAt = lastLoginAt;
              user.deletionWarningSentAt = deletionWarningSentAt;
              user.finalWarningSentAt = finalWarningSentAt;
              user.isPremium = premium;
              user.persist();
            });
    return id;
  }

  private User reload(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }

  /** The warning observer is synchronous, so the message is already there when the cycle returns. */
  private Mail singleMailTo(String address) {
    List<Mail> mails = mailbox.getMailsSentTo(address);
    if (mails.isEmpty()) {
      return fail("No mail reached " + address);
    }
    assertEquals(1, mails.size(), "exactly one message expected for " + address);
    return mails.getFirst();
  }
}
