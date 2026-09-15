package zen.demo;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * The {@code Origin} allowlist rule in isolation, free of a live handshake: a cross-origin
 * upgrade is exactly what CORS cannot police (the check does not run for WebSocket at all), so
 * this is the one place the defence in {@code DemoWebSocket#onOpen} is actually exercised. The
 * refusal itself (a real handshake torn down) needs a real session and is covered by
 * {@code DemoWebSocketSecurityTest}'s note on out-of-band verification.
 */
class DemoWebSocketOriginTest {

  private static final List<String> ALLOWED = List.of("http://localhost:8080", "http://localhost:5173");

  @Test
  void anOriginOnTheListIsAllowed() {
    assertTrue(DemoWebSocket.isAllowedOrigin("http://localhost:5173", ALLOWED));
  }

  @Test
  void anOriginNotOnTheListIsRefused() {
    assertFalse(DemoWebSocket.isAllowedOrigin("https://evil.example", ALLOWED));
  }

  @Test
  void anEmptyConfiguredListMeansUnrestrictedMatchingCorsItself() {
    // quarkus.http.cors.origins being unset/blank is CORS's own "no restriction" reading
    // (CorsCredentialsGuard treats it the same way); the WebSocket check must not silently become
    // stricter than the HTTP surface it is modeled on.
    assertTrue(DemoWebSocket.isAllowedOrigin("https://anything.example", List.of()));
  }

  @Test
  void aWildcardEntryAllowsEveryOrigin() {
    assertTrue(DemoWebSocket.isAllowedOrigin("https://anything.example", List.of("*")));
  }
}
