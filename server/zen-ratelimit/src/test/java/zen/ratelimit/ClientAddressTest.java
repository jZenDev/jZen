package zen.ratelimit;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Nested;

/**
 * The spoofing tests. A rate limiter's whole value rests on this one function, and both ways of
 * getting it wrong are silent, so the dangerous inputs are expressed here directly — an assembled
 * application only ever produces the safe one.
 */
class ClientAddressTest {

  private static final String REAL_PEER = "203.0.113.7";
  private static final String ATTACKER_CLAIM = "9.9.9.9";

  @Nested
  @DisplayName("with no trusted proxy (hops = 0, the default)")
  class Untrusted {

    @Test
    void aSpoofedForwardedForHeaderIsIgnoredEntirely() {
      // The attack: send your own X-Forwarded-For and get a fresh identity, and therefore a fresh
      // budget, on every single request. If this ever returns the header value the limiter is
      // decorative.
      assertEquals(REAL_PEER, ClientAddress.resolve(ATTACKER_CLAIM, REAL_PEER, 0));
    }

    @Test
    void aChainOfInventedHopsIsAlsoIgnored() {
      assertEquals(
          REAL_PEER, ClientAddress.resolve("1.1.1.1, 2.2.2.2, 3.3.3.3", REAL_PEER, 0));
    }

    @Test
    void everyDistinctSpoofStillResolvesToTheSameSubject() {
      // The property that actually matters: an attacker cycling the header cannot escape a bucket.
      String first = ClientAddress.resolve("10.0.0.1", REAL_PEER, 0);
      String second = ClientAddress.resolve("10.0.0.2", REAL_PEER, 0);
      assertEquals(first, second);
    }
  }

  @Nested
  @DisplayName("behind one trusted proxy (hops = 1, Cloud Run served directly)")
  class OneHop {

    @Test
    void theAppendedRightmostEntryWinsOverTheCallersOwn() {
      // Cloud Run's frontend APPENDS the real peer to whatever the caller sent. The conventional
      // "leftmost is the client" reading would take ATTACKER_CLAIM here, which is the bypass.
      assertEquals(
          REAL_PEER, ClientAddress.resolve(ATTACKER_CLAIM + ", " + REAL_PEER, "10.0.0.5", 1));
    }

    @Test
    void paddingTheHeaderWithExtraHopsDoesNotMoveTheAnswer() {
      // An attacker who guesses the hop count and pads the list still cannot shift the entry that
      // infrastructure wrote, because it is counted from the right.
      assertEquals(
          REAL_PEER,
          ClientAddress.resolve("a, b, c, d, e, " + REAL_PEER, "10.0.0.5", 1));
    }

    @Test
    void twoDifferentClaimsBehindTheSameRealPeerShareOneSubject() {
      assertEquals(
          ClientAddress.resolve("1.1.1.1, " + REAL_PEER, "10.0.0.5", 1),
          ClientAddress.resolve("2.2.2.2, " + REAL_PEER, "10.0.0.5", 1));
    }

    @Test
    void twoGenuinelyDifferentCallersDoNotShareOne() {
      assertNotEquals(
          ClientAddress.resolve("x, 198.51.100.1", "10.0.0.5", 1),
          ClientAddress.resolve("x, 198.51.100.2", "10.0.0.5", 1));
    }

    @Test
    void aRequestThatCarriesNoHeaderFallsBackToTheSocketPeer() {
      // Configured for a proxy, but the request did not come through one.
      assertEquals("10.0.0.5", ClientAddress.resolve(null, "10.0.0.5", 1));
    }

    @Test
    void aShorterChainThanConfiguredFallsBackToItsLeftmostEntry() {
      // Fewer entries than trusted hops means the whole list was written by infrastructure.
      assertEquals(REAL_PEER, ClientAddress.resolve(REAL_PEER, "10.0.0.5", 3));
    }
  }

  @Nested
  @DisplayName("normalisation")
  class Normalisation {

    @Test
    void theSourcePortIsStrippedFromIpv4() {
      // Left on, the port would hand every new connection its own counter, which is the "blocks
      // no one" failure by a different route.
      assertEquals("203.0.113.7", ClientAddress.normalize("203.0.113.7:51514"));
    }

    @Test
    void aBracketedIpv6LiteralLosesItsBracketsAndPort() {
      assertEquals("::1", ClientAddress.normalize("[::1]:54321"));
    }

    @Test
    void abareIpv6LiteralIsLeftAlone() {
      assertEquals("2001:db8::1", ClientAddress.normalize("2001:db8::1"));
    }

    @Test
    void anAbsentAddressBecomesOneSharedBucketRatherThanAnExemption() {
      assertEquals(ClientAddress.UNKNOWN, ClientAddress.resolve(null, null, 0));
      assertEquals(ClientAddress.UNKNOWN, ClientAddress.resolve(null, "   ", 0));
    }

    @Test
    void blankHopsInTheHeaderAreDropped() {
      assertEquals(2, ClientAddress.parse("1.1.1.1, , 2.2.2.2").size());
    }
  }
}
