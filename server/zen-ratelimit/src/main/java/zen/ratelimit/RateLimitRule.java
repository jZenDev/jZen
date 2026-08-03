package zen.ratelimit;

import java.util.Set;

/**
 * The buckets a request can fall into, most specific first.
 *
 * <p>Deliberately a closed set matched in code rather than an operator-editable path list. The
 * paths named here are <em>framework</em> routes — they ship in {@code zen-identity} and
 * {@code zen-jobs} and are the same in every jZen application — so expressing them as
 * configuration would invite an application to lose the protection by not knowing it had to
 * declare it. What an application <em>can</em> tune is how tight each bucket is
 * ({@link RateLimitConfig}); what it cannot do is quietly leave the credential endpoints
 * uncovered.
 *
 * <p>A request matches exactly one rule: {@link #resolve} returns the first that claims it, and
 * a request outside {@code /api/} matches none and is not counted at all (static assets, the
 * health probe, {@code /openapi}).
 */
public enum RateLimitRule {

  /**
   * {@code POST /api/v1/jobs/trigger}. <strong>First, and with the tightest durable limit in the
   * system.</strong> A successful call runs retention: e-mail dispatch and account
   * <em>anonymisation</em>. It is the highest-consequence endpoint jZen ships, its only credential
   * is a shared secret in a header, and until this module existed guessing that secret was
   * unbounded. {@code JobTriggerAuthenticator} already compares in constant time and fails closed
   * when unconfigured; this is the other half — constant-time comparison stops a timing oracle, it
   * does not stop a million attempts.
   *
   * <p>Its legitimate caller is one Cloud Scheduler entry once an hour, so the honest limit is
   * small enough to be arithmetic rather than a compromise.
   */
  JOB_TRIGGER,

  /**
   * The credential-bearing auth endpoints: password login, registration, recovery, password set,
   * link-token exchange and refresh. These are the credential-guessing and account-enumeration
   * surfaces, and the ones an attacker returns to.
   *
   * <p>{@code GET /api/v1/auth/identity} and {@code POST /api/v1/auth/logout} are deliberately
   * <em>not</em> here. Neither accepts a guess: identity reads the session the caller already
   * holds and logout destroys it. A client calls identity on every launch and on every route
   * change, so bucketing it with login would be counting ordinary use against an abuse budget —
   * it falls to {@link #GLOBAL} like any other read.
   */
  AUTH,

  /**
   * Everything else under {@code /api/}. This is the denial-of-service bucket rather than the
   * credential one: at {@code --concurrency=200} and a 60s timeout, saturating the whole service
   * costs about 3.3 requests per second from one source (ADR-027), so a per-address ceiling
   * meaningfully below that is what puts a single-source flood back in reach. It is generous
   * enough that no human, and no client polling on a sane interval, will ever meet it.
   */
  GLOBAL;

  private static final String JOB_TRIGGER_PATH = "api/v1/jobs/trigger";

  private static final Set<String> AUTH_PATHS =
      Set.of(
          "api/v1/auth/login",
          "api/v1/auth/register",
          "api/v1/auth/restore-password",
          "api/v1/auth/password",
          "api/v1/auth/session",
          "api/v1/auth/refresh");

  private static final String API_PREFIX = "api/";

  /**
   * The rule claiming this request path, or {@code null} when none does.
   *
   * @param path a request path with or without a leading slash; {@code UriInfo.getPath()} differs
   *     between runtimes on that point, which is why it is normalised here rather than assumed
   */
  public static RateLimitRule resolve(String path) {
    String normalized = normalize(path);
    if (JOB_TRIGGER_PATH.equals(normalized)) {
      return JOB_TRIGGER;
    }
    if (AUTH_PATHS.contains(normalized)) {
      return AUTH;
    }
    if (normalized.startsWith(API_PREFIX)) {
      return GLOBAL;
    }
    return null;
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

  /** The limits configured for this rule. */
  public RateLimitConfig.Limits limitsIn(RateLimitConfig config) {
    return switch (this) {
      case JOB_TRIGGER -> config.jobTrigger();
      case AUTH -> config.auth();
      case GLOBAL -> config.global();
    };
  }

  /** Lower-case name used in the counter's bucket key and in log lines. */
  public String key() {
    return name().toLowerCase(java.util.Locale.ROOT);
  }
}
