package zen.ratelimit;

/**
 * What a tier decided about one request.
 *
 * @param permitted whether the request may proceed
 * @param retryAfterSeconds whole seconds until the window that refused it closes; {@code 0} when
 *     permitted. Sent to the caller as {@code Retry-After}, because a 429 that does not say when
 *     to come back trains clients to retry immediately, which is the behaviour the limiter exists
 *     to stop
 * @param tier which tier decided, for the log line and for {@code X-RateLimit-Tier}; the two tiers
 *     mean quite different things and an operator reading a 429 needs to know which fired
 */
public record RateLimitDecision(boolean permitted, long retryAfterSeconds, String tier) {

  /** The burst tier's name, as it appears on the wire and in logs. */
  public static final String BURST = "burst";

  /** The durable tier's name, as it appears on the wire and in logs. */
  public static final String DURABLE = "durable";

  private static final RateLimitDecision PERMITTED = new RateLimitDecision(true, 0, "");

  /** The request may proceed. */
  public static RateLimitDecision permit() {
    return PERMITTED;
  }

  /** The request is refused until {@code retryAfterSeconds} have passed. */
  public static RateLimitDecision refuse(long retryAfterSeconds, String tier) {
    // Retry-After: 0 reads as "immediately", which would be a lie and an invitation to hammer.
    return new RateLimitDecision(false, Math.max(1, retryAfterSeconds), tier);
  }
}
