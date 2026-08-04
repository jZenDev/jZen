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
   * <p>The email address and the confirmation flag go the other way: they belong to Supabase, so
   * they are reconciled on <em>every</em> call. Language is the user's own setting and is seeded
   * once; an address is not a setting jZen owns at all.
   *
   * <p>Signing in also clears any pending data-retention warnings: the account is demonstrably
   * active again, so it must fall out of the deletion pipeline. Leaving the stamps set would
   * anonymise an account whose owner had demonstrably come back.
   */
  @Transactional
  public Upsert upsertOnLogin(UserPayload payload, String preferredLanguage) {
    UUID id = UUID.fromString(payload.id());
    User user = User.findById(id);
    boolean created = user == null;
    if (created) {
      user = new User();
      user.id = id;
      user.role = UserRole.USER;
      user.language = ZenLocales.resolve(preferredLanguage);
      user.isPrivate = false;
      user.acceptedTerms = false;
      user.isPremium = false;
      user.createdAt = OffsetDateTime.now();
    }
    // Both of these are Supabase's to state, so both are reconciled on every call rather than
    // written once at creation - a profile that drifts from the identity provider is a profile
    // nobody can trust.
    //
    // The address is the one that used to be written only on creation, which meant a user who
    // changed it in Supabase kept the old one here forever: every email jZen sent went to an
    // address the user had abandoned, and the admin panel showed one that was simply wrong.
    // Confirmation state is the same reconciliation one line down - a user who confirms after
    // registering has emailVerified flip true on their next authenticated request.
    //
    // Blank is not a value to copy. The column is NOT NULL, and GoTrue's bare-user shape can
    // arrive without an address; overwriting a known address with nothing would turn a stale row
    // into an unusable one and take the constraint down with it.
    if (payload.email() != null && !payload.email().isBlank()) {
      user.email = payload.email();
    }
    user.emailVerified = payload.emailVerified();
    user.lastLoginAt = OffsetDateTime.now();
    user.deletionWarningSentAt = null;
    user.finalWarningSentAt = null;
    if (created) {
      // Persisted last, after the provider fields are on the instance. A row is built and then
      // written once; persisting a half-filled entity and patching it afterwards writes an INSERT
      // with a null email, which the NOT NULL column refuses.
      user.persist();
    }
    return new Upsert(user, created);
  }

  @Transactional
  public User findById(UUID id) {
    return User.findById(id);
  }
}
