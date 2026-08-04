package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;

/**
 * The retention queries are bounded, and bounding them did not move the stamp.
 *
 * <p>Batching a pipeline whose whole correctness argument is an ordering is the kind of change that
 * can pass a "does it batch?" test and still be a regression, so both halves are asserted here and
 * the second one is the point. {@link UserRetentionService} finds, {@link UserRetentionJob} warns,
 * and only a confirmed delivery stamps — a limit on the find must not become a stamp taken before
 * the send (ADR-008, and the defect the service's own javadoc records fixing).
 *
 * <p>The mailer in this profile always throws, exactly as {@code RetentionDeliveryGateTest}'s does,
 * because that is what makes the ordering observable: if a batch were stamped as a batch rather
 * than per confirmed delivery, these accounts would carry timestamps despite nothing being sent.
 *
 * <p>The batch size is 2 here so the assertions can be about specific rows rather than about a
 * number. Production ships 500 (zen-identity's {@code microprofile-config.properties}); the
 * behaviour under test is the bound and the ordering, neither of which depends on the value.
 */
@QuarkusTest
@TestProfile(RetentionBatchingTest.TinyBatchProfile.class)
class RetentionBatchingTest {

  /** Matches {@code zen.identity.retention.batch-size} in {@link TinyBatchProfile}. */
  private static final int BATCH = 2;

  /** Longer than the configured 330-day dormancy window. */
  private static final int DORMANT_DAYS = 400;

  /**
   * Unambiguously the oldest row in the database. Dev Services provisions one Postgres for the
   * whole run, so the other retention suites' fixtures are visible here; they all sit at 400 days,
   * and a "most overdue" assertion has to be about a row nothing else can outrank.
   */
  private static final int MOST_OVERDUE_DAYS = 20_000;

  @Inject UserRetentionJob retentionJob;
  @Inject UserRetentionService retention;

  @Test
  void aFindReadsAtMostOneBatch() {
    // Deliberately more than one batch of eligible accounts.
    List<UUID> ids = persistDormant(BATCH + 3);

    int found = retention.findAccountsDueFirstWarning().size();

    assertEquals(
        BATCH,
        found,
        "the find is unbounded again — it loads whatever matches, which on a 256Mi instance is a"
            + " cost set by how many dormant accounts exist rather than by the code");
    assertTrue(ids.size() > BATCH, "the fixture must exceed one batch or this proves nothing");
  }

  @Test
  void aBatchedFindStillStampsNothingThatWasNotDelivered() {
    // THE assertion. Every account below is due a first warning, the relay is down, and the batch
    // is full. A batch stamped as a batch would leave timestamps here; find-then-stamp leaves none.
    List<UUID> ids = persistDormant(BATCH + 1);

    retentionJob.runCycle();

    for (UUID id : ids) {
      assertNull(
          reload(id).deletionWarningSentAt,
          "account " + id + " was stamped without a delivered warning. Batching moved the stamp"
              + " ahead of the send, which is the defect the find/stamp split exists to prevent"
              + " (ADR-008): thirty days later this account is erased having been told nothing.");
    }
  }

  @Test
  void theBacklogIsCarriedRatherThanDropped() {
    // A bound is only acceptable because the remainder survives to the next cycle. Nothing is
    // stamped (the relay is down), so every account stays eligible and the find keeps answering.
    persistDormant(BATCH + 3);

    assertEquals(BATCH, retention.findAccountsDueFirstWarning().size());
    assertEquals(
        BATCH,
        retention.findAccountsDueFirstWarning().size(),
        "the next cycle finds a full batch again — a limited find must not consume what it skipped");
  }

  @Test
  void theMostOverdueAccountIsAlwaysInTheBatch() {
    // Why the queries carry an explicit order. A LIMIT with no ORDER BY lets PostgreSQL return any
    // matching rows, so the same ones can come back forever while the oldest account is never
    // reached — a starvation that looks exactly like a working pipeline.
    UUID oldest = persistDormant(1, MOST_OVERDUE_DAYS).get(0);
    persistDormant(BATCH + 3);

    List<UUID> batch =
        retention.findAccountsDueFirstWarning().stream().map(w -> w.userId()).toList();

    assertTrue(
        batch.contains(oldest),
        "the most overdue account was not in the batch; the find has lost its oldest-first order"
            + " and a limit can now starve it indefinitely");
  }

  // --- helpers ---------------------------------------------------------------------------------

  private List<UUID> persistDormant(int count) {
    return persistDormant(count, DORMANT_DAYS);
  }

  private List<UUID> persistDormant(int count, int dormantDays) {
    List<UUID> ids = new ArrayList<>(count);
    for (int i = 0; i < count; i++) {
      UUID id = UUID.randomUUID();
      int offset = dormantDays + i;
      QuarkusTransaction.requiringNew()
          .run(
              () -> {
                User user = new User();
                user.id = id;
                user.email = "batch-" + id + "@example.com";
                user.language = "en";
                user.role = UserRole.USER;
                user.createdAt = OffsetDateTime.now().minusDays(offset + 1);
                user.lastLoginAt = OffsetDateTime.now().minusDays(offset);
                user.persist();
              });
      ids.add(id);
    }
    return ids;
  }

  private User reload(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }

  /** A tiny batch, and a mailer that refuses, for this class only. */
  public static class TinyBatchProfile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("zen.identity.retention.batch-size", String.valueOf(BATCH));
    }

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
