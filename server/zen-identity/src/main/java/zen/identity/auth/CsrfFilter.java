package zen.identity.auth;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.inject.Inject;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.container.ContainerRequestFilter;
import jakarta.ws.rs.core.Cookie;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.ext.Provider;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import zen.proto.v1.ZenError;

/**
 * Enforces the double-submit CSRF token the session already issues.
 *
 * <p>{@link SessionService} has always minted a random token into the JS-readable
 * {@code XSRF-TOKEN} cookie beside the httpOnly session cookie, and nothing ever checked it. This
 * is the other half: a mutating request that is being authenticated by the session cookie must
 * echo that same value in {@code X-CSRF-Token}. The asymmetry is the whole mechanism — a page on
 * another origin can cause the browser to <em>send</em> the cookie but the same-origin policy
 * stops it <em>reading</em> the cookie, so it cannot produce the header.
 *
 * <p><strong>The check runs only when the caller is actually authenticated</strong> — not merely
 * when a session cookie is present. That distinction is the whole of it:
 *
 * <ul>
 *   <li>It is exactly the set of requests CSRF is about. Forgery rides on an <em>ambient</em>
 *       credential the server <em>accepts</em>. A request the server does not accept has nothing to
 *       forge with, and one that authenticates by something the caller had to supply deliberately —
 *       the job trigger's shared secret — cannot be forged this way at all.
 *   <li>It keeps a stale session returning 401 rather than 403. A client whose access token has
 *       aged out is anonymous ({@code SessionCookieAuthenticationMechanism}), so it reads a 401 it
 *       knows how to act on — refresh, retry — instead of a 403 that tells it nothing and that it
 *       cannot clear, since the CSRF cookie it would need expired alongside the access token.
 *       Signing out would be impossible for the same reason.
 * </ul>
 *
 * <p>An earlier version of this filter keyed on the cookie being <em>present</em> and justified it
 * by noting that authentication had already succeeded by the time the filter ran. That was true
 * only because an unverifiable cookie was rejected with a 401 before any filter — which was itself
 * the defect {@code SessionCookieAuthenticationMechanism} fixes. Keying on the identity says
 * directly what the old rule was inferring, and no longer depends on a behaviour that has changed
 * once already.
 *
 * <p>Which routes are in scope, and the reason each exemption exists, is
 * {@link CsrfRules} — separated so it can be tested as a function.
 *
 * <p>Discovered as a {@code @Provider} from this module's jar only because zen-identity runs
 * {@code jandex-maven-plugin}. Without {@code META-INF/jandex.idx} this class is on the classpath,
 * compiles, and is never instantiated: no error, no warning, a green suite, and a token that is
 * still issued and still never checked — which is indistinguishable from the defect this closes.
 * {@code CsrfWiringTest} in the app module fails the build if that happens.
 */
@Provider
public class CsrfFilter implements ContainerRequestFilter {

  private static final Logger LOG = Logger.getLogger(CsrfFilter.class);

  /** {@code ZenError} code returned to a caller whose request failed the check. */
  static final String ERROR_CSRF = "csrf_failed";

  private static final String MESSAGE =
      "This request could not be verified. Reload the page and try again.";

  /**
   * The escape hatch, on by default.
   *
   * <p>An application that turns this off is choosing to rely on {@code SameSite=Lax} alone, and
   * should know it is choosing. It exists because a framework control that cannot be switched off
   * gets worked around instead, and a documented flag is a better record of that decision than a
   * fork.
   */
  @ConfigProperty(name = "zen.csrf.enabled", defaultValue = "true")
  boolean enabled;

  @Inject SecurityIdentity identity;

  @Override
  public void filter(ContainerRequestContext ctx) {
    if (!enabled) {
      return;
    }
    if (!CsrfRules.applies(ctx.getMethod(), ctx.getUriInfo().getPath())) {
      return;
    }
    if (identity == null || identity.isAnonymous()) {
      // No accepted credential, nothing to forge. The request continues and is judged on its own
      // merits - which for a route that needs a user means a 401 the client can act on.
      return;
    }

    Map<String, Cookie> cookies = ctx.getCookies();
    Cookie token = cookies.get(SessionService.CSRF_COOKIE);
    String header = ctx.getHeaderString(SessionService.CSRF_HEADER);
    if (token == null || !matches(token.getValue(), header)) {
      /* No address, no token, no header value in the log line: the first is personal data, and the
       * other two are the credential itself. The method and path are what an operator acts on. */
      LOG.infof(
          "CSRF check refused %s %s: an authenticated request arrived without a matching %s header",
          ctx.getMethod(), ctx.getUriInfo().getPath(), SessionService.CSRF_HEADER);

      ctx.abortWith(
          Response.status(Response.Status.FORBIDDEN)
              .entity(ZenError.newBuilder().setCode(ERROR_CSRF).setMessage(MESSAGE).build())
              .build());
    }
  }

  /**
   * Constant-time comparison of the cookie's value against the header's.
   *
   * <p>The token is a secret the caller is proving they can read, so comparing it with
   * {@code equals} would leak how much of a guess was right through timing — the same reasoning
   * {@code JobTriggerAuthenticator} applies to the trigger secret. Differing lengths return false
   * immediately, which reveals only the length of a random UUID that is the same length every time.
   */
  private static boolean matches(String cookieValue, String headerValue) {
    if (cookieValue == null || headerValue == null || cookieValue.isEmpty()) {
      return false;
    }
    return MessageDigest.isEqual(
        cookieValue.getBytes(StandardCharsets.UTF_8), headerValue.getBytes(StandardCharsets.UTF_8));
  }
}
