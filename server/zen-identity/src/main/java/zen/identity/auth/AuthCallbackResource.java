package zen.identity.auth;

import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;

/**
 * Compatibility landing route for older Supabase email links (confirmation, recovery). The new
 * templates use {@link AuthConfirmResource} and return a one-time token hash here only after the
 * person continues. Older messages still ask Supabase to verify the token and return a session in
 * the URL fragment ({@code #access_token=...}).
 *
 * <p>The fragment is client-side only and never reaches the server, so this route cannot read the
 * legacy token. It bounces the browser to the app carrying the fragment, where the client posts it
 * to {@code POST /api/v1/auth/session}. The query-token branch is used only when the app's default
 * return address is this callback; it forwards the hash to the app, which posts it to
 * {@code POST /api/v1/auth/confirm}.
 *
 * <p>The legacy fragment redirect does not read or exchange tokens server-side. The query-token
 * branch is only a compatibility hand-off for configurations whose return address is this route;
 * new messages use the dedicated confirmation landing page.
 *
 * <p>Lives in {@code zen-identity} as a framework resource (discovered from the Jandex-indexed jar
 * like {@code AuthResource}); it is outside the {@code api/} prefix, so the transport filter and
 * dual-mode negotiation do not apply.
 */
@Path("/auth/callback")
public class AuthCallbackResource {

  @GET
  @PermitAll
  public Response landing(
      @QueryParam("token_hash") String tokenHash, @QueryParam("type") String type) {
    if (tokenHash != null
        && !tokenHash.isBlank()
        && ("signup".equals(type) || "recovery".equals(type))) {
      // The new flow returns only the hash to the app. It is submitted to the verifier after the
      // app has loaded; the old fragment flow below remains intact for already-sent mail.
      String location =
          UriBuilder.fromPath("/")
              .queryParam("token_hash", tokenHash)
              .queryParam("type", type)
              .build()
              .toASCIIString();
      return Response.status(Response.Status.SEE_OTHER)
          .header("Location", location)
          .header("Referrer-Policy", "no-referrer")
          .header("Cache-Control", "no-store")
          .build();
    }
    // 303 See Other to the app root. The browser carries the original fragment (the tokens) across
    // the redirect on its own, which is what lets the app consume them at the destination.
    //
    // The query flag is the fallback, not the mechanism: when a link arrives with no usable token
    // (an old link, a provider that stripped the fragment), the app has nothing to exchange and
    // falls back to greeting the user on the login screen. The Location is relative rather than a
    // Response.seeOther(URI), which JAX-RS would resolve against the request's host — wrong behind
    // the deployed URL; a relative path resolves against whatever origin served the link.
    return Response.status(Response.Status.SEE_OTHER)
        .header("Location", "/?auth=email-confirmed")
        .header("Referrer-Policy", "no-referrer")
        .header("Cache-Control", "no-store")
        .build();
  }
}
