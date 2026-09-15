package zen.identity.user;

import zen.core.i18n.ZenLocales;
import zen.identity.AuthException;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import io.quarkus.hibernate.orm.panache.Panache;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;

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
   * The languages <em>this application</em> supports, as language tags (ADR-044).
   *
   * <p>Absent, it is what jZen itself ships. An application that renders more languages than the
   * framework has strings for sets {@code zen.i18n.supported} and {@code users.language} then
   * holds those tags: the framework must not clamp a user's language to its own inventory, or a
   * Polish user's stored preference silently becomes English and every later email is wrong.
   *
   * <p>Runtime config rather than a constant because the server is the runtime-config tier - one
   * binary serves every client (BLUEPRINT, "The compile-time config rule").
   */
  @Inject
  @ConfigProperty(name = "zen.i18n.supported")
  Optional<List<String>> supportedLocales;

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
   * narrows it to one of {@link #supportedLocales}, so a null or unknown tag yields the fallback
   * rather than an unrenderable value - while a language the application supports and jZen does
   * not is kept rather than clamped. That column is the sole locale source for email, which has no request to
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
  /**
   * The application's locale set, defaulting to jZen's own inventory when unconfigured.
   *
   * <p>An <em>empty</em> value counts as unconfigured, not as "no languages at all". Cloud Run
   * deploys pass the variable through unconditionally ({@code ZEN_I18N_SUPPORTED=${...:-}}), so
   * the common case in production is a variable that is present and blank; reading that as an
   * empty set would resolve every user to English while looking perfectly configured.
   */
  private List<String> supported() {
    return supportedLocales.filter(set -> !set.isEmpty()).orElse(ZenLocales.SHIPPED);
  }

  /**
   * The PK half of {@code upsertOnLogin}'s race, single-statement per {@link
   * io.quarkus.narayana.jta.QuarkusTransaction} row-lock idiom already used by {@code
   * DurableLimiter}'s counter upsert.
   *
   * <p>Two concurrent first logins for the same Supabase identity used to both read "no row",
   * both build a {@link User}, and the loser's {@code persist()} throw a bare constraint
   * violation. {@code INSERT ... ON CONFLICT (id) DO NOTHING} is atomic under the row lock
   * Postgres already takes for the insert, so at most one caller ever creates the row and every
   * other caller simply finds it afterwards.
   */
  private static final String INSERT_IF_ABSENT =
      """
      INSERT INTO users (id, email, email_verified, language, is_private, role, created_at,
                          accepted_terms, is_premium)
      VALUES (?1, ?2, false, ?3, false, ?4, ?5, false, false)
      ON CONFLICT (id) DO NOTHING
      RETURNING id
      """;

  @Transactional
  public Upsert upsertOnLogin(UserPayload payload, String preferredLanguage) {
    UUID id = UUID.fromString(payload.id());
    // Blank is not a value to write. The column is NOT NULL, and GoTrue's bare-user shape can
    // arrive without an address; a blank email surfaces as the NOT NULL violation it always has,
    // rather than being silently swallowed.
    String email = blankToNull(payload.email());

    /*
     * Existence checked first, and the insert attempted only when it looks absent. Not merely an
     * optimisation: Postgres validates a row's NOT NULL columns before it ever gets to the ON
     * CONFLICT check, so an unconditional INSERT with a null email would throw on *every*
     * subsequent login of an existing user that happens to arrive without one (GoTrue's bare-user
     * shape) - a real regression the first version of this fix shipped with, caught by
     * upsertOnLogin_aPayloadWithNoEmailDoesNotEraseTheStoredOne. This still closes the actual
     * race the fix targets: two concurrent *first* logins for the same id both see "absent" here
     * and both reach the atomic INSERT below, which resolves the true race with ON CONFLICT DO
     * NOTHING exactly as before - the pre-check only ever skips the insert for a call that finds
     * the row genuinely already there.
     */
    User user = User.findById(id);
    boolean created = false;
    if (user == null) {
      created = insertIfAbsent(id, email, preferredLanguage);
      user = User.findById(id);
    }

    // Both email and confirmation state are Supabase's to state, so both are reconciled on every
    // call rather than written once at creation - a profile that drifts from the identity
    // provider is a profile nobody can trust. The address is the one that used to be written only
    // on creation, which meant a user who changed it in Supabase kept the old one here forever:
    // every email jZen sent went to an address the user had abandoned, and the admin panel showed
    // one that was simply wrong.
    if (email != null && !email.equals(user.email)) {
      claimEmail(user, email);
    }
    user.emailVerified = payload.emailVerified();
    user.lastLoginAt = OffsetDateTime.now();
    user.deletionWarningSentAt = null;
    user.finalWarningSentAt = null;
    return new Upsert(user, created);
  }

  /** @return whether this call created the row, as opposed to finding one a racing call made */
  private boolean insertIfAbsent(UUID id, String email, String preferredLanguage) {
    try {
      List<?> inserted =
          Panache.getEntityManager()
              .createNativeQuery(INSERT_IF_ABSENT)
              .setParameter(1, id)
              .setParameter(2, email)
              .setParameter(3, ZenLocales.resolve(preferredLanguage, supported()))
              .setParameter(4, UserRole.USER.toString())
              .setParameter(5, OffsetDateTime.now())
              .getResultList();
      return !inserted.isEmpty();
    } catch (RuntimeException e) {
      // Hibernate does not consistently wrap a constraint violation from a native query in
      // jakarta.persistence.PersistenceException the way the JPA spec describes for
      // Query#getResultList() - org.hibernate.exception.ConstraintViolationException (a
      // JDBCException, not a PersistenceException) reaches here directly. Caught broadly and
      // reclassified by inspecting the cause chain instead of the exception's declared type.
      throw isEmailUniqueViolation(e) ? emailConflict() : e;
    }
  }

  /**
   * The email-collision half of the race: a login carries an address another profile already
   * owns. Explicitly refused rather than left to the unique index to surface as an opaque 500 -
   * there is no safe default for which of two profiles keeps a shared mailbox, so this asks
   * neither row to give it up. The pre-check makes the ordinary case a clean {@link
   * AuthException} instead of a stack trace; the {@code flush()} still catches the residual race
   * between the check and the write.
   */
  private void claimEmail(User user, String email) {
    if (User.count("email = ?1 and id <> ?2", email, user.id) > 0) {
      throw emailConflict();
    }
    user.email = email;
    try {
      Panache.getEntityManager().flush();
    } catch (RuntimeException e) {
      throw isEmailUniqueViolation(e) ? emailConflict() : e;
    }
  }

  private static boolean isEmailUniqueViolation(RuntimeException e) {
    for (Throwable t = e; t != null; t = t.getCause()) {
      if (t.getMessage() != null && t.getMessage().contains("users_email_key")) {
        return true;
      }
    }
    return false;
  }

  private static AuthException emailConflict() {
    return AuthException.conflict(
        "email_taken", "Another profile already claims this email address.");
  }

  private static String blankToNull(String value) {
    return value == null || value.isBlank() ? null : value;
  }

  @Transactional
  public User findById(UUID id) {
    return User.findById(id);
  }
}
