package zen.transport;

import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.container.PreMatching;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.ext.Provider;

/**
 * Request half of the dual-mode transport seam.
 *
 * <p>Runs {@code @PreMatching} so the rewritten {@code Accept} header is in place before
 * JAX-RS selects a resource method and a {@link jakarta.ws.rs.ext.MessageBodyWriter}.
 * The developer writes an ordinary resource returning a proto message; this filter and
 * the paired writers pick the wire format. That is the whole point of the seam — the
 * endpoint author never mentions JSON or Protobuf.
 *
 * <p>Scoped to {@code api/} paths so it never rewrites {@code Accept} on framework
 * endpoints ({@code /openapi}, {@code /q/health}, static assets). BugEater's
 * {@code ContentTypeFilter} is likewise scoped to {@code api/v1/*}.
 */
@Provider
@PreMatching
public class ZenTransportFilter implements ContainerRequestFilter {

  /** Request property carrying the negotiated format to the response filter. */
  static final String FORMAT_PROPERTY = "zen.transport.format";

  @Override
  public void filter(ContainerRequestContext ctx) {
    // UriInfo.getPath() may or may not carry a leading slash depending on the runtime;
    // normalize before gating.
    String path = ctx.getUriInfo().getPath();
    if (path.startsWith("/")) {
      path = path.substring(1);
    }
    if (!path.startsWith("api/")) {
      return;
    }

    ZenTransportFormat format =
        ZenTransportFormat.negotiate(ctx.getHeaderString(ZenTransportFormat.HEADER), ctx.getMediaType());

    // Force content negotiation to the negotiated format's writer.
    ctx.getHeaders().putSingle(HttpHeaders.ACCEPT, format.mediaType());
    ctx.setProperty(FORMAT_PROPERTY, format);
  }
}
