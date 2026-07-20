package zen.identity.security;

import zen.identity.user.User;
import zen.identity.user.UserRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.util.UUID;

/**
 * Transactional wrapper for loading a user's role from the {@code users} table. Ported from
 * ../BugEater/.../application/security/UserRoleLoader.java.
 *
 * <p>Extracted so {@link RoleAugmentor} calls a properly proxied CDI method that activates a
 * Hibernate session via {@code @Transactional}. The {@code to_regclass} guard lets role
 * augmentation degrade gracefully before Flyway has created the table (e.g. very early boot).
 */
@ApplicationScoped
public class UserRoleLoader {

  private final EntityManager entityManager;

  @Inject
  public UserRoleLoader(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  public record UserSnapshot(boolean exists, UserRole role, String analyticsConsent) {}

  @Transactional(Transactional.TxType.REQUIRED)
  public UserSnapshot loadUser(UUID userId) {
    if (!hasUsersTable()) {
      return new UserSnapshot(false, null, null);
    }
    User user = User.findById(userId);
    return user != null
        ? new UserSnapshot(true, user.role, user.analyticsConsent)
        : new UserSnapshot(false, null, null);
  }

  @Transactional(Transactional.TxType.REQUIRED)
  public UserRole loadRole(UUID userId) {
    return loadUser(userId).role();
  }

  @Transactional(Transactional.TxType.REQUIRED)
  public boolean userExists(UUID userId) {
    return loadUser(userId).exists();
  }

  private boolean hasUsersTable() {
    Object usersTable =
        entityManager.createNativeQuery("select to_regclass('public.users')").getSingleResult();
    return usersTable != null;
  }
}
