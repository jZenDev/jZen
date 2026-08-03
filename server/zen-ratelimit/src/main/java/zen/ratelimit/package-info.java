/**
 * The abuse layer: per-address rate limiting for jZen's HTTP surface (DECISIONS ADR-029).
 *
 * <p>Two tiers, and the split is measured rather than defensive. {@link zen.ratelimit.BurstLimiter}
 * holds minute-scale windows in memory, which is valid because at most one instance ever runs.
 * {@link zen.ratelimit.DurableLimiter} holds hour-scale windows in Postgres, which is <em>required</em>
 * because under {@code --min-instances=0} the process is replaced about every hour (ADR-027) and an
 * hour-scale counter in memory would reset itself as fast as it filled.
 *
 * <p>Three things in here fail silently if disturbed, and each carries its own guard:
 *
 * <ol>
 *   <li><strong>Bean discovery.</strong> Remove {@code jandex-maven-plugin} from this module's pom
 *       and every class here becomes inert with no error anywhere —
 *       {@code RateLimitWiringTest} in the app module is what notices.
 *   <li><strong>Client-IP resolution.</strong> Read {@code X-Forwarded-For} the conventional way
 *       and the limiter throttles nobody — {@link zen.ratelimit.ClientAddress} explains why, and
 *       {@link zen.ratelimit.RateLimitAddressGuard} refuses to boot on the inconsistent
 *       configurations.
 *   <li><strong>Counter growth.</strong> The durable table is bounded by a
 *       {@link zen.ratelimit.RateLimitCleanupJob}, not by a cron that cannot fire here.
 * </ol>
 */
package zen.ratelimit;
