package zen.identity.security;

import zen.identity.user.User;
import zen.identity.user.UserRole;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.util.UUID;

/**
 * Transactional wrapper for loading a user's role from the {@code users} table.
 *
 * <p>Extracted so {@link RoleAugmentor} calls a properly proxied CDI method that activates a
 * Hibernate session via {@code @Transactional}. The {@code to_regclass} guard lets role
 * augmentation degrade gracefully before Flyway has created the table (e.g. very early boot).
 *
 * <p><strong>The guard is latched, not repeated.</strong> It used to run on every authenticated
 * request, which is a second round trip to PostgreSQL on the hottest path in the application —
 * paid forever to answer a question that can only change once. A table's absence is a startup
 * condition: {@code quarkus.flyway.migrate-at-start=true} creates it before the HTTP server
 * accepts anything, and a {@code users} table that vanished mid-flight is not a state this class
 * could usefully degrade into anyway. So the probe runs until it first answers yes and never
 * again; while the answer is no it keeps asking, because that is the path that is still waiting
 * for something to change.
 *
 * <p><strong>The latch is an instance field on purpose, and a {@code static} one would be a
 * defect.</strong> GraalVM snapshots static state into the native image at build time, so a
 * static latch would carry whatever the build machine's answer was — where there is no database
 * at all — into every container that ever runs the image. An {@code @ApplicationScoped} bean is
 * constructed at runtime, so its fields start from the declared value in the running process.
 * {@code volatile} because requests are served on many event-loop threads and this is a
 * write-once flag: the worst a race can cost is one redundant probe, never a wrong answer.
 */
@ApplicationScoped
public class UserRoleLoader {

  private final EntityManager entityManager;

  /** Latches true the first time the table is seen, and is never cleared. See the class javadoc. */
  private volatile boolean usersTableConfirmed;

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
    if (usersTableConfirmed) {
      return true;
    }
    Object usersTable =
        entityManager.createNativeQuery("select to_regclass('public.users')").getSingleResult();
    if (usersTable == null) {
      return false;
    }
    usersTableConfirmed = true;
    return true;
  }
}
