package zen.identity;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.user.User;
import zen.identity.user.UserRole;
import zen.proto.v1.Identity;

/**
 * F10: {@code lifecycle_state} is derived from the two retention timestamps and the anonymisation
 * placeholder, not hard-coded to {@code "active"}. A plain unit test against the MapStruct-generated
 * {@link IdentityMapperImpl} - no CDI container needed, the same reason {@code CsrfRulesTest} is
 * plain JUnit: the mapping is a pure function of the fields on {@link User}.
 */
class IdentityMapperTest {

  private final IdentityMapperImpl mapper = new IdentityMapperImpl();

  @Test
  void ordinaryAccountIsActive() {
    Identity identity = mapper.toProto(user(null, null));
    assertEquals("active", identity.getLifecycleState());
  }

  @Test
  void firstWarningSentMakesTheAccountWarned() {
    Identity identity = mapper.toProto(user(OffsetDateTime.now(), null));
    assertEquals("warned", identity.getLifecycleState());
  }

  @Test
  void finalWarningSentIsStillWarnedNotYetAnonymised() {
    Identity identity = mapper.toProto(user(OffsetDateTime.now().minusDays(20), OffsetDateTime.now()));
    assertEquals("warned", identity.getLifecycleState());
  }

  @Test
  void anonymisedPlaceholderEmailIsAnonymised() {
    User user = user(OffsetDateTime.now().minusDays(30), OffsetDateTime.now().minusDays(10));
    user.email = "anon_" + user.id + "@deleted.invalid";

    Identity identity = mapper.toProto(user);

    assertEquals("anonymised", identity.getLifecycleState());
  }

  @Test
  void anEmailThatMerelyStartsWithAnonPrefixIsNotMistakenForThePlaceholder() {
    /* The boundary the review named: a real address that happens to start "anon_" (e.g.
     * anon_fan@example.com) must not be classified as the anonymisation placeholder. */
    User user = user(null, null);
    user.email = "anon_fan@example.com";

    Identity identity = mapper.toProto(user);

    assertEquals("active", identity.getLifecycleState());
  }

  private static User user(OffsetDateTime deletionWarningSentAt, OffsetDateTime finalWarningSentAt) {
    User user = new User();
    user.id = UUID.randomUUID();
    user.email = "someone-" + UUID.randomUUID() + "@example.com";
    user.role = UserRole.USER;
    user.createdAt = OffsetDateTime.now();
    user.emailVerified = true;
    user.deletionWarningSentAt = deletionWarningSentAt;
    user.finalWarningSentAt = finalWarningSentAt;
    return user;
  }
}
