package zen.ratelimit;

import io.quarkus.vertx.http.runtime.CurrentVertxRequest;
import io.vertx.ext.web.RoutingContext;
import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import org.jboss.logging.Logger;
import zen.proto.v1.ZenError;

/**
 * Charges every {@code /api/} request against its bucket and refuses the ones over the limit.
 *
 * <p><strong>Not {@code @PreMatching}, deliberately.</strong> {@code ZenTransportFilter} is
 * pre-matching because it has to rewrite {@code Accept} before JAX-RS picks a writer; this filter
 * must run <em>after</em> that, so an aborted 429 body is serialised in whichever format the
 * caller negotiated. Ordinary (post-matching) filters run after every pre-matching one, so the
 * ordering is structural rather than a priority number someone has to remember.
 *
 * <p><strong>The 429 is charged before authentication, not after.</strong> A limiter that only
 * counted authenticated requests would count only the traffic that was never the problem: on the
 * credential buckets and on the job trigger, the failures <em>are</em> the attack.
 *
 * <p>Discovered as a {@code @Provider} from this module's jar only because zen-ratelimit runs
 * {@code jandex-maven-plugin}. Without {@code META-INF/jandex.idx} this class is on the classpath,
 * compiles, and is never instantiated: no error, no warning, a green suite, and a limiter that
 * permits everything. {@code RateLimitWiringTest} in the app module fails the build if that
 * happens.
 */
@Provider
public class RateLimitFilter implements ContainerRequestFilter {

  private static final Logger LOG = Logger.getLogger(RateLimitFilter.class);

  /** {@code ZenError} code returned to a caller that has been throttled. */
  static final String ERROR_RATE_LIMITED = "rate_limited";

  private static final String MESSAGE = "Too many requests. Slow down and try again shortly.";

  /** Standard, and the reason a throttled client does not simply retry in a tight loop. */
  private static final String RETRY_AFTER = "Retry-After";

  /**
   * Which tier refused, for an operator reading a 429 in the wild. Burst means "you are fast",
   * durable means "you have been at this for a while" — quite different situations.
   */
  private static final String TIER_HEADER = "X-RateLimit-Tier";

  @Inject RateLimitConfig config;
  @Inject BurstLimiter burst;
  @Inject DurableLimiter durable;
  @Inject CurrentVertxRequest currentRequest;

  @Override
  public void filter(ContainerRequestContext ctx) {
    if (!config.enabled()) {
      return;
    }
    RateLimitRule rule = RateLimitRule.resolve(ctx.getUriInfo().getPath());
    if (rule == null) {
      return;
    }

    String subject =
        ClientAddress.resolve(
            ctx.getHeaderString(ClientAddress.FORWARDED_FOR), socketPeer(), config.forwardedHops());

    /* Burst first: it is free, and a caller already over the fast limit should not also be
     * charged a database write. The durable tier is what an attacker eventually runs into. */
    RateLimitDecision decision = burst.check(rule, subject);
    if (decision.permitted()) {
      decision = durable.check(rule, subject);
    }
    if (decision.permitted()) {
      return;
    }

    /* The address is not logged. Wave 0 took e-mail addresses out of the logs for the same
     * reason: an IP address is personal data, Cloud Logging retains it, and the bucket plus the
     * tier is what an operator actually needs to act on. */
    LOG.infof(
        "Rate limit refused a request to %s: bucket=%s tier=%s retry-after=%ds",
        ctx.getUriInfo().getPath(), rule.key(), decision.tier(), decision.retryAfterSeconds());

    ctx.abortWith(
        Response.status(429)
            .header(RETRY_AFTER, decision.retryAfterSeconds())
            .header(TIER_HEADER, decision.tier())
            .entity(ZenError.newBuilder().setCode(ERROR_RATE_LIMITED).setMessage(MESSAGE).build())
            .build());
  }

  /**
   * The transport-level peer address.
   *
   * <p>Read from the Vert.x request rather than from anything JAX-RS offers, because JAX-RS has no
   * notion of a socket peer at all. Null-tolerant: an in-VM invocation has no socket, and
   * {@link ClientAddress} maps that to a single shared bucket rather than to an exemption.
   */
  private String socketPeer() {
    RoutingContext routing = currentRequest.getCurrent();
    if (routing == null || routing.request().remoteAddress() == null) {
      return null;
    }
    return routing.request().remoteAddress().hostAddress();
  }
}
