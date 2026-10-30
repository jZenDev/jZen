package zen.identity.auth;

import zen.identity.AuthException;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.core.NewCookie;
import java.time.Duration;
import java.util.UUID;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Issues and clears the session cookies.
 *
 * <p>Each token gets its own normally-named cookie: the access token in
 * {@code zen_access_token}, which SmallRye JWT parses on its own (via
 * {@code mp.jwt.token.cookie}, with {@code quarkus.http.auth.proactive=true}), and the
 * refresh token in {@code zen_refresh_token}. There is no session filter and nothing to
 * unpack, because nothing packs several tokens into one cookie.
 *
 * <p><strong>This depends on jZen serving Cloud Run directly.</strong> An edge that strips
 * cookies by name would break the whole path, and recovering from it would mean packing the
 * tokens into whatever single cookie survives plus a filter to unpack them. See
 * docs/architecture/STANDARDS.md "Deployment model" before putting a CDN in front.
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
        .value(cookieValue(CSRF_COOKIE, token))
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

  private NewCookie authCookie(String name, String token, Duration maxAge) {
    return new NewCookie.Builder(name)
        .value(cookieValue(name, token))
        .path("/")
        .httpOnly(true)
        .secure(secureCookie)
        .sameSite(NewCookie.SameSite.LAX)
        .maxAge((int) maxAge.toSeconds())
        .build();
  }

  /**
   * {@code token} if every character is a legal cookie octet (RFC 6265 section 4.1.1), else a 502.
   *
   * <p>The tokens come from Supabase, not from the caller, and a JWT or an opaque refresh token
   * is made of base64url characters and dots. A value with a CR/LF, space, quote, comma, semicolon
   * or backslash is not one, and it must never reach a {@code Set-Cookie} header. The HTTP layer
   * does not let it split the response, but left to it the request never completes (a test that
   * returns such a token from Supabase times out). Failing here turns that into a clean error, and
   * keeps the check in the code that builds the header rather than in whatever sits underneath.
   * The message names the cookie, never the value.
   */
  private static String cookieValue(String name, String token) {
    for (int i = 0; i < token.length(); i++) {
      char c = token.charAt(i);
      boolean legal =
          c == 0x21 || (c >= 0x23 && c <= 0x2B) || (c >= 0x2D && c <= 0x3A)
              || (c >= 0x3C && c <= 0x5B) || (c >= 0x5D && c <= 0x7E);
      if (!legal) {
        throw new AuthException(
            502,
            "invalid_session_token",
            "The identity provider returned a value for " + name + " that cannot be sent as a cookie.");
      }
    }
    return token;
  }
}
