package zen.identity.user;

import zen.core.i18n.ZenLocales;
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

  /**
   * The reconciled row plus whether this call is what created it. {@code created} is what makes
   * "greet a user once" enforceable: a Supabase signup for an address that already has a local
   * profile must not fire {@code UserRegistered} a second time.
   */
  public record Upsert(User user, boolean created) {}

  /**
   * Creates the local profile row if absent, then stamps the login time. Returns the row together
   * with whether this call created it.
   *
   * <p>{@code preferredLanguage} seeds {@code users.language} on creation only - the column is the
   * user's own setting afterwards, so a later request in another language never overwrites it. It
   * is the raw tag from the registering request ({@code Accept-Language}); {@link ZenLocales}
   * narrows it to a supported locale, so a null or unknown tag yields the fallback rather than an
   * unrenderable value. That column is the sole locale source for email, which has no request to
   * read a header from.
   *
   * <p>Signing in also clears any pending data-retention warnings: the account is demonstrably
   * active again, so it must fall out of the deletion pipeline. The donor left the timestamps set
   * and went on to delete accounts whose owners had come back
   * (../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/user/UserCleanupService.java:143);
   * that is a bug, and STANDARDS forbids carrying donor bugs across.
   */
  @Transactional
  public Upsert upsertOnLogin(UserPayload payload, String preferredLanguage) {
    UUID id = UUID.fromString(payload.id());
    User user = User.findById(id);
    boolean created = user == null;
    if (created) {
      user = new User();
      user.id = id;
      user.email = payload.email();
      user.role = UserRole.USER;
      user.language = ZenLocales.resolve(preferredLanguage);
      user.emailVerified = false;
      user.isPrivate = false;
      user.acceptedTerms = false;
      user.isPremium = false;
      user.createdAt = OffsetDateTime.now();
      user.persist();
    }
    user.lastLoginAt = OffsetDateTime.now();
    user.deletionWarningSentAt = null;
    user.finalWarningSentAt = null;
    return new Upsert(user, created);
  }

  @Transactional
  public User findById(UUID id) {
    return User.findById(id);
  }
}
