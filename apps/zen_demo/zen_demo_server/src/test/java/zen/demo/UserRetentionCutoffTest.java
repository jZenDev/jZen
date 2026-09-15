package zen.demo;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.enterprise.inject.Alternative;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.time.Clock;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Consumer;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.identity.event.AccountDeletionWarning;
import zen.identity.user.User;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;

/**
 * Each retention cutoff is exact, proven at a clock the test owns instead of tolerated as
 * approximately right (ADR-051, the F15 follow-up).
 *
 * <p>{@link UserRetentionService} compares timestamps with a strict {@code <}, so an account
 * exactly at a window boundary is not yet due and an account one second past it is. That is
 * indistinguishable from an off-by-one-day bug in a test that only checks "roughly 330 days" —
 * the point of driving the clock is to plant a row on either side of the exact instant the
 * service computes and watch the boundary hold.
 *
 * <p>Uses a driven {@link Clock}, the same mechanism {@code JobSchedulerTest} uses for {@code
 * JobScheduler}: replacing the CDI-produced {@code Clock} rather than instantiating {@link
 * UserRetentionService} by hand, because its queries run through Panache active-record methods
 * that need a live persistence context. {@code BurstLimiterTest}'s plain {@code MutableClock},
 * constructed directly, is not available to a Panache-backed service under test.
 *
 * <p>Fixtures are matched by id (not by count), because Dev Services shares one Postgres across
 * the whole run and other retention suites' rows are visible here too ({@code
 * RetentionBatchingTest} documents the same constraint).
 */
@QuarkusTest
@TestProfile(UserRetentionCutoffTest.DrivenClockProfile.class)
class UserRetentionCutoffTest {

  private static final OffsetDateTime NOW =
      OffsetDateTime.of(2026, 9, 15, 12, 0, 0, 0, ZoneOffset.UTC);

  /** Matches {@code zen.identity.retention.warning-days} in production config. */
  private static final int WARNING_DAYS = 330;

  /** Matches {@code zen.identity.retention.final-warning-offset-days} in production config. */
  private static final int FINAL_WARNING_OFFSET_DAYS = 23;

  /** Matches {@code zen.identity.retention.anonymise-offset-days} in production config. */
  private static final int ANONYMISE_OFFSET_DAYS = 7;

  @Inject UserRetentionService retention;

  @BeforeEach
  void resetClock() {
    DrivenClock.set(NOW);
  }

  @Test
  void firstWarningExcludesTheExactCutoffAndIncludesOneSecondPastIt() {
    UUID atCutoff = persistUser(u -> u.lastLoginAt = NOW.minusDays(WARNING_DAYS));
    UUID pastCutoff = persistUser(u -> u.lastLoginAt = NOW.minusDays(WARNING_DAYS).minusSeconds(1));

    Set<UUID> due = idsOf(retention.findAccountsDueFirstWarning());

    assertFalse(
        due.contains(atCutoff),
        "an account exactly at the warning-days cutoff is not yet dormant long enough");
    assertTrue(
        due.contains(pastCutoff),
        "an account one second past the warning-days cutoff is due its first warning");
  }

  @Test
  void finalWarningExcludesTheExactCutoffAndIncludesOneSecondPastIt() {
    UUID atCutoff =
        persistUser(u -> u.deletionWarningSentAt = NOW.minusDays(FINAL_WARNING_OFFSET_DAYS));
    UUID pastCutoff =
        persistUser(
            u ->
                u.deletionWarningSentAt =
                    NOW.minusDays(FINAL_WARNING_OFFSET_DAYS).minusSeconds(1));

    Set<UUID> due = idsOf(retention.findAccountsDueFinalWarning());

    assertFalse(
        due.contains(atCutoff),
        "an account exactly at the final-warning-offset cutoff has not yet cleared the grace"
            + " period");
    assertTrue(
        due.contains(pastCutoff),
        "an account one second past the final-warning-offset cutoff is due its final warning");
  }

  @Test
  void anonymisationExcludesTheExactCutoffAndIncludesOneSecondPastIt() {
    UUID atCutoff = persistUser(u -> u.finalWarningSentAt = NOW.minusDays(ANONYMISE_OFFSET_DAYS));
    UUID pastCutoff =
        persistUser(
            u -> u.finalWarningSentAt = NOW.minusDays(ANONYMISE_OFFSET_DAYS).minusSeconds(1));

    retention.anonymiseExpiredAccounts();

    assertFalse(
        UserRetentionService.isAnonymised(reload(atCutoff)),
        "an account exactly at the anonymise-offset cutoff has not yet cleared its final grace"
            + " period");
    assertTrue(
        UserRetentionService.isAnonymised(reload(pastCutoff)),
        "an account one second past the anonymise-offset cutoff is anonymised");
  }

  // --- helpers ---------------------------------------------------------------------------------

  private UUID persistUser(Consumer<User> customize) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = "cutoff-" + id + "@example.com";
              user.language = "en";
              user.role = UserRole.USER;
              user.createdAt = NOW.minusDays(400);
              user.lastLoginAt = NOW.minusDays(1);
              customize.accept(user);
              user.persist();
            });
    return id;
  }

  private User reload(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }

  private static Set<UUID> idsOf(List<AccountDeletionWarning> warnings) {
    return warnings.stream().map(AccountDeletionWarning::userId).collect(Collectors.toSet());
  }

  public static class DrivenClockProfile implements QuarkusTestProfile {
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      return Set.of(DrivenClock.class);
    }
  }

  /**
   * A clock the test moves by hand, replacing the framework's {@code ZenClockProducer}. Mirrors
   * {@code JobSchedulerTest.DrivenClock}.
   */
  @Alternative
  @Singleton
  public static class DrivenClock {

    private static final AtomicReference<Instant> NOW_REF = new AtomicReference<>(NOW.toInstant());

    static void set(OffsetDateTime instant) {
      NOW_REF.set(instant.toInstant());
    }

    @Produces
    @Singleton
    public Clock drivenClock() {
      return new Clock() {
        @Override
        public ZoneId getZone() {
          return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
          return this;
        }

        @Override
        public Instant instant() {
          return NOW_REF.get();
        }
      };
    }
  }
}
