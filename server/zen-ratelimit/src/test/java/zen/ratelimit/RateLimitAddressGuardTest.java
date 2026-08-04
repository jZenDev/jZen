package zen.ratelimit;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * The two contradictory configurations, expressed here because an assembled application can only
 * ever have a consistent one — the same division of labour as {@code CorsCredentialsGuardTest}.
 */
class RateLimitAddressGuardTest {

  @Test
  void proxyForwardingWithoutTrustedHopsIsRefused() {
    // Vert.x has already replaced the socket peer with the caller-supplied leftmost
    // X-Forwarded-For entry, so falling back to "the socket peer" would count attacker input.
    IllegalStateException thrown =
        assertThrows(IllegalStateException.class, () -> RateLimitAddressGuard.verify(true, 0));
    assertTrue(thrown.getMessage().contains(RateLimitAddressGuard.HOPS_PROPERTY));
    assertTrue(
        thrown.getMessage().contains("throttle nobody"),
        "the message has to say what actually breaks, not just that something is inconsistent");
  }

  @Test
  void trustedHopsWithoutProxyForwardingIsRefused() {
    assertThrows(IllegalStateException.class, () -> RateLimitAddressGuard.verify(false, 1));
  }

  @Test
  void theTwoConsistentPairingsBoot() {
    assertDoesNotThrow(() -> RateLimitAddressGuard.verify(false, 0), "%dev / %test: no proxy");
    assertDoesNotThrow(() -> RateLimitAddressGuard.verify(true, 1), "%prod: Cloud Run in front");
  }
}
