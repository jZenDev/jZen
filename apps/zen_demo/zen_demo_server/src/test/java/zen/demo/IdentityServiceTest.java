package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import zen.identity.AuthException;
import zen.identity.IdentityService;
import zen.identity.auth.RedirectTargets;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.auth.SupabaseTokenRequest;
import zen.identity.auth.SupabaseUnavailableException;
import zen.identity.auth.UserUpdateRequest;
import zen.identity.user.User;
import zen.identity.user.UserStore;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
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

  private static SupabaseSessionResponse.UserPayload userPayload(String email) {
    return new SupabaseSessionResponse.UserPayload(
        UUID.randomUUID().toString(), email, "authenticated", "2024-01-01T00:00:00Z", Map.of());
  }

  private static SupabaseSessionResponse freshSession(String access, String refresh, String email) {
    return new SupabaseSessionResponse(
        access, refresh, userPayload(email), null, null, null, null, null, null);
  }

  @Test
  void setPassword_blankPassword_isRefusedBeforeSupabaseIsCalled() {
    AuthException thrown =
        assertThrows(
            AuthException.class,
            () -> identityService.setPassword("session-jwt", "old-secret", "  ", false));

    assertEquals("weak_password", thrown.code());
    verify(authClient, never()).updateUser(any(), any());
  }

  /**
   * ADR-050: an ordinary signed-in user changing their password must prove the current one first.
   * No user id is ever passed to {@code updateUser} — Supabase resolves the account from the
   * bearer, which is what makes it impossible for one session to change another session's
   * password.
   */
  @Test
  void setPassword_ordinaryChange_verifiesCurrentPasswordThenRevokesAndReissues() {
    // A distinct email per test that reaches toSession(): it upserts into a real (Dev Services)
    // users table shared across this class's test methods, and UserStore enforces one profile per
    // email - reusing an address another test already claimed under a different random id would
    // fail with "Another profile already claims this email address," a test-isolation collision
    // rather than anything setPassword itself got wrong.
    String email = "ordinary-change@example.com";
    when(authClient.getUser("Bearer session-jwt")).thenReturn(userPayload(email));
    when(authClient.token(eq("password"), argThat(r -> "old-secret".equals(r.password()))))
        .thenReturn(freshSession("verify-access", "verify-refresh", email));
    when(authClient.token(eq("password"), argThat(r -> "new-secret".equals(r.password()))))
        .thenReturn(freshSession("fresh-access", "fresh-refresh", email));

    IdentityService.Session result =
        identityService.setPassword("session-jwt", "old-secret", "new-secret", false);

    verify(authClient).updateUser("Bearer session-jwt", new UserUpdateRequest("new-secret"));
    // Every other session this password could still open must not survive the change - a global
    // revoke, not the local one an ordinary sign-out uses.
    verify(authClient).logout("Bearer session-jwt", "global");
    // The caller's own device is not signed out by its own password change: it gets a fresh
    // session minted with the new password, not the one used only to verify the old one.
    assertEquals("fresh-access", result.accessToken());
    assertEquals("fresh-refresh", result.refreshToken());
  }

  @Test
  void setPassword_ordinaryChange_missingCurrentPassword_isRefusedBeforeAnyChange() {
    when(authClient.getUser("Bearer session-jwt")).thenReturn(userPayload("user@example.com"));

    AuthException thrown =
        assertThrows(
            AuthException.class,
            () -> identityService.setPassword("session-jwt", "  ", "new-secret", false));

    assertEquals("current_password_required", thrown.code());
    assertEquals(400, thrown.status());
    verify(authClient, never()).updateUser(any(), any());
    verify(authClient, never()).logout(any(), any());
  }

  @Test
  void setPassword_ordinaryChange_wrongCurrentPassword_isRefusedBeforeAnyChange() {
    when(authClient.getUser("Bearer session-jwt")).thenReturn(userPayload("user@example.com"));
    doThrow(
            new WebApplicationException(
                Response.status(400)
                    .entity("{\"error_code\":\"invalid_credentials\",\"msg\":\"Invalid login credentials\"}")
                    .type("application/json")
                    .build()))
        .when(authClient)
        .token(eq("password"), argThat(r -> "wrong-secret".equals(r.password())));

    AuthException thrown =
        assertThrows(
            AuthException.class,
            () -> identityService.setPassword("session-jwt", "wrong-secret", "new-secret", false));

    assertEquals("invalid_credentials", thrown.code());
    verify(authClient, never()).updateUser(any(), any());
    verify(authClient, never()).logout(any(), any());
  }

  /**
   * The last step of password recovery cannot supply the current password - not knowing it is the
   * entire reason recovery exists - so {@code recoverySession=true} skips the check {@code
   * AuthResource} would otherwise have derived from the token's own {@code amr} claim.
   */
  @Test
  void setPassword_recoverySession_needsNoCurrentPasswordButStillRevokesAndReissues() {
    String email = "recovery-change@example.com";
    when(authClient.getUser("Bearer recovery-jwt")).thenReturn(userPayload(email));
    when(authClient.token(eq("password"), argThat(r -> "new-secret".equals(r.password()))))
        .thenReturn(freshSession("fresh-access", "fresh-refresh", email));

    IdentityService.Session result =
        identityService.setPassword("recovery-jwt", null, "new-secret", true);

    verify(authClient).updateUser("Bearer recovery-jwt", new UserUpdateRequest("new-secret"));
    verify(authClient).logout("Bearer recovery-jwt", "global");
    // Exactly one password-grant call happened - the re-login that mints the fresh session.
    // Recovery has nothing to verify a current password against, so there must be no second call.
    verify(authClient, times(1)).token(eq("password"), any());
    assertEquals("fresh-access", result.accessToken());
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
  void login_whenSupabaseFails5xx_isReportedAsServiceUnavailableNotWrongPassword() {
    // A Supabase outage must not present as "wrong password" (401): that is what
    // classifySupabaseError's generic 4xx fallback would produce, and it sends a user chasing a
    // credential problem that does not exist. SupabaseAuthClient's @ClientExceptionMapper
    // remaps any 5xx response to SupabaseUnavailableException specifically so it cannot be
    // confused with a rejected request here.
    doThrow(new SupabaseUnavailableException(503)).when(authClient).token(any(), any());

    AuthException thrown =
        assertThrows(AuthException.class, () -> identityService.login("someone@example.com", "secret"));

    assertEquals("service_unavailable", thrown.code());
    assertEquals(503, thrown.status());
  }

  /**
   * F11: real GoTrue error bodies, pinned rather than invented, so a wording change upstream
   * cannot silently degrade the classification the way a substring-only match could.
   * Shape is GoTrue's own since 2024: {@code {"code": <http status>, "error_code": "...",
   * "msg": "..."}}.
   */
  @Test
  void login_classifiesByGoTrueStructuredErrorCode() {
    assertGoTrueBodyClassifiedAs(
        "{\"code\":400,\"error_code\":\"invalid_credentials\",\"msg\":\"Invalid login credentials\"}",
        "invalid_credentials",
        401);
    assertGoTrueBodyClassifiedAs(
        "{\"code\":400,\"error_code\":\"weak_password\",\"msg\":\"Password should be at least 6"
            + " characters.\"}",
        "weak_password",
        400);
    assertGoTrueBodyClassifiedAs(
        "{\"code\":422,\"error_code\":\"user_already_exists\",\"msg\":\"User already"
            + " registered\"}",
        "email_taken",
        409);
    assertGoTrueBodyClassifiedAs(
        "{\"code\":429,\"error_code\":\"over_email_send_rate_limit\",\"msg\":\"Email rate limit"
            + " exceeded\"}",
        "rate_limited",
        429);
  }

  @Test
  void login_withoutStructuredErrorCode_fallsBackToSubstringMatch() {
    // An older GoTrue without the error_code field: the pre-existing substring match must still
    // classify a recognizable message rather than everything collapsing to the generic fallback.
    assertGoTrueBodyClassifiedAs(
        "{\"msg\":\"Password should be at least 6 characters.\"}", "weak_password", 400);
  }

  @Test
  void login_whenNeitherStructuredNorSubstringMatch_getsTheGenericFallback() {
    assertGoTrueBodyClassifiedAs("{\"msg\":\"Something GoTrue has never said before.\"}", "unauthorized", 401);
  }

  private void assertGoTrueBodyClassifiedAs(String body, String expectedCode, int expectedStatus) {
    doThrow(
            new WebApplicationException(
                Response.status(400).entity(body).type("application/json").build()))
        .when(authClient)
        .token(any(), any());

    AuthException thrown =
        assertThrows(
            AuthException.class, () -> identityService.login("someone@example.com", "secret"));

    assertEquals(expectedCode, thrown.code(), body);
    assertEquals(expectedStatus, thrown.status(), body);
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
