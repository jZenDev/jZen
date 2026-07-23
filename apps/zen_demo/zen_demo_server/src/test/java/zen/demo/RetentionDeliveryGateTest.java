package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.enterprise.inject.Alternative;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.time.OffsetDateTime;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRole;

/**
 * The GDPR hole ADR-007 knowingly accepted, now closed: <strong>no account is anonymised without a
 * warning that was actually delivered.</strong>
 *
 * <p>The hazard was concrete rather than theoretical. {@code EmailService.send} is deliberately
 * non-fatal - it returns {@code false} rather than throwing, so that a mail problem can never fail
 * the business action that triggered it - and the retention cycle used to stamp its timestamps
 * before firing the warning asynchronously. A relay that was down or misconfigured therefore
 * advanced every account's clock while sending nothing, and thirty days later erased people who had
 * never been told. Warning someone is the entire legal basis for erasing their data.
 *
 * <p>The outage is a real CDI alternative that always throws, enabled only for this class's profile
 * (the {@code EmailFailureTest} pattern), so the suite stays hermetic and never touches SMTP.
 */
@QuarkusTest
@TestProfile(RetentionDeliveryGateTest.UnreachableMailerProfile.class)
class RetentionDeliveryGateTest {

  /** Longer than the configured 330-day dormancy window. */
  private static final int DORMANT_DAYS = 400;

  /** Longer than the configured 23-day gap between the first and the final warning. */
  private static final int SINCE_FIRST_WARNING_DAYS = 30;

  /** Longer than the configured 7-day gap between the final warning and anonymisation. */
  private static final int SINCE_FINAL_WARNING_DAYS = 10;

  @Inject UserRetentionJob retentionJob;

  @Test
  void aFirstWarningThatCouldNotBeSentDoesNotStartTheClock() {
    String email = unique("gate-first");
    UUID id = persistUser(email, dormant(), null, null);

    retentionJob.runCycle();

    assertNull(
        reload(id).deletionWarningSentAt,
        "an undelivered warning must not count as a warning, or the countdown starts in silence");
  }

  /**
   * The failure that mattered most: this account was warned once, is now due its final warning, and
   * the relay is down. It must not reach anonymisation, however many cycles run.
   */
  @Test
  void anAccountIsNeverAnonymisedWhenItsFinalWarningFailedToSend() {
    String email = unique("gate-final");
    UUID id =
        persistUser(email, dormant(), OffsetDateTime.now().minusDays(SINCE_FIRST_WARNING_DAYS), null);

    retentionJob.runCycle();

    assertNull(reload(id).finalWarningSentAt, "the final warning was not delivered, so not stamped");
    assertEquals(email, reload(id).email, "and the account is untouched");

    /* Time passing changes nothing: with no delivered final warning there is no clock to expire. */
    retentionJob.runCycle();
    retentionJob.runCycle();

    assertNull(reload(id).finalWarningSentAt);
    assertEquals(
        email,
        reload(id).email,
        "an account whose warning never went out is never erased, however often the job runs");
  }

  /**
   * The gate blocks unwarned accounts, not the retention cycle itself. This account was properly
   * warned before the relay broke, so its countdown is legitimate and anonymisation still happens -
   * otherwise a permanently broken mailer would quietly suspend GDPR compliance instead of
   * enforcing it.
   */
  @Test
  void anAccountThatWasWarnedBeforeTheOutageIsStillAnonymised() {
    String email = unique("gate-warned");
    UUID id =
        persistUser(
            email,
            dormant(),
            OffsetDateTime.now().minusDays(SINCE_FIRST_WARNING_DAYS),
            OffsetDateTime.now().minusDays(SINCE_FINAL_WARNING_DAYS));

    retentionJob.runCycle();

    User anonymised = reload(id);
    assertEquals("anon_" + id + "@deleted.invalid", anonymised.email);
    assertNotEquals(email, anonymised.email);
  }

  // --- helpers ---------------------------------------------------------------------------------

  private static String unique(String prefix) {
    return prefix + "-" + UUID.randomUUID() + "@example.com";
  }

  private OffsetDateTime dormant() {
    return OffsetDateTime.now().minusDays(DORMANT_DAYS);
  }

  private UUID persistUser(
      String email,
      OffsetDateTime lastLoginAt,
      OffsetDateTime deletionWarningSentAt,
      OffsetDateTime finalWarningSentAt) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = email;
              user.language = "en";
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now().minusDays(DORMANT_DAYS + 1);
              user.lastLoginAt = lastLoginAt;
              user.deletionWarningSentAt = deletionWarningSentAt;
              user.finalWarningSentAt = finalWarningSentAt;
              user.persist();
            });
    return id;
  }

  private User reload(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }

  /** Enables {@link UnreachableMailer} for this class only, leaving the other suites unaffected. */
  public static class UnreachableMailerProfile implements QuarkusTestProfile {
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      return Set.of(UnreachableMailer.class);
    }
  }

  /** A mailer that behaves like an SMTP server refusing connections. */
  @Alternative
  @Singleton
  public static class UnreachableMailer implements Mailer {
    @Override
    public void send(Mail... mails) {
      throw new IllegalStateException("SMTP unavailable");
    }
  }
}
