package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.user.User;
import zen.identity.user.UserRetentionJob;
import zen.identity.user.UserRole;

/**
 * {@code users.email} is UNIQUE at the database, and data retention still works alongside it.
 *
 * <p>Proved by trying, in the manner of {@code DatabasePrivilegeTest}, rather than by reading the
 * migration: a constraint that was written but not applied, or applied to the wrong column, reads
 * identically in source and behaves completely differently.
 *
 * <p><strong>The second test is the one that could have been forgotten.</strong> A UNIQUE
 * constraint and an anonymisation routine are written by different people at different times, and
 * they meet only in production. If the anonymised placeholder were a constant rather than one
 * derived from the primary key, the first account of a batch would anonymise and every one after
 * it would violate the constraint, roll the transaction back, and take the whole retention cycle
 * with it — inside an hourly job, where the only symptom is that erasure quietly stops happening.
 */
@QuarkusTest
class UserEmailUniquenessTest {

  @Inject UserRetentionJob retentionJob;

  @Test
  void twoProfilesCannotClaimTheSameAddress() {
    String shared = "duplicate-" + UUID.randomUUID() + "@example.com";
    persist(UUID.randomUUID(), shared, null, null, null);

    assertThrows(
        RuntimeException.class,
        () -> persist(UUID.randomUUID(), shared, null, null, null),
        "a second profile took the same address. Without the constraint two Supabase identities"
            + " can claim one mailbox, and every email jZen sends to it reaches whichever row was"
            + " read first");
  }

  @Test
  void aDifferentAddressIsStillAccepted() {
    // The mirror direction. A constraint on the wrong column, or one that somehow refused
    // everything, would pass the test above for entirely the wrong reason.
    UUID id = UUID.randomUUID();
    persist(id, "unique-" + id + "@example.com", null, null, null);
    assertEquals(1, count(id), "an ordinary distinct address must still insert");
  }

  @Test
  void anonymisingSeveralAccountsInOneCycleDoesNotCollide() {
    // Three accounts, all past their delivered final warning, all anonymised by one cycle. With a
    // constant placeholder the second insert would violate users_email_key and roll back the
    // transaction, so this asserts three DISTINCT results rather than merely three survivors.
    List<UUID> ids = new ArrayList<>();
    for (int i = 0; i < 3; i++) {
      UUID id = UUID.randomUUID();
      persist(
          id,
          "erase-" + id + "@example.com",
          OffsetDateTime.now().minusDays(400),
          OffsetDateTime.now().minusDays(30),
          OffsetDateTime.now().minusDays(10));
      ids.add(id);
    }

    retentionJob.runCycle();

    Set<String> addresses = new HashSet<>();
    for (UUID id : ids) {
      User row = reload(id);
      assertNotEquals(
          "erase-" + id + "@example.com", row.email, "account " + id + " was not anonymised");
      assertTrue(
          addresses.add(row.email),
          "two anonymised accounts ended up with the same address (" + row.email + "). The"
              + " placeholder has stopped embedding the user id, so users_email_key now refuses"
              + " every erasure after the first and GDPR anonymisation fails inside an hourly job");
    }
    assertEquals(3, addresses.size());
  }

  // --- helpers ---------------------------------------------------------------------------------

  private void persist(
      UUID id,
      String email,
      OffsetDateTime lastLoginAt,
      OffsetDateTime deletionWarningSentAt,
      OffsetDateTime finalWarningSentAt) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = email;
              user.language = "en";
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now();
              user.lastLoginAt = lastLoginAt;
              user.deletionWarningSentAt = deletionWarningSentAt;
              user.finalWarningSentAt = finalWarningSentAt;
              user.persist();
            });
  }

  private long count(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.count("id", id));
  }

  private User reload(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }
}
