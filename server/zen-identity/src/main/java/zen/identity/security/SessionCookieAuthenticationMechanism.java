package zen.identity.security;

import io.quarkus.security.AuthenticationFailedException;
import io.quarkus.security.identity.IdentityProviderManager;
import io.quarkus.security.identity.SecurityIdentity;
import io.quarkus.security.identity.request.AuthenticationRequest;
import io.quarkus.smallrye.jwt.runtime.auth.JWTAuthMechanism;
import io.quarkus.vertx.http.runtime.security.ChallengeData;
import io.quarkus.vertx.http.runtime.security.HttpAuthenticationMechanism;
import io.quarkus.vertx.http.runtime.security.HttpCredentialTransport;
import io.smallrye.mutiny.Uni;
import io.vertx.ext.web.RoutingContext;
import jakarta.annotation.Priority;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Alternative;
import jakarta.inject.Inject;
import java.util.Set;
import org.jboss.logging.Logger;

/**
 * An expired session cookie means "not signed in", not "error".
 *
 * <p>jZen keeps {@code quarkus.http.auth.proactive=true}, which authenticates every request before
 * it reaches JAX-RS. The default behaviour when the {@code zen_access_token} cookie fails to
 * verify is an {@link AuthenticationFailedException}, and proactive auth turns that into a 401
 * challenge <em>immediately</em> — before any resource, any filter, any provider. For a token
 * presented in an {@code Authorization} header that is the right answer: the caller deliberately
 * offered a credential and it was bad. For a cookie it is the wrong answer, because a cookie is
 * <em>ambient</em>: the browser attaches it without anyone deciding to, so "the cookie in your jar
 * is an hour old" is the most ordinary state a session ever reaches, not an error condition.
 *
 * <p>Three things were broken by treating it as one, all measured against a running server before
 * this class existed:
 *
 * <ul>
 *   <li><b>Sign-out was impossible.</b> {@code POST /auth/logout} answered 401 rather than clearing
 *       cookies, so the one action that ends a stale session was the one action a stale session
 *       could not perform — and after Wave 2 it is also where the upstream revocation happens.
 *   <li><b>Recovery was impossible.</b> {@code POST /auth/refresh} answered 401 too. That endpoint
 *       exists precisely to be called once the access token has expired, and its credential is the
 *       <em>refresh</em> cookie — but the expired access cookie travelling beside it killed the
 *       request first. A seven-day refresh token was unreachable from any client still holding the
 *       dead access cookie.
 *   <li><b>The rate limiter was bypassable.</b> {@code RateLimitFilter} is a JAX-RS filter, so a
 *       request rejected before JAX-RS is never counted. Attaching any junk value as
 *       {@code zen_access_token} therefore made a request unmetered on every endpoint while still
 *       occupying a concurrency slot — the exact resource {@code --concurrency=200} makes scarce
 *       (ADR-027). The filter's own javadoc says the 429 is charged before authentication; this is
 *       what makes that true.
 * </ul>
 *
 * <p><b>It fails closed.</b> Recovering from the failure produces <em>no identity</em>, never a
 * partial or assumed one, so the request proceeds exactly as an anonymous one: a
 * {@code @RolesAllowed} or {@code @Authenticated} route still answers 401 via {@link #getChallenge},
 * and {@code RoleAugmentor} has nothing to augment. What changes is only <em>when</em> that 401 is
 * decided and by whom — the route, on its own terms, instead of the transport layer on everyone's.
 *
 * <p><b>Why a wrapper rather than {@code proactive=false}.</b> Turning proactive auth off is the
 * documented lever and it is far broader: it changes the posture of every route at once, and it
 * does not even fix this, because any {@code @PermitAll} route that touches {@code SecurityIdentity}
 * — {@code AuthResource} does — forces the same failure lazily. A path-scoped
 * {@code quarkus.http.auth.permission.…policy=permit} was measured and does not suppress the
 * challenge either. This is the narrow change: one credential source, one reclassification.
 */
@Alternative
@Priority(1)
@ApplicationScoped
public class SessionCookieAuthenticationMechanism implements HttpAuthenticationMechanism {

  private static final Logger LOG = Logger.getLogger(SessionCookieAuthenticationMechanism.class);

  @Inject JWTAuthMechanism delegate;

  @Override
  public Uni<SecurityIdentity> authenticate(RoutingContext context, IdentityProviderManager idpm) {
    return delegate
        .authenticate(context, idpm)
        .onFailure(AuthenticationFailedException.class)
        .recoverWithItem(
            failure -> {
              /*
               * DEBUG rather than WARN, and that is a decision rather than an oversight. This fires
               * once per request for any client holding a cookie that has aged out, which is
               * routine and self-correcting - so logging it loudly would turn an ordinary session
               * expiry into log volume an attacker could amplify at will, in a service billed for
               * what it writes. The event is not lost: an unauthenticated request now reaches the
               * rate limiter and is counted like any other, so abuse shows up as 429s and counters
               * rather than as a wall of identical lines. Nothing about the token is logged.
               */
              LOG.debugf(
                  "Session cookie did not verify on %s; continuing as anonymous", context.request().path());
              return null;
            });
  }

  /**
   * Unchanged: a route that requires an identity still challenges when there is none. This is the
   * half that keeps the reclassification honest — refusing later is not refusing less.
   */
  @Override
  public Uni<ChallengeData> getChallenge(RoutingContext context) {
    return delegate.getChallenge(context);
  }

  @Override
  public Set<Class<? extends AuthenticationRequest>> getCredentialTypes() {
    return delegate.getCredentialTypes();
  }

  @Override
  public Uni<HttpCredentialTransport> getCredentialTransport(RoutingContext context) {
    return delegate.getCredentialTransport(context);
  }

  @Override
  public int getPriority() {
    return delegate.getPriority();
  }
}
