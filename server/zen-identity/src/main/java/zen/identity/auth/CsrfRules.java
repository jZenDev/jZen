package zen.identity.auth;

import java.util.Set;

/**
 * Which requests the double-submit CSRF check applies to.
 *
 * <p>Separated from {@link CsrfFilter} so the decision can be tested as what it is — a pure
 * function from method and path to yes-or-no. An assembled application only ever presents the
 * configuration that works; the interesting cases are the ones that must <em>not</em> be enforced,
 * and every one of them is a route that would break in production if this got it wrong.
 *
 * <p><strong>What this is worth, stated honestly.</strong> All four session cookies are
 * {@code SameSite=Lax}, which already means a cross-site {@code POST} carries no session at all —
 * the classic attack is largely closed before this filter runs. This is defence in depth: it
 * covers a same-site subdomain that turns hostile, browsers that do not implement {@code SameSite},
 * and the day someone needs {@code SameSite=None} for an embedding. It is not an open hole being
 * closed, and it should not be described as one.
 */
public final class CsrfRules {

  private CsrfRules() {}

  /**
   * Routes that must never be asked for the token, each for a reason that would show up as a
   * production outage rather than as a failing test.
   *
   * <ul>
   *   <li>{@code auth/login}, {@code auth/register}, {@code auth/restore-password},
   *       {@code auth/session} — <b>they run before the cookie exists.</b> These are how a caller
   *       <em>gets</em> a session, so requiring a token issued with one is circular. The subtle
   *       half is a returning visitor: they may still be holding a stale token from a previous
   *       session, and enforcing here would make signing in fail for exactly the people who have
   *       been here before.
   *   <li>{@code auth/refresh} — <b>its credential is the refresh cookie, not the access
   *       cookie.</b> The CSRF cookie's lifetime is the access token's (they are issued together
   *       by the same response and expire together), and refresh is precisely the endpoint a
   *       client calls <em>after</em> that hour is up. Enforcing here would end every session at
   *       the access-token TTL instead of at seven days, on every client, silently. The
   *       alternative — giving the CSRF cookie the refresh token's seven-day lifetime — was
   *       rejected: it would leave a window in which the access cookie is gone but the CSRF cookie
   *       is not, and the check below keys on the access cookie, so the two lifetimes are load
   *       bearing together. Nothing is lost that {@code SameSite=Lax} was not already covering: a
   *       forged refresh rotates a token and grants the forger nothing, since the new cookies land
   *       in the victim's browser.
   *   <li>{@code jobs/trigger} — <b>its caller is a machine.</b> Cloud Scheduler has no cookie jar
   *       and no CSRF token, and never will. It carries its own shared-secret credential compared
   *       in constant time and is {@code @PermitAll} by design (ADR-008). Enforcing here breaks
   *       scheduled retention in production and the end-to-end gate with it.
   * </ul>
   */
  private static final Set<String> EXEMPT_PATHS =
      Set.of(
          "api/v1/auth/login",
          "api/v1/auth/register",
          "api/v1/auth/restore-password",
          "api/v1/auth/session",
          "api/v1/auth/refresh",
          "api/v1/jobs/trigger");

  /**
   * Methods that change something. A positive list of the <em>safe</em> methods rather than of the
   * unsafe ones, so a verb nobody anticipated is protected rather than exempt.
   */
  private static final Set<String> SAFE_METHODS = Set.of("GET", "HEAD", "OPTIONS");

  private static final String API_PREFIX = "api/";

  /**
   * Whether a request with this method and path is subject to the check.
   *
   * <p>Note what is <em>not</em> decided here: whether the caller actually holds a session. That is
   * the filter's job, because it is a property of the request rather than of the route — and it is
   * what keeps an expired session from turning a 401 into a 403.
   */
  public static boolean applies(String method, String path) {
    if (method == null || SAFE_METHODS.contains(method.toUpperCase(java.util.Locale.ROOT))) {
      return false;
    }
    String normalized = normalize(path);
    // Outside /api/ there is nothing to forge: the static handler serves the app bundle and the
    // admin panel, and neither reads a cookie or changes state.
    return normalized.startsWith(API_PREFIX) && !EXEMPT_PATHS.contains(normalized);
  }

  /** Strips a leading slash and any trailing slash, so {@code /api/x/} and {@code api/x} agree. */
  static String normalize(String path) {
    if (path == null) {
      return "";
    }
    String value = path.trim();
    if (value.startsWith("/")) {
      value = value.substring(1);
    }
    while (value.endsWith("/")) {
      value = value.substring(0, value.length() - 1);
    }
    return value;
  }

  /** The exempt routes, for tests and for anything that needs to state the list. */
  public static Set<String> exemptPaths() {
    return EXEMPT_PATHS;
  }
}
