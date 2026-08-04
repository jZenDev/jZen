package zen.ratelimit;

import io.quarkus.hibernate.orm.panache.Panache;
import io.quarkus.narayana.jta.QuarkusTransaction;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

/**
 * The persistent tier: hour-scale windows in Postgres.
 *
 * <p><strong>This tier is a measured requirement, not a precaution.</strong> Under
 * {@code --min-instances=0} the live service's process is replaced roughly every hour (ADR-027,
 * twelve consecutive samples), so a counter whose window outlives an hour cannot be held in memory
 * at all — it would reset itself about as often as an attacker filled it, and would look like
 * protection while providing none. Postgres is already provisioned, already under Flyway, already
 * migrated at start, and costs nothing incrementally.
 *
 * <p>Applied only to the buckets where a patient attacker is the threat — the credential endpoints
 * and the job trigger. {@link RateLimitRule#GLOBAL} has no durable tier, because a database write
 * on every read request would make the limiter the most expensive thing in the request.
 *
 * <p><strong>The increment is one statement, and that is load-bearing.</strong> Reading a count and
 * then writing it back is a lost-update race, and in a rate limiter a lost update means the
 * effective limit is whatever concurrency happened to be. {@code INSERT … ON CONFLICT DO UPDATE …
 * RETURNING} makes the read-modify-write atomic inside the row lock Postgres already takes.
 *
 * <p><strong>A database failure here is not swallowed.</strong> It propagates, the request fails,
 * and the caller sees a 500. That is deliberate: the alternative is a limiter that silently stops
 * limiting exactly when the system is already unhealthy, which is when it is most needed. It also
 * costs nothing in availability terms — this application cannot serve an authenticated request
 * without Postgres anyway, since roles are loaded from the {@code users} table on every one.
 */
@ApplicationScoped
public class DurableLimiter {

  /**
   * Domain separator mixed into the hash. Not a secret and not pretending to be one: it stops a
   * value in this column from being comparable with a bare SHA-256 of an address computed
   * elsewhere, which is what an off-the-shelf rainbow table over the IPv4 space would be.
   */
  private static final String HASH_DOMAIN = "zen-ratelimit:v1:";

  /**
   * The atomic increment. {@code EXCLUDED} is the row that failed to insert, so the update sees
   * the value already stored plus the one being charged.
   */
  private static final String INCREMENT =
      """
      INSERT INTO zen_rate_limit_counters (bucket, subject, window_start, request_count)
      VALUES (?1, ?2, ?3, 1)
      ON CONFLICT (bucket, subject, window_start)
      DO UPDATE SET request_count = zen_rate_limit_counters.request_count + 1
      RETURNING request_count
      """;

  private final RateLimitConfig config;
  private final Clock clock;

  /**
   * The {@link Clock} is the one {@code zen-jobs} produces. zen-ratelimit is its second consumer,
   * which is the trigger ADR-008 named for promoting the producer — deliberately not taken here,
   * because {@code zen-core} is a zero-dependency pure-Java library and hosting a CDI producer
   * would make it a bean archive. Declaring a second producer instead would be an ambiguous
   * dependency and would fail the build, which is the right outcome.
   */
  @Inject
  public DurableLimiter(RateLimitConfig config, Clock clock) {
    this.config = config;
    this.clock = clock;
  }

  /**
   * Charges one request against {@code subject} in {@code rule}'s durable bucket.
   *
   * @return {@link RateLimitDecision#permit()} immediately when the bucket has no durable tier
   */
  public RateLimitDecision check(RateLimitRule rule, String subject) {
    RateLimitConfig.Limits limits = rule.limitsIn(config);
    if (!limits.hasDurableTier()) {
      return RateLimitDecision.permit();
    }
    long windowMs = limits.durableWindow().toMillis();
    if (windowMs <= 0) {
      return RateLimitDecision.permit();
    }

    long now = clock.millis();
    long windowStartMs = now - Math.floorMod(now, windowMs);
    OffsetDateTime windowStart =
        OffsetDateTime.ofInstant(Instant.ofEpochMilli(windowStartMs), ZoneOffset.UTC);

    long count = increment(rule.key(), hash(subject), windowStart);
    if (count <= limits.durableLimit()) {
      return RateLimitDecision.permit();
    }
    long retryAfter = Duration.ofMillis(windowStartMs + windowMs - now).toSeconds();
    return RateLimitDecision.refuse(retryAfter, RateLimitDecision.DURABLE);
  }

  /**
   * Runs the upsert in its own short transaction, so counting a request never enlists in — or
   * rolls back with — whatever transaction the resource goes on to open.
   */
  private long increment(String bucket, String subject, OffsetDateTime windowStart) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                ((Number)
                        Panache.getEntityManager()
                            .createNativeQuery(INCREMENT)
                            .setParameter(1, bucket)
                            .setParameter(2, subject)
                            .setParameter(3, windowStart)
                            .getSingleResult())
                    .longValue());
  }

  /**
   * Hashes a client address for storage.
   *
   * <p>An IP address is personal data (GDPR Recital 30). The limiter needs to tell callers apart,
   * which equality over a hash gives it exactly as well as the address itself would — so storing
   * the address would be keeping more than the purpose requires, in a table that outlives the
   * request by two days. Hex-encoded SHA-256 truncated to 32 characters: 128 bits, far past any
   * collision that matters for counting requests, and half the column width.
   */
  static String hash(String address) {
    try {
      byte[] digest =
          MessageDigest.getInstance("SHA-256")
              .digest((HASH_DOMAIN + address).getBytes(StandardCharsets.UTF_8));
      StringBuilder hex = new StringBuilder(32);
      for (int i = 0; i < 16; i++) {
        hex.append(Character.forDigit((digest[i] >> 4) & 0xF, 16));
        hex.append(Character.forDigit(digest[i] & 0xF, 16));
      }
      return hex.toString();
    } catch (NoSuchAlgorithmException e) {
      // SHA-256 is mandated by the JDK spec; if it is missing the platform is not a JDK.
      throw new IllegalStateException("SHA-256 is unavailable on this JVM", e);
    }
  }
}
