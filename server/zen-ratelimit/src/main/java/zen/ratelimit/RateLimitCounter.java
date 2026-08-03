package zen.ratelimit;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.Objects;

/**
 * One caller's request count in one bucket, in one closed window. Active-record Panache, like
 * every other jZen entity (BLUEPRINT "Persistence").
 *
 * <p>The entity exists so the cleanup job and any operator query have a typed handle on the table.
 * The <em>hot path</em> deliberately does not go through it: {@link DurableLimiter} increments with
 * a single {@code INSERT … ON CONFLICT … DO UPDATE … RETURNING}, because a read-then-write through
 * the persistence context is a lost-update race, and losing updates in a rate limiter means the
 * limit is whatever concurrency happens to be.
 *
 * <p><strong>{@code subject} is a hash, never an address.</strong> An IP address is personal data
 * under GDPR Recital 30, and this table would otherwise be a durable log of who called what and
 * when — retained for reasons that have nothing to do with why the address was collected. The
 * limiter only ever needs equality, and a hash gives it that, so storing the address itself would
 * be collecting more than the purpose requires. See {@link DurableLimiter#hash}.
 */
@Entity
@Table(name = "zen_rate_limit_counters")
@IdClass(RateLimitCounter.Key.class)
public class RateLimitCounter extends PanacheEntityBase {

  /** The {@link RateLimitRule#key()} this row counts. */
  @Id
  @Column(name = "bucket")
  public String bucket;

  /** Salted hash of the client address — see the class note on why it is not the address. */
  @Id
  @Column(name = "subject")
  public String subject;

  /** Start of the fixed window, truncated to the bucket's configured window length. */
  @Id
  @Column(name = "window_start")
  public OffsetDateTime windowStart;

  /** Requests charged in this window, including ones that went on to fail authentication. */
  @Column(name = "request_count", nullable = false)
  public long requestCount;

  /** Removes every row whose window closed before {@code before}. Returns how many went. */
  public static long deleteClosedBefore(OffsetDateTime before) {
    return delete("windowStart < ?1", before);
  }

  /** Composite primary key: one row per (bucket, subject, window). */
  public static final class Key implements Serializable {

    public String bucket;
    public String subject;
    public OffsetDateTime windowStart;

    public Key() {}

    @Override
    public boolean equals(Object other) {
      return other instanceof Key key
          && Objects.equals(bucket, key.bucket)
          && Objects.equals(subject, key.subject)
          && Objects.equals(windowStart, key.windowStart);
    }

    @Override
    public int hashCode() {
      return Objects.hash(bucket, subject, windowStart);
    }
  }
}
