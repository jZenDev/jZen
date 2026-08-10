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
 * augmentation degrade gracefully when the table is not there yet.
 *
 * <p><strong>The guard is latched, not repeated.</strong> It used to run on every authenticated
 * request, which is a second round trip to PostgreSQL on the hottest path in the application —
 * paid forever to answer a question that can only change once. So the probe runs until it first
 * answers yes and never again; while the answer is no it keeps asking, because that is the path
 * that is still waiting for something to change.
 *
 * <p><strong>Since ADR-038 this guard carries more weight than it used to.</strong> The absence of
 * the table was a startup condition the process resolved itself: {@code migrate-at-start=true}
 * created it before the HTTP server accepted anything, so the "no" branch was reachable for
 * milliseconds at most. In {@code %prod} Flyway no longer runs at boot at all — migration is a step
 * of the deploy, run as a one-shot job on this same image before the revision goes live
 * ({@code zen.identity.schema.MigrateOnlyRunner}). A process now assumes its schema is already
 * there. If a deploy ever ran in the wrong order, or migrated a different database than the one it
 * deployed against, this latch is the only thing between that and a confusing failure: role
 * augmentation degrades to "no such user" — every authenticated request is refused — instead of
 * every request dying inside Hibernate on a missing relation. It is a legible failure rather than a
 * safe one, and it self-heals the moment the table appears, because the latch only ever latches on
 * a yes.
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

  /**
   * What the augmentation path learned about the caller, including the row it read.
   *
   * <p>{@code user} is the entity {@code loadUser} loaded, detached once this method's transaction
   * commits. It is carried out so the request that follows does not read the identical row a second
   * time (see {@link RoleAugmentor}); it is a flat 17-column row with no associations, so there is
   * nothing lazy on it for a detached read to trip over.
   */
  public record UserSnapshot(boolean exists, UserRole role, String analyticsConsent, User user) {}

  @Transactional(Transactional.TxType.REQUIRED)
  public UserSnapshot loadUser(UUID userId) {
    if (!hasUsersTable()) {
      return new UserSnapshot(false, null, null, null);
    }
    User user = User.findById(userId);
    return user != null
        ? new UserSnapshot(true, user.role, user.analyticsConsent, user)
        : new UserSnapshot(false, null, null, null);
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
