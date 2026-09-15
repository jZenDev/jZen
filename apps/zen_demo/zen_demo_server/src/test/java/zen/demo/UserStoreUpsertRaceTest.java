package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.AuthException;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import zen.identity.user.User;
import zen.identity.user.UserStore;

/**
 * F8: {@code upsertOnLogin}'s two check-then-act races.
 *
 * <p>{@code aSecondFirstLoginFindsTheRowRatherThanCollidingOnIt} proves the PK half: the atomic
 * {@code INSERT ... ON CONFLICT (id) DO NOTHING} idiom means a second call for an id that already
 * exists finds the row instead of throwing the constraint violation the old check-then-act
 * {@code persist()} would have. This is a same-thread, sequential proof of the SQL idiom's
 * correctness rather than a genuine concurrent race: driving two real threads through a CDI
 * {@code @Transactional} proxy from a raw {@code ExecutorService} is not a pattern this codebase
 * uses anywhere else, and it was tried here first - it corrupted shared Hibernate/CDI state badly
 * enough to make an unrelated, already-passing test fail with a wrong bind value. {@code
 * aLoginCarryingAnotherProfilesEmailIsRefused} proves the email half returns a typed {@link
 * AuthException} instead of the unique index's constraint violation surfacing as an opaque 500.
 */
@QuarkusTest
class UserStoreUpsertRaceTest {

  @Inject UserStore userStore;

  @Test
  void aSecondFirstLoginFindsTheRowRatherThanCollidingOnIt() {
    UUID id = UUID.randomUUID();
    String email = "race-" + id + "@example.com";
    UserPayload payload = payload(id, email);

    UserStore.Upsert first = userStore.upsertOnLogin(payload, "en");
    assertTrue(first.created(), "the first call for a new id creates the row");

    // What used to throw a bare constraint violation from persist(): a second call for the same
    // id, as a racing concurrent first-login for the same identity would produce, must find the
    // row the atomic INSERT already settled rather than attempting a second INSERT.
    UserStore.Upsert second = userStore.upsertOnLogin(payload, "en");
    assertFalse(second.created(), "a second call for the same id must not report creating it again");

    User row = userStore.findById(id);
    assertEquals(email, row.email);
  }

  @Test
  void aLoginCarryingAnotherProfilesEmailIsRefused() {
    UUID ownerId = UUID.randomUUID();
    String sharedEmail = "taken-" + ownerId + "@example.com";
    userStore.upsertOnLogin(payload(ownerId, sharedEmail), "en");

    UUID challengerId = UUID.randomUUID();
    AuthException exception =
        assertThrows(
            AuthException.class,
            () -> userStore.upsertOnLogin(payload(challengerId, sharedEmail), "en"),
            "a second identity logging in with an address another profile already owns");

    assertEquals(409, exception.status());
    assertEquals("email_taken", exception.code());
    assertFalse(
        userExists(challengerId), "the challenger's row was never created by the refused login");
  }

  private boolean userExists(UUID id) {
    return userStore.findById(id) != null;
  }

  private static UserPayload payload(UUID id, String email) {
    return new UserPayload(id.toString(), email, "user", "2026-01-01T00:00:00Z", Map.of());
  }
}
