package zen.identity.auth;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * ADR-050's recovery/ordinary password-change split rests on {@link AuthResource#amrMethods},
 * which reads Supabase's {@code amr} claim the way jose4j (under SmallRye JWT) actually delivers
 * a JSON array claim to {@code JsonWebToken.getClaim}: a {@link List} of {@link Map} entries.
 *
 * <p>A plain unit test in the library rather than a {@code @QuarkusTest}, for the reason
 * {@code CsrfRulesTest} and {@code RedirectTargetsTest} are: this is pure data-shape logic, and a
 * live handshake cannot exercise it anyway — a fabricated JWT is not a real Supabase session, so
 * a claim built by hand is the only way to state what this method does with a real one's shape
 * without a live Supabase JWKS to sign against ({@code IdentityServiceTest} gives the same reason
 * for not driving the authenticated password change itself over HTTP).
 */
class AuthResourceAmrMethodsTest {

  @Test
  void readsTheMethodOfEachEntry() {
    List<String> methods =
        AuthResource.amrMethods(
                List.of(
                    Map.of("method", "password", "timestamp", 1L),
                    Map.of("method", "recovery", "timestamp", 2L)))
            .toList();

    assertEquals(List.of("password", "recovery"), methods);
  }

  @Test
  void unexpectedShapesYieldNoMethodsRatherThanThrowing() {
    // A future Supabase change to this claim's shape must fail closed (no recovery method found,
    // so current_password stays required) rather than crash the request with a ClassCastException.
    assertTrue(AuthResource.amrMethods(null).toList().isEmpty());
    assertTrue(AuthResource.amrMethods("not-a-list").toList().isEmpty());
    assertTrue(AuthResource.amrMethods(List.of("not-a-map")).toList().isEmpty());
    assertTrue(AuthResource.amrMethods(List.of(Map.of("method", 123))).toList().isEmpty());
  }
}
