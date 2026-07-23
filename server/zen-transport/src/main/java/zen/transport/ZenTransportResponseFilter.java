package zen.transport;

import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;

/**
 * Response half of the seam: echoes the negotiated {@code X-Zen-Transport} value back on the
 * outgoing response, so a caller can confirm which format it actually got.
 */
@Provider
public class ZenTransportResponseFilter implements ContainerResponseFilter {

  @Override
  public void filter(ContainerRequestContext request, ContainerResponseContext response) {
    Object format = request.getProperty(ZenTransportFilter.FORMAT_PROPERTY);
    if (format instanceof ZenTransportFormat f) {
      response.getHeaders().putSingle(ZenTransportFormat.HEADER, f.wire());
    }
  }
}
