package dev.zen.demo;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import dev.zen.identity.security.RoleAugmentor;
import dev.zen.identity.user.User;
import dev.zen.identity.user.UserRole;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.security.identity.AuthenticationRequestContext;
import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.security.runtime.QuarkusPrincipal;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.smallrye.mutiny.Uni;
import jakarta.inject.Inject;
import io.quarkus.test.junit.QuarkusTest;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * Proves {@code RoleAugmentor} loads the role from the {@code users} table, not from the token.
 * There is no JWT in this test at all, so a role appearing on the augmented identity can only
 * have come from the database (ADR-029 in the donor; TA carried into jZen).
 */
@QuarkusTest
class RoleAugmentorTest {

  @Inject RoleAugmentor roleAugmentor;

  /** Runs the augmentor's blocking work synchronously on the calling thread. */
  private static final AuthenticationRequestContext SYNC =
      supplier -> Uni.createFrom().item(supplier.get());

  @Test
  void augment_addsRoleFromUsersTable() {
    UUID userId = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = userId;
              user.email = "admin@example.com";
              user.role = UserRole.ADMIN;
              user.language = "en";
              user.createdAt = OffsetDateTime.now();
              user.persist();
            });

    SecurityIdentity base =
        QuarkusSecurityIdentity.builder()
            .setPrincipal(new QuarkusPrincipal(userId.toString()))
            .build();

    SecurityIdentity augmented = roleAugmentor.augment(base, SYNC).await().indefinitely();

    assertTrue(augmented.hasRole("admin"), "role must be loaded from the users table");
  }

  @Test
  void augment_anonymousIdentityUnchanged() {
    SecurityIdentity anonymous = QuarkusSecurityIdentity.builder().setAnonymous(true).build();
    SecurityIdentity result = roleAugmentor.augment(anonymous, SYNC).await().indefinitely();
    assertTrue(result.isAnonymous());
    assertFalse(result.hasRole("admin"));
  }
}
