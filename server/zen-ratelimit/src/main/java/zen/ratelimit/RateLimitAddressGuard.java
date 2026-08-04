package zen.ratelimit;

import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import org.eclipse.microprofile.config.Config;
import org.eclipse.microprofile.config.ConfigProvider;

/**
 * Refuses to boot when the limiter's idea of "who is calling" and the HTTP layer's disagree.
 *
 * <p>Two settings describe the same fact — whether there is a proxy in front of this process — and
 * nothing makes them agree:
 *
 * <ul>
 *   <li>{@code quarkus.http.proxy.proxy-address-forwarding} / {@code allow-x-forwarded}, which
 *       tell Vert.x to rewrite the request's remote address from {@code X-Forwarded-For};
 *   <li>{@code zen.ratelimit.forwarded-hops}, which tells {@link ClientAddress} how many trailing
 *       entries of that header were written by infrastructure rather than by the caller.
 * </ul>
 *
 * <p>Each inconsistent pairing breaks the limiter completely, and silently:
 *
 * <ul>
 *   <li><strong>Forwarding on, hops 0.</strong> The limiter falls back to the socket peer — but
 *       Vert.x has already replaced that with the <em>leftmost</em> {@code X-Forwarded-For} entry,
 *       which is the one the caller made up. Every attacker gets an unlimited supply of fresh
 *       identities and the limiter blocks nobody.
 *   <li><strong>Forwarding off, hops above 0.</strong> The limiter reads a header that nothing
 *       vouches for, with the same result. "Behind a proxy" was asserted by configuration and is
 *       not true.
 * </ul>
 *
 * <p>Neither shows up as an error at runtime. The 429s simply never happen, every suite stays
 * green, and the only evidence is traffic that should have been refused and was not — which is
 * indistinguishable from not being attacked. So it fails at startup instead: on Cloud Run a
 * revision that throws during boot never receives traffic and the previous revision keeps serving,
 * so the misconfiguration costs a failed deploy rather than an unprotected service. Same
 * reasoning, and same shape, as {@code CorsCredentialsGuard} in zen-transport.
 */
@ApplicationScoped
public class RateLimitAddressGuard {

  static final String PROXY_FORWARDING_PROPERTY = "quarkus.http.proxy.proxy-address-forwarding";
  static final String ALLOW_X_FORWARDED_PROPERTY = "quarkus.http.proxy.allow-x-forwarded";
  static final String HOPS_PROPERTY = "zen.ratelimit.forwarded-hops";

  @Inject RateLimitConfig config;

  void check(@Observes StartupEvent event) {
    if (!config.enabled()) {
      return;
    }
    Config runtime = ConfigProvider.getConfig();
    boolean forwarding =
        runtime.getOptionalValue(PROXY_FORWARDING_PROPERTY, Boolean.class).orElse(false)
            || runtime.getOptionalValue(ALLOW_X_FORWARDED_PROPERTY, Boolean.class).orElse(false);
    verify(forwarding, config.forwardedHops());
  }

  /**
   * The rule itself, separated from the container so both dangerous pairings can be expressed
   * directly in a unit test. An assembled application only ever has a consistent one.
   *
   * @throws IllegalStateException when the two settings contradict each other
   */
  static void verify(boolean proxyForwardingEnabled, int forwardedHops) {
    if (proxyForwardingEnabled && forwardedHops <= 0) {
      throw new IllegalStateException(
          "Refusing to start: "
              + PROXY_FORWARDING_PROPERTY
              + " is on but "
              + HOPS_PROPERTY
              + " is "
              + forwardedHops
              + ". Vert.x has already overwritten the socket peer with the leftmost"
              + " X-Forwarded-For entry, which the caller controls, so the rate limiter would"
              + " count a value every attacker can change at will and would throttle nobody. Set "
              + HOPS_PROPERTY
              + " to the number of proxies actually in front of this process (1 for Cloud Run"
              + " served directly), or turn proxy address forwarding off.");
    }
    if (!proxyForwardingEnabled && forwardedHops > 0) {
      throw new IllegalStateException(
          "Refusing to start: "
              + HOPS_PROPERTY
              + " is "
              + forwardedHops
              + " but "
              + PROXY_FORWARDING_PROPERTY
              + " is off. The rate limiter would trust X-Forwarded-For on a deployment that has"
              + " declared it is not behind a proxy, so any caller could pick their own identity"
              + " by sending the header. Set "
              + HOPS_PROPERTY
              + "=0, or turn proxy address forwarding on if there really is a proxy in front.");
    }
  }
}
