package zen.ratelimit;

import java.time.Duration;

/**
 * Every knob the abuse layer has. Defaults ship in this module's
 * {@code META-INF/microprofile-config.properties} at the standard MicroProfile ordinal (100), so
 * an application's own {@code application.properties} (ordinal 250) overrides any one of them
 * without redeclaring the rest.
 *
 * <p>An interface with a {@link RateLimitProperties} implementation behind it, rather than a
 * {@code @ConfigMapping}: the tests can then hand the limiters a hand-written instance carrying
 * deliberately dangerous values, without a container and without touching global configuration.
 * That is the same reason {@link ClientAddress} is static — the interesting inputs here are the
 * ones an assembled application never produces.
 *
 * <p><strong>The limits are deliberately profile-dependent, and that is the honest answer rather
 * than a convenience.</strong> A test suite drives hundreds of requests from {@code 127.0.0.1} in
 * a few seconds — {@code AuthResourceTest} alone makes about a dozen login and register calls —
 * so any per-address limit tight enough to be worth having in production would turn the whole
 * backend suite into a test of this module. The dishonest ways out are all available and all
 * refused: deleting assertions, inserting sleeps, or exempting a path in production so a test
 * passes. Configuring the limits per profile is the one resolution that leaves the production
 * behaviour and every existing assertion intact. Enforcement is not taken on trust either —
 * {@code RateLimitEnforcementTest} sets its own deliberately tiny limits and proves a 429.
 */
public interface RateLimitConfig {

  /**
   * Master switch. On by default: a framework whose protection has to be remembered is not
   * protection. Turning it off is a local-debugging affordance, not a deployment option.
   */
  boolean enabled();

  /**
   * How many trailing {@code X-Forwarded-For} entries were written by proxies the operator
   * controls. {@code 0} — the default — means the header is untrusted and ignored entirely. See
   * {@link ClientAddress} for why counting from the right is the only safe reading, and
   * {@link RateLimitAddressGuard} for the two configurations that refuse to boot.
   */
  int forwardedHops();

  /**
   * How long a durable counter row is kept after its window closes, before the cleanup
   * {@link RateLimitCleanupJob} removes it. Long enough to be readable while investigating an
   * incident; short enough that the table cannot grow without bound.
   */
  Duration counterRetention();

  /**
   * Ceiling on how many distinct callers the in-memory burst tier tracks at once. Reaching it is
   * itself a symptom — a flood from many addresses — and the behaviour there is documented on
   * {@link BurstLimiter#note}, because "runs out of memory on a 256Mi instance" is a worse failure
   * than any limiter decision.
   */
  int maxTrackedSubjects();

  /** Limits for {@link RateLimitRule#GLOBAL} — {@code zen.ratelimit.global.*}. */
  Limits global();

  /** Limits for {@link RateLimitRule#AUTH} — {@code zen.ratelimit.auth.*}. */
  Limits auth();

  /** Limits for {@link RateLimitRule#JOB_TRIGGER} — {@code zen.ratelimit.job-trigger.*}. */
  Limits jobTrigger();

  /**
   * One bucket's two tiers.
   *
   * <p>The split is not belt-and-braces. The burst tier catches the fast flood and costs nothing
   * per request; the durable tier catches the patient one, and has to be durable because under
   * {@code --min-instances=0} the process is replaced roughly every hour (ADR-027), so an
   * hour-scale counter kept in memory would reset itself faster than an attacker could fill it.
   */
  interface Limits {

    /** Requests permitted per {@link #burstWindow()} from one address. */
    int burstLimit();

    /** The in-memory window. Second- to minute-scale; longer belongs in the durable tier. */
    Duration burstWindow();

    /**
     * Requests permitted per {@link #durableWindow()} from one address, or {@code 0} to leave the
     * durable tier off for this bucket. Off is right for {@link RateLimitRule#GLOBAL}: a database
     * write on every read request would make the limiter the most expensive thing in the request.
     */
    int durableLimit();

    /** The persisted window. Hour-scale; this is the tier that survives a process replacement. */
    Duration durableWindow();

    /** Whether this bucket persists counters at all. */
    default boolean hasDurableTier() {
      return durableLimit() > 0;
    }
  }
}
