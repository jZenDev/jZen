package dev.zen.identity.auth;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.core.Cookie;
import jakarta.ws.rs.core.NewCookie;
import java.time.Duration;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Issues and clears the session cookies. Ported from
 * ../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/auth/SessionService.java,
 * <strong>un-hacked per TA-4</strong> (docs/architecture/BLUEPRINT.md).
 *
 * <p>The donor packed {@code "access|refresh"} into a single {@code __session} cookie and
 * carried {@code extractAccessToken}/{@code extractRefreshToken} split helpers, purely
 * because Firebase Hosting strips every cookie except {@code __session} at the CDN edge
 * (its ADR-034). jZen serves Cloud Run directly, so those are gone: the access token lives
 * in a normally-named {@code zen_access_token} cookie that SmallRye JWT parses on its own
 * (via {@code mp.jwt.token.cookie}, with {@code quarkus.http.auth.proactive=true}), and the
 * refresh token lives in its own {@code zen_refresh_token} cookie. The donor's manual
 * {@code SessionFilter} existed only to unpack {@code __session} and is not ported.
 *
 * <p>Cookie names match application.properties ({@code session.cookie.name} /
 * {@code session.cookie.refresh-name} / {@code mp.jwt.token.cookie}); keep them in sync.
 */
@ApplicationScoped
public class SessionService {

  /** Access-token cookie. Must equal {@code mp.jwt.token.cookie} so SmallRye JWT reads it. */
  public static final String ACCESS_COOKIE = "zen_access_token";

  /** Refresh-token cookie, read only by the {@code /auth/refresh} endpoint. */
  public static final String REFRESH_COOKIE = "zen_refresh_token";

  /** Double-submit CSRF cookie (JS-readable) and its companion request header. */
  public static final String CSRF_COOKIE = "XSRF-TOKEN";

  public static final String CSRF_HEADER = "X-CSRF-Token";

  /** Access tokens are short-lived; the refresh token outlives them and rotates on use. */
  static final Duration ACCESS_TOKEN_TTL = Duration.ofHours(1);

  // OWASP Session Management Cheat Sheet: refresh tokens expire after 7 days and rotate on
  // every use (Supabase issues a new refresh token on each /token call).
  static final Duration REFRESH_TOKEN_TTL = Duration.ofDays(7);

  @ConfigProperty(name = "session.cookie.secure", defaultValue = "false")
  boolean secureCookie;

  /** Access-token cookie (httpOnly, 1 hour). */
  public NewCookie accessCookie(String token) {
    return authCookie(ACCESS_COOKIE, token, ACCESS_TOKEN_TTL);
  }

  /** Refresh-token cookie (httpOnly, 7 days). */
  public NewCookie refreshCookie(String token) {
    return authCookie(REFRESH_COOKIE, token, REFRESH_TOKEN_TTL);
  }

  /** CSRF cookie (JS-readable, so the SPA can echo it in {@link #CSRF_HEADER}). */
  public NewCookie csrfCookie(String token) {
    return new NewCookie.Builder(CSRF_COOKIE)
        .value(token)
        .path("/")
        .httpOnly(false)
        .secure(secureCookie)
        .sameSite(NewCookie.SameSite.LAX)
        .maxAge((int) ACCESS_TOKEN_TTL.toSeconds())
        .build();
  }

  /** Expires a cookie by name (value cleared, max-age 0). */
  public NewCookie clearCookie(String name) {
    return new NewCookie.Builder(name)
        .value("")
        .path("/")
        .httpOnly(true)
        .secure(secureCookie)
        .sameSite(NewCookie.SameSite.LAX)
        .maxAge(0)
        .build();
  }

  public String generateCsrfToken() {
    return UUID.randomUUID().toString();
  }

  public String readCookie(Map<String, Cookie> cookies, String name) {
    Cookie cookie = cookies.get(name);
    return cookie == null ? null : cookie.getValue();
  }

  private NewCookie authCookie(String name, String token, Duration maxAge) {
    return new NewCookie.Builder(name)
        .value(token)
        .path("/")
        .httpOnly(true)
        .secure(secureCookie)
        .sameSite(NewCookie.SameSite.LAX)
        .maxAge((int) maxAge.toSeconds())
        .build();
  }
}
