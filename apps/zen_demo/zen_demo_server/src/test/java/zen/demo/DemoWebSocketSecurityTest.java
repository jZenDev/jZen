package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.common.http.TestHTTPResource;
import jakarta.inject.Inject;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.WebSocket;
import java.util.Map;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutionException;
import org.eclipse.microprofile.config.Config;
import org.junit.jupiter.api.Test;

/**
 * The socket's two bounds, asserted where they can be: an unauthenticated handshake is refused,
 * and the frame ceilings are actually configured.
 *
 * <p>The socket was the one route into this application that required no credential at all — an
 * anonymous caller could open it, and the session cookie every other route insists on was never
 * consulted. It is also the one route the rate limiter cannot police: {@code RateLimitFilter} is a
 * JAX-RS provider, and a connection leaves JAX-RS behind the moment the upgrade completes, so the
 * limiter charges the handshake and nothing after it. The handshake is therefore the only place
 * the socket can be bounded, which is why it is bounded there.
 *
 * <p>The <em>authenticated</em> half of the same seam is asserted by the live e2e gate rather than
 * here, because proving it needs a real Supabase session; {@code the WebSocket echoes a message
 * back} in {@code e2e_test.dart} passes only if the cookie reaches the upgrade.
 */
@QuarkusTest
@TestProfile(DemoWebSocketSecurityTest.LooseLimiter.class)
class DemoWebSocketSecurityTest {

  /**
   * Keeps the rate limiter out of the way of a test about authentication. The handshake is an
   * ordinary {@code /api/} request and is counted like one; with {@code %test}'s own values that
   * is already fine, and pinning it here means this test cannot start failing for the other
   * module's reasons.
   */
  public static class LooseLimiter implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("zen.ratelimit.global.burst-limit", "10000");
    }
  }

  @TestHTTPResource("/api/v1/demo/ws")
  URI socketUri;

  @Inject Config config;

  @Test
  void anAnonymousHandshakeIsRefused() throws Exception {
    try {
      HttpClient.newHttpClient()
          .newWebSocketBuilder()
          .buildAsync(socketUri, new WebSocket.Listener() {})
          .get();
      throw new AssertionError(
          "the upgrade succeeded without a session — DemoWebSocket's @Authenticated is not being"
              + " enforced, and the socket is once again the one unauthenticated way in");
    } catch (ExecutionException | CompletionException e) {
      // The JDK client surfaces a refused upgrade as a failed handshake; the exact exception type
      // is a JDK detail, so the assertion is that it did not connect rather than how it said so.
      assertTrue(e.getCause() != null, "expected a handshake failure, got: " + e);
    }
  }

  @Test
  void theFrameAndMessageCeilingsAreConfigured() {
    // quarkus.http.limits.max-body-size does NOT apply to WebSocket frames, so losing these two
    // lines from application.properties reopens an unbounded in-memory buffer on one connection —
    // with no error and no failing behaviour anywhere to notice it by.
    assertEquals(
        65536,
        config.getValue("quarkus.websockets-next.server.max-frame-size", Integer.class),
        "the WebSocket frame ceiling is gone");
    assertEquals(
        65536,
        config.getValue("quarkus.websockets-next.server.max-message-size", Integer.class),
        "the message ceiling is gone, so the same hole is open one fragment at a time");
  }
}
