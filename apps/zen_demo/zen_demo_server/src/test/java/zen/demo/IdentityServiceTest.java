package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;

import zen.identity.AuthException;
import zen.identity.IdentityService;
import zen.identity.auth.RedirectTargets;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.auth.UserUpdateRequest;
import zen.identity.user.User;
import zen.identity.user.UserStore;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import java.util.Map;
import java.util.UUID;
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
  @Inject UserStore userStore;

  /** Stands in for a session's subject; it only ever reaches a log line. */
  private static final UUID USER_ID = UUID.fromString("00000000-0000-4000-8000-000000000001");

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
  void logout_revokesTheSessionUpstreamWithTheLocalScope() {
    assertTrue(identityService.logout("session-jwt", USER_ID));

    // The whole of F4: without this call the refresh token behind the cleared cookie stays valid
    // upstream for its full seven days, so signing out on a borrowed machine changes nothing.
    // Local scope, not global - a sign-out button ends this session, not every device the user owns.
    verify(authClient).logout("Bearer session-jwt", "local");
  }

  @Test
  void logout_withNoToken_callsNothing() {
    assertFalse(identityService.logout(null, USER_ID));
    assertFalse(identityService.logout("   ", USER_ID));

    verify(authClient, never()).logout(any(), any());
  }

  @Test
  void logout_whenSupabaseIsUnreachable_reportsFailureInsteadOfThrowing() {
    // A throw here would propagate out of AuthResource and take the cookie clearing with it,
    // leaving a user who pressed sign out still signed in locally *and* upstream. So it returns
    // false - and logs, because a session that is still live upstream is a security event.
    doThrow(new IllegalStateException("supabase unreachable"))
        .when(authClient)
        .logout(any(), any());

    assertFalse(identityService.logout("session-jwt", USER_ID));
  }

  @Test
  void logout_whenTheTokenWasAlreadyRevoked_countsAsRevoked() {
    // The provider refuses a token it will not accept with 401 or 403 - which spelling depends on
    // how it failed. Both mean the session is already gone, which is exactly what was asked for.
    // Treating 403 as a failure logged a security warning on the most ordinary path there is, which
    // is how it was found: against a live local Supabase, an unverifiable token came back 403.
    for (int refusal : new int[] {401, 403}) {
      doThrow(new WebApplicationException(refusal)).when(authClient).logout(any(), any());

      assertTrue(identityService.logout("session-jwt", USER_ID), "HTTP " + refusal);
    }
  }

  @Test
  void upsertOnLogin_syncsTheEmailAddressOnEveryLogin() {
    UUID id = UUID.randomUUID();

    userStore.upsertOnLogin(payload(id, "before@example.com"), null);
    User afterFirst = userStore.findById(id);
    assertEquals("before@example.com", afterFirst.email);

    // The user changes their address with the identity provider. Before this was synced, the local
    // profile kept the old one for good: every email jZen sent went somewhere the user had left,
    // and the admin panel displayed an address that was simply wrong.
    userStore.upsertOnLogin(payload(id, "after@example.com"), null);
    assertEquals("after@example.com", userStore.findById(id).email);
  }

  @Test
  void upsertOnLogin_aPayloadWithNoEmailDoesNotEraseTheStoredOne() {
    // users.email is NOT NULL, and GoTrue's bare-user shape can arrive without an address.
    // Copying that blank over would turn a stale row into an unusable one.
    UUID id = UUID.randomUUID();
    userStore.upsertOnLogin(payload(id, "kept@example.com"), null);

    userStore.upsertOnLogin(payload(id, null), null);
    assertEquals("kept@example.com", userStore.findById(id).email);

    userStore.upsertOnLogin(payload(id, "  "), null);
    assertEquals("kept@example.com", userStore.findById(id).email);
  }

  private static SupabaseSessionResponse.UserPayload payload(UUID id, String email) {
    return new SupabaseSessionResponse.UserPayload(
        id.toString(), email, "authenticated", "2024-01-01T00:00:00Z", Map.of());
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
