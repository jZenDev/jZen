package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import zen.identity.AuthException;
import zen.identity.IdentityService;
import zen.identity.auth.RedirectTargets;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.UserUpdateRequest;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;

/**
 * Service-level proof for the two rules that decide where a session token may go: which bearer a
 * password change is made with, and which return addresses an email link may be sent to.
 *
 * <p>Deliberately not driven over HTTP. Proving the authenticated password change through the REST
 * layer means presenting a session cookie, and a fabricated one is not a session — it makes the
 * test a statement about how convincingly the fake was assembled rather than about the code. The
 * REST layer's own claim, that the endpoint refuses an unauthenticated caller, is asserted in
 * {@code AuthResourceTest}; what is left is this logic, and it is exact here.
 */
@QuarkusTest
class IdentityServiceTest {

  @InjectMock @RestClient SupabaseAuthClient authClient;

  @Inject IdentityService identityService;
  @Inject RedirectTargets redirectTargets;

  @Test
  void setPassword_changesThePasswordOfWhoeverTheTokenBelongsTo() {
    identityService.setPassword("session-jwt", "a-new-secret");

    // No user id is passed, and none could be: Supabase resolves the account from the bearer. That
    // is what makes it impossible for one session to change another session's password.
    verify(authClient).updateUser("Bearer session-jwt", new UserUpdateRequest("a-new-secret"));
  }

  @Test
  void setPassword_blankPassword_isRefusedBeforeSupabaseIsCalled() {
    AuthException thrown =
        assertThrows(AuthException.class, () -> identityService.setPassword("session-jwt", "  "));

    assertEquals("weak_password", thrown.code());
    verify(authClient, never()).updateUser(any(), any());
  }

  @Test
  void redirectTargets_blankRequestGetsTheDefault() {
    String configured = redirectTargets.allowed().get(0);

    assertEquals(configured, redirectTargets.resolve(null));
    assertEquals(configured, redirectTargets.resolve(""));
    assertEquals(configured, redirectTargets.resolve("   "));
  }

  @Test
  void redirectTargets_exactMatchOnly() {
    String configured = redirectTargets.allowed().get(0);

    // Asking for the default by name is allowed — it is a member of its own allowlist.
    assertEquals(configured, redirectTargets.resolve(configured));
    // Surrounding whitespace is a transport artefact, not a different address.
    assertEquals(configured, redirectTargets.resolve("  " + configured + "  "));

    // Everything else is refused, and these are the shapes a prefix or host check would have let
    // through — which is the reason the match is exact.
    for (String hostile :
        new String[] {
          configured + "/../evil",
          configured + ".evil.example",
          configured + "@evil.example",
          "https://evil.example/steal",
          "zen-evil://callback",
        }) {
      AuthException thrown =
          assertThrows(
              AuthException.class, () -> redirectTargets.resolve(hostile), hostile + " must be refused");
      assertEquals("invalid_redirect", thrown.code());
      assertEquals(400, thrown.status());
      // The refused value is untrusted text; it must not be reflected back to the caller.
      assertTrue(
          !thrown.getMessage().contains("evil"),
          "the rejection must not echo the address it refused");
    }
  }
}
