package zen.identity.security;

import zen.identity.user.UserRole;
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
 * <p>There is no request-scoped preload to read from: the role is loaded straight from
 * {@link UserRoleLoader} on each augmentation. The DB read runs on
 * {@code context.runBlocking} because the augmentor may be invoked on the I/O thread.
 *
 * <p>Requires a Jandex index (see pom.xml) so Quarkus discovers it from the jar.
 */
@ApplicationScoped
public class RoleAugmentor implements SecurityIdentityAugmentor {

  private static final Logger LOG = Logger.getLogger(RoleAugmentor.class);

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
    UserRole role;
    try {
      role = userRoleLoader.loadRole(userId);
    } catch (RuntimeException exception) {
      LOG.warnf(exception, "Skipping database role augmentation for user %s", userId);
      return identity;
    }
    if (role == null) {
      return identity;
    }
    return QuarkusSecurityIdentity.builder(identity).addRole(role.toString()).build();
  }
}
