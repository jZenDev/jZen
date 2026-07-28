package zen.identity.auth;

import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;

/**
 * Landing route for Supabase email links (confirmation, recovery). Supabase verifies the token on
 * its side and then redirects the browser here — the URL Supabase is given via {@code redirect_to}
 * (the {@code AUTH_REDIRECT_URI} the backend passes on signup/recover) — with the new session token
 * in the URL <em>fragment</em> ({@code #access_token=...}).
 *
 * <p>The fragment is client-side only and never reaches the server, so this endpoint cannot read
 * the token. Its job is simply to not be a 404: it lands the now-confirmed user on the app, where
 * they sign in. Without it, the confirmation link dead-ends on "Resource not found".
 *
 * <p><b>Not yet done, on purpose:</b> consuming the fragment token to sign the user in automatically
 * after they confirm. That needs the client to read the fragment and exchange the token for a
 * cookie session (or Supabase's PKCE flow with a server-side code exchange), and is tracked
 * separately. Password recovery, which also lands here and needs the token to set a new password,
 * is part of the same follow-up.
 *
 * <p>Lives in {@code zen-identity} as a framework resource (discovered from the Jandex-indexed jar
 * like {@code AuthResource}); it is outside the {@code api/} prefix, so the transport filter and
 * dual-mode negotiation do not apply.
 */
@Path("/auth/callback")
public class AuthCallbackResource {

  @GET
  @PermitAll
  public Response landing() {
    // 303 See Other to the app root, tagged so the login screen can greet the user ("your email is
    // confirmed, please sign in"). The Location is set relative rather than via
    // Response.seeOther(URI), which JAX-RS would resolve to an absolute URL bound to the request's
    // host — wrong behind the deployed URL. A relative path resolves against whatever origin served
    // the link. The browser carries the original fragment (the token) along, which the app ignores.
    return Response.status(Response.Status.SEE_OTHER)
        .header("Location", "/?auth=email-confirmed")
        .build();
  }
}
