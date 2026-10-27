package zen.identity.auth;

import jakarta.annotation.security.PermitAll;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
import java.net.URI;
import zen.identity.AuthException;

/**
 * Safe landing page used by the confirmation and recovery email templates.
 *
 * <p>The email scanner and link preview fetch this GET. It only validates the requested return
 * target and renders a Continue link; the one-time hash is not sent to GoTrue here. Following
 * Continue opens the app with the hash in its query, and the app submits it to
 * {@code POST /api/v1/auth/confirm} after an explicit user action.
 */
@Path("/auth/confirm")
public class AuthConfirmResource {

  private static final String REFERRER_POLICY = "Referrer-Policy";
  private static final String CACHE_CONTROL = "Cache-Control";
  private static final String NO_STORE = "no-store";
  private static final String NO_REFERRER = "no-referrer";
  private static final int MAX_TOKEN_HASH_LENGTH = 512;

  private final RedirectTargets redirectTargets;

  @Inject
  public AuthConfirmResource(RedirectTargets redirectTargets) {
    this.redirectTargets = redirectTargets;
  }

  @GET
  @PermitAll
  public Response landing(
      @QueryParam("token_hash") String tokenHash,
      @QueryParam("type") String type,
      @QueryParam("next") String requestedTarget) {
    if (tokenHash == null || tokenHash.isBlank() || tokenHash.length() > MAX_TOKEN_HASH_LENGTH) {
      return page(Response.Status.BAD_REQUEST, "This email link is incomplete.", null);
    }
    if (!"signup".equals(type) && !"recovery".equals(type)) {
      return page(Response.Status.BAD_REQUEST, "This email link type is not supported.", null);
    }

    final String target;
    try {
      target = redirectTargets.resolve(requestedTarget);
    } catch (AuthException refusedTarget) {
      // Do not reflect an untrusted return address into HTML, logs, or a Location header.
      return page(Response.Status.BAD_REQUEST, "This return address is not available.", null);
    }

    URI continueUri =
        UriBuilder.fromUri(target).queryParam("token_hash", tokenHash).queryParam("type", type).build();
    return page(Response.Status.OK, "Continue to finish signing in.", continueUri);
  }

  private static Response page(Response.Status status, String message, URI continueUri) {
    String action =
        continueUri == null
            ? ""
            : "<a class=\"continue\" href=\"" + escapeHtml(continueUri.toASCIIString()) + "\">Continue</a>";
    String html =
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<title>Continue</title></head><body><main><h1>Continue</h1><p>"
            + escapeHtml(message)
            + "</p>"
            + action
            + "</main></body></html>";
    return Response.status(status)
        .type("text/html; charset=UTF-8")
        .header(REFERRER_POLICY, NO_REFERRER)
        .header(CACHE_CONTROL, NO_STORE)
        .header("X-Content-Type-Options", "nosniff")
        .entity(html)
        .build();
  }

  private static String escapeHtml(String value) {
    return value
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&#39;");
  }
}
