package zen.identity.user;

import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.OffsetDateTime;
import java.util.UUID;

/**
 * Persistence for the local {@code users} profile row that mirrors a Supabase
 * {@code auth.users} identity.
 *
 * <p>Supabase owns authentication ({@code auth.users}); jZen owns the application profile and
 * the role. On first login/registration there is no local row yet, so the session flows
 * upsert one keyed by the Supabase user id. This is a separate transactional bean (not folded
 * into {@code IdentityService}) so the DB transaction does not wrap the outbound Supabase HTTP
 * call, and so the {@code @Transactional} proxy is honored (self-invocation would bypass it).
 */
@ApplicationScoped
public class UserStore {

  /** Creates the local profile row if absent, then stamps the login time. Returns the row. */
  @Transactional
  public User upsertOnLogin(UserPayload payload) {
    UUID id = UUID.fromString(payload.id());
    User user = User.findById(id);
    if (user == null) {
      user = new User();
      user.id = id;
      user.email = payload.email();
      user.role = UserRole.USER;
      user.language = "en";
      user.emailVerified = false;
      user.isPrivate = false;
      user.acceptedTerms = false;
      user.isPremium = false;
      user.createdAt = OffsetDateTime.now();
      user.persist();
    }
    user.lastLoginAt = OffsetDateTime.now();
    return user;
  }

  @Transactional
  public User findById(UUID id) {
    return User.findById(id);
  }
}
