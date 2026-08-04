package zen.identity.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import io.quarkus.security.identity.SecurityIdentity;
import jakarta.ws.rs.container.ContainerRequestContext;
import jakarta.ws.rs.core.Cookie;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriInfo;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import zen.proto.v1.ZenError;

/**
 * The filter's decision, case by case.
 *
 * <p>A plain unit test rather than a {@code @QuarkusTest}, for the reason {@code RedirectTargetsTest}
 * and {@code ClientAddressTest} are: the states worth asserting are combinations of identity,
 * cookies and header that an assembled application will not produce on demand, and driving the
 * filter directly says what it decides without a fixture standing in the way. The app module proves
 * it is <em>discovered</em> and enforced end to end ({@code CsrfWiringTest}), and the live gate
 * proves it refuses a real session's forged request.
 *
 * <p>The gate is the caller's identity, not the presence of a cookie. An earlier version keyed on
 * the cookie and leaned on authentication having already succeeded by the time the filter ran —
 * which held only while an unverifiable cookie was rejected with a 401 before any filter, the very
 * behaviour {@code SessionCookieAuthenticationMechanism} had to fix. {@link
 * #aStaleSessionCookieIsNotEnoughToTriggerTheCheck} is that lesson, kept.
 */
class CsrfFilterTest {

  private static final String PATH = "/api/v1/auth/logout";

  @Test
  void aMutatingCallWithASessionCookieAndNoHeaderIsRefused() {
    ContainerRequestContext ctx =
        request("POST", PATH, cookies(SessionService.ACCESS_COOKIE, "jwt", SessionService.CSRF_COOKIE, token()), null);

    filter().filter(ctx);

    assertEquals(403, abortedStatus(ctx));
    assertEquals(CsrfFilter.ERROR_CSRF, abortedError(ctx).getCode());
  }

  @Test
  void aMutatingCallWithAMismatchedHeaderIsRefused() {
    // The forged case in full. A cross-site page can cause the cookie to be sent but the
    // same-origin policy stops it reading the cookie, so the best it can do is guess.
    ContainerRequestContext ctx =
        request(
            "POST",
            PATH,
            cookies(SessionService.ACCESS_COOKIE, "jwt", SessionService.CSRF_COOKIE, token()),
            token());

    filter().filter(ctx);

    assertEquals(403, abortedStatus(ctx));
  }

  @Test
  void anAuthenticatedCallWithNoCsrfCookieAtAllIsRefused() {
    // Fails closed. The access and CSRF cookies are issued by the same response, so an accepted
    // session arriving without its token is not a state the server produces - and if it somehow
    // is, the answer is "refuse", never "there is nothing to compare against, so allow".
    ContainerRequestContext ctx = request("POST", PATH, Map.of(), token());

    filter().filter(ctx);

    assertEquals(403, abortedStatus(ctx));
  }

  @Test
  void aMatchingHeaderPasses() {
    String token = token();
    ContainerRequestContext ctx =
        request(
            "POST",
            PATH,
            cookies(SessionService.ACCESS_COOKIE, "jwt", SessionService.CSRF_COOKIE, token),
            token);

    filter().filter(ctx);

    verify(ctx, never()).abortWith(any());
  }

  @Test
  void anAnonymousCallerIsNeverChecked() {
    // Nothing the server accepts, so nothing to forge - the request continues and is judged on its
    // own credentials, which for a route that needs a user means a 401 the client can act on.
    ContainerRequestContext ctx = request("POST", PATH, Map.of(), null);

    filter(anonymous()).filter(ctx);

    verify(ctx, never()).abortWith(any());
  }

  @Test
  void aStaleSessionCookieIsNotEnoughToTriggerTheCheck() {
    // The case that made this gate key on the identity rather than on the cookie. A client whose
    // access token has aged out still sends the cookie until the browser drops it, but
    // SessionCookieAuthenticationMechanism makes it anonymous - and if the mere presence of that
    // cookie switched the check on, the reply would be a 403 the client cannot clear, because the
    // CSRF cookie it would need expired alongside the access token. Signing out would be
    // impossible for exactly the sessions that most need to end.
    ContainerRequestContext ctx =
        request("POST", PATH, cookies(SessionService.ACCESS_COOKIE, "expired.or.garbage"), null);

    filter(anonymous()).filter(ctx);

    verify(ctx, never()).abortWith(any());
  }

  @Test
  void aReadIsNeverChecked() {
    // Every page load is a GET carrying the session cookie and no header. If this ever refused,
    // the app would stop working entirely rather than partially.
    ContainerRequestContext ctx =
        request(
            "GET",
            "/api/v1/auth/identity",
            cookies(SessionService.ACCESS_COOKIE, "jwt", SessionService.CSRF_COOKIE, token()),
            null);

    filter().filter(ctx);

    verify(ctx, never()).abortWith(any());
  }

  @Test
  void anExemptRouteIsNotCheckedEvenWithASession() {
    // The trigger's caller is Cloud Scheduler, which has no cookie jar; the exemption is by route
    // rather than by guessing at the caller, so a stray session cookie must not switch it on.
    ContainerRequestContext ctx =
        request(
            "POST",
            "/api/v1/jobs/trigger",
            cookies(SessionService.ACCESS_COOKIE, "jwt", SessionService.CSRF_COOKIE, token()),
            null);

    filter().filter(ctx);

    verify(ctx, never()).abortWith(any());
  }

  @Test
  void disablingItTurnsTheCheckOff() {
    // The escape hatch does what it says, and an application choosing it is choosing to rely on
    // SameSite=Lax alone.
    CsrfFilter disabled = filter();
    disabled.enabled = false;
    ContainerRequestContext ctx =
        request("POST", PATH, cookies(SessionService.ACCESS_COOKIE, "jwt", SessionService.CSRF_COOKIE, token()), null);

    disabled.filter(ctx);

    verify(ctx, never()).abortWith(any());
  }

  /** A filter whose caller holds an accepted session — the state the check applies to. */
  private static CsrfFilter filter() {
    return filter(authenticated());
  }

  private static CsrfFilter filter(SecurityIdentity identity) {
    CsrfFilter filter = new CsrfFilter();
    filter.enabled = true;
    filter.identity = identity;
    return filter;
  }

  private static SecurityIdentity authenticated() {
    SecurityIdentity identity = mock(SecurityIdentity.class);
    when(identity.isAnonymous()).thenReturn(false);
    return identity;
  }

  private static SecurityIdentity anonymous() {
    SecurityIdentity identity = mock(SecurityIdentity.class);
    when(identity.isAnonymous()).thenReturn(true);
    return identity;
  }

  private static String token() {
    return UUID.randomUUID().toString();
  }

  private static Map<String, Cookie> cookies(String... nameValuePairs) {
    Map<String, Cookie> cookies = new LinkedHashMap<>();
    for (int i = 0; i < nameValuePairs.length; i += 2) {
      cookies.put(
          nameValuePairs[i], new Cookie.Builder(nameValuePairs[i]).value(nameValuePairs[i + 1]).build());
    }
    return cookies;
  }

  private static ContainerRequestContext request(
      String method, String path, Map<String, Cookie> cookies, String csrfHeader) {
    UriInfo uriInfo = mock(UriInfo.class);
    when(uriInfo.getPath()).thenReturn(path);

    ContainerRequestContext ctx = mock(ContainerRequestContext.class);
    when(ctx.getMethod()).thenReturn(method);
    when(ctx.getUriInfo()).thenReturn(uriInfo);
    when(ctx.getCookies()).thenReturn(cookies);
    when(ctx.getHeaderString(SessionService.CSRF_HEADER)).thenReturn(csrfHeader);
    return ctx;
  }

  private static int abortedStatus(ContainerRequestContext ctx) {
    return aborted(ctx).getStatus();
  }

  private static ZenError abortedError(ContainerRequestContext ctx) {
    return (ZenError) aborted(ctx).getEntity();
  }

  private static Response aborted(ContainerRequestContext ctx) {
    ArgumentCaptor<Response> captor = ArgumentCaptor.forClass(Response.class);
    verify(ctx).abortWith(captor.capture());
    return captor.getValue();
  }
}
