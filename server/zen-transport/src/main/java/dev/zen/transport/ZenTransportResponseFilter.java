package dev.zen.transport;

import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerResponseContext;
import jakarta.ws.rs.container.ContainerResponseFilter;
import jakarta.ws.rs.ext.Provider;

/**
 * Response half of the seam: echoes the negotiated {@code X-Zen-Transport} value back to
 * the client, matching DartZen's server behavior (its transport middleware sets the
 * header on the outgoing response). Lets a client confirm which format it received.
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
