package zen.transport;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * Unit tests for the origin-list half of {@link CorsCredentialsGuard}.
 *
 * <p>A plain JUnit test, not a {@code @QuarkusTest}, for the same reason as {@code
 * RedirectTargetsTest}: the interesting cases are the configurations an assembled application
 * <em>cannot</em> express. A running app has exactly one CORS origin list, and the one it has is
 * the safe one — so exercising the guard through the container would prove only that the correct
 * configuration boots, which is the case that was never in doubt.
 */
class CorsCredentialsGuardTest {

  @Test
  void explicitOrigins_areRestricted() {
    assertFalse(
        CorsCredentialsGuard.isUnrestricted(
            Optional.of(List.of("https://app.example.com", "http://localhost:5173"))));
  }

  @Test
  void wildcard_isUnrestricted() {
    assertTrue(CorsCredentialsGuard.isUnrestricted(Optional.of(List.of("*"))));
  }

  @Test
  void wildcardAmongRealOrigins_isStillUnrestricted() {
    /* One wildcard anywhere in the list allows every origin; the neighbours do not narrow it. */
    assertTrue(
        CorsCredentialsGuard.isUnrestricted(Optional.of(List.of("https://app.example.com", "*"))));
  }

  @Test
  void absentProperty_isUnrestricted() {
    /* Quarkus reads an unset origin list as "allow any origin", not as "allow none". */
    assertTrue(CorsCredentialsGuard.isUnrestricted(Optional.empty()));
  }

  @Test
  void emptyList_isUnrestricted() {
    /* The shape a blank CORS_ORIGINS secret produces. It reads like a lockdown and is the
     * opposite, which is exactly why it is worth a test of its own. */
    assertTrue(CorsCredentialsGuard.isUnrestricted(Optional.of(List.of())));
  }

  @Test
  void whitespaceOnlyEntries_areUnrestricted() {
    assertTrue(CorsCredentialsGuard.isUnrestricted(Optional.of(List.of("  ", ""))));
  }

  @Test
  void paddedWildcard_isUnrestricted() {
    assertTrue(CorsCredentialsGuard.isUnrestricted(Optional.of(List.of(" * "))));
  }
}
