package zen.transport;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.ext.Provider;

/**
 * Response half of the seam: echoes the negotiated {@code X-Zen-Transport} value back on the
 * outgoing response, so a caller can confirm which format it actually got — and, on every
 * {@code /api/} response this filter sees, the two cache-correctness headers a shared/CDN cache
 * would otherwise get wrong for a negotiated, per-caller API.
 *
 * <p><strong>{@code Vary}.</strong> A cache that does not know a response varies by these
 * headers can serve one caller's response to another: {@code X-Zen-Transport} picks the wire
 * format (a protobuf response served to a JSON caller does not merely look wrong, it fails to
 * parse), {@code Accept-Language} picks the localized body, {@code Origin} is read by Quarkus's
 * own CORS filter to decide which {@code Access-Control-Allow-*} headers this response carries
 * (see {@code CorsCredentialsGuard} for the startup-time guard on that configuration), and
 * {@code Cookie} is the session — the same path answers differently, or not at all, for an
 * authenticated caller versus an anonymous one.
 *
 * <p><strong>{@code Cache-Control: no-store} on an authenticated response.</strong> Without it, a
 * response containing one caller's data is a candidate for any cache sitting between this server
 * and the browser to keep and hand to the next request that looks similar enough — exactly the
 * class of bug {@code Vary} narrows but a cache that ignores {@code Vary} (a misconfigured proxy,
 * an old client) does not respect at all. "Authenticated" is read from the injected {@link
 * SecurityIdentity} — the standard JAX-RS {@code SecurityContext} was tried first and dropped:
 * under Quarkus REST it does not reliably reflect {@code @TestSecurity}'s identity by the time a
 * {@code ContainerResponseFilter} runs, where {@code SecurityIdentity} (the same CDI type {@code
 * CsrfFilter} already keys on) does.
 */
@Provider
public class ZenTransportResponseFilter implements ContainerResponseFilter {

  /**
   * Every request attribute that changes which bytes this filter's own response carries for an
   * otherwise-identical request. See the class javadoc for what each one governs.
   */
  static final String VARY_VALUE = "X-Zen-Transport, Accept-Language, Origin, Cookie";

  static final String NO_STORE = "no-store";

  @Inject SecurityIdentity identity;

  @Override
  public void filter(ContainerRequestContext request, ContainerResponseContext response) {
    Object format = request.getProperty(ZenTransportFilter.FORMAT_PROPERTY);
    if (format instanceof ZenTransportFormat f) {
      response.getHeaders().putSingle(ZenTransportFormat.HEADER, f.wire());
    }
    response.getHeaders().putSingle(HttpHeaders.VARY, VARY_VALUE);
    if (identity != null && !identity.isAnonymous()) {
      response.getHeaders().putSingle(HttpHeaders.CACHE_CONTROL, NO_STORE);
    }
  }
}
