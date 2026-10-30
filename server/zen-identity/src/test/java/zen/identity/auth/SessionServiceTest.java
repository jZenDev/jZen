package zen.identity.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;

import jakarta.ws.rs.core.NewCookie;
import java.util.List;
import org.junit.jupiter.api.Test;
import zen.identity.AuthException;

/**
 * What may become a cookie value. A plain unit test beside {@code CsrfRulesTest}: the refusal is
 * the property, and it must hold for every character that could end a header line or a cookie.
 */
class SessionServiceTest {

  private final SessionService sessions = new SessionService();

  @Test
  void aJwtAndAnOpaqueRefreshTokenAreCarriedUnchanged() {
    String jwt = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.c2lnLV9fMDEyMw";
    NewCookie access = sessions.accessCookie(jwt);
    assertEquals(jwt, access.getValue());
    assertEquals("zen_refresh_token", sessions.refreshCookie("abcdEFGH1234").getName());
    assertEquals("abcdEFGH1234", sessions.refreshCookie("abcdEFGH1234").getValue());
    assertEquals(
        "f47ac10b-58cc-4372-a567-0e02b2c3d479",
        sessions.csrfCookie("f47ac10b-58cc-4372-a567-0e02b2c3d479").getValue());
  }

  @Test
  void aValueThatCouldEndAHeaderLineOrACookieIsRefusedWithoutEchoingIt() {
    List<String> hostile =
        List.of(
            "jwt\r\nSet-Cookie: pwned=1",
            "jwt\nX-Evil: 1",
            "jwt\rX",
            "jwt\u0000",
            "jwt\u007f",
            "jwt;Path=/x",
            "jwt,other=1",
            "jwt value",
            "jw\"t",
            "jw\\t",
            "jüwt",
            "jwt ");
    for (String bad : hostile) {
      AuthException access = assertThrows(AuthException.class, () -> sessions.accessCookie(bad), bad);
      assertEquals(502, access.status());
      assertEquals("invalid_session_token", access.code());
      assertFalse(access.getMessage().contains("pwned"), access.getMessage());
      assertThrows(AuthException.class, () -> sessions.refreshCookie(bad), bad);
      assertThrows(AuthException.class, () -> sessions.csrfCookie(bad), bad);
    }
  }

  @Test
  void clearingACookieStillWorks() {
    NewCookie cleared = sessions.clearCookie(SessionService.ACCESS_COOKIE);
    assertEquals("", cleared.getValue());
    assertEquals(0, cleared.getMaxAge());
  }
}
