package zen.identity.security;

import io.quarkus.security.identity.AuthenticationRequestContext;
import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.security.identity.SecurityIdentityAugmentor;
import io.quarkus.security.runtime.QuarkusSecurityIdentity;
import io.smallrye.mutiny.Uni;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.UUID;
import org.jboss.logging.Logger;

/**
 * Enriches the {@link SecurityIdentity} with the role stored in the {@code users} table.
 *
 * <p>After SmallRye JWT validates the Supabase token and sets the principal name to the JWT
 * {@code sub}, this augmentor loads the {@code role} column from the database and adds it to
 * the identity. Roles are managed by the application database, not carried in the token.
 *
 * <p>The role is loaded straight from {@link UserRoleLoader} on each augmentation. The DB read runs
 * on {@code context.runBlocking} because the augmentor may be invoked on the I/O thread.
 *
 * <h2>The row it read is carried forward, and that is not a cache</h2>
 *
 * <p>Loading the role means loading the {@code users} row. Every authenticated request that returns
 * user data then loaded the <em>identical</em> row again, in a second {@code @Transactional} unit —
 * byte-identical SQL, same parameter, and a second persistence context, so Hibernate's first-level
 * cache could not serve it. Against a cross-region database that was a measured ~135 ms per
 * authenticated request, paid to learn nothing new. So the loaded entity is attached to the
 * augmented identity under {@link #LOADED_USER}, and {@code IdentityService.currentUser} reads it
 * instead of issuing the second query.
 *
 * <p><b>Nothing survives the request.</b> A {@link SecurityIdentity} is built per authentication and
 * is reachable only from the request it was built for, so the entity is unreachable the moment that
 * request ends. The row is still read from the database on <em>every</em> request — which is what
 * ADR-017's revocation guarantee rests on, and why a role must never be read from the token nor held
 * in anything application-scoped. This shortens one request; it does not remember anything between
 * two.
 *
 * <p>Requires a Jandex index (see pom.xml) so Quarkus discovers it from the jar.
 */
@ApplicationScoped
public class RoleAugmentor implements SecurityIdentityAugmentor {

  private static final Logger LOG = Logger.getLogger(RoleAugmentor.class);

  /**
   * Identity attribute holding the {@code users} row this augmentation read, for the rest of the
   * same request to use rather than re-read. Absent when the caller is anonymous, when the
   * principal is not a user id, when there is no local profile yet, or when the load failed — every
   * reader must therefore treat it as optional and fall back to loading the row itself.
   */
  public static final String LOADED_USER = "zen.identity.loaded-user";

  private final UserRoleLoader userRoleLoader;

  @Inject
  public RoleAugmentor(UserRoleLoader userRoleLoader) {
    this.userRoleLoader = userRoleLoader;
  }

  @Override
  public Uni<SecurityIdentity> augment(
      SecurityIdentity identity, AuthenticationRequestContext context) {
    if (identity.isAnonymous()) {
      return Uni.createFrom().item(identity);
    }

    UUID userId;
    try {
      userId = UUID.fromString(identity.getPrincipal().getName());
    } catch (IllegalArgumentException e) {
      // Principal is not a Supabase user id (e.g. a service identity); leave it unchanged.
      return Uni.createFrom().item(identity);
    }

    return context.runBlocking(() -> addRoleFromDatabase(identity, userId));
  }

  private SecurityIdentity addRoleFromDatabase(SecurityIdentity identity, UUID userId) {
    UserRoleLoader.UserSnapshot snapshot;
    try {
      snapshot = userRoleLoader.loadUser(userId);
    } catch (RuntimeException exception) {
      LOG.warnf(exception, "Skipping database role augmentation for user %s", userId);
      return identity;
    }
    if (snapshot.user() == null) {
      return identity;
    }
    QuarkusSecurityIdentity.Builder builder =
        QuarkusSecurityIdentity.builder(identity).addAttribute(LOADED_USER, snapshot.user());
    if (snapshot.role() != null) {
      builder.addRole(snapshot.role().toString());
    }
    return builder.build();
  }
}
