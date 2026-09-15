package zen.demo;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * The per-address ceiling {@code DemoWebSocket} relies on to survive a single caller holding the
 * whole instance's global capacity: {@code --max-instances=1} means there is no second instance
 * for anyone else to fail over to, so one address exhausting the global cap first is a
 * single-caller lock-out of the entire fleet. Config is pinned low so both ceilings are reachable
 * without opening hundreds of real connections.
 */
@QuarkusTest
@TestProfile(WebSocketConnectionsTest.TightCeilings.class)
class WebSocketConnectionsTest {

  public static class TightCeilings implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "zen.demo.websocket.max-connections", "5",
          "zen.demo.websocket.max-connections-per-address", "2");
    }
  }

  private static final String ADDRESS_A = "203.0.113.7";
  private static final String ADDRESS_B = "203.0.113.9";

  @Inject WebSocketConnections connections;

  @Test
  void anAddressCannotExceedItsOwnCeilingWhileOthersStillCan() {
    assertTrue(connections.tryAcquire(ADDRESS_A), "1st slot for A");
    assertTrue(connections.tryAcquire(ADDRESS_A), "2nd slot for A, at its ceiling");
    assertFalse(connections.tryAcquire(ADDRESS_A), "3rd slot for A must be refused");

    // The instance is nowhere near its own global ceiling (5) — A's refusal must not have taken
    // a global slot down with it, or a single caller could still starve everyone else one address
    // short of its own limit.
    assertTrue(connections.tryAcquire(ADDRESS_B), "a different address is unaffected by A's ceiling");

    connections.release(ADDRESS_A);
    connections.release(ADDRESS_A);
    connections.release(ADDRESS_B);
  }

  @Test
  void releasingFreesBothTheGlobalAndThePerAddressSlot() {
    assertTrue(connections.tryAcquire(ADDRESS_A));
    int openBeforeRelease = connections.openConnections();
    connections.release(ADDRESS_A);
    assertTrue(connections.openConnections() < openBeforeRelease, "the global count must drop");

    // The per-address slot was freed too: two more acquisitions for the same address succeed.
    assertTrue(connections.tryAcquire(ADDRESS_A));
    assertTrue(connections.tryAcquire(ADDRESS_A));
    connections.release(ADDRESS_A);
    connections.release(ADDRESS_A);
  }
}
