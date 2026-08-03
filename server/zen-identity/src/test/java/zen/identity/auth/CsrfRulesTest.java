package zen.identity.auth;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

/**
 * The exemption list, asserted route by route.
 *
 * <p>A plain unit test in the library rather than a {@code @QuarkusTest}, for the reason
 * {@code RedirectTargetsTest} and {@code ClientAddressTest} are: an assembled application only ever
 * presents the configuration that works, and every case here is one where getting it wrong is a
 * production outage rather than a red suite — a scheduler that can no longer run retention, or a
 * login form that refuses everyone who has visited before.
 */
class CsrfRulesTest {

  @Test
  void aMutatingApiCallIsInScope() {
    assertTrue(CsrfRules.applies("POST", "/api/v1/auth/logout"));
    assertTrue(CsrfRules.applies("POST", "/api/v1/auth/password"));
    assertTrue(CsrfRules.applies("PUT", "/api/v1/admin/users/abc"));
    assertTrue(CsrfRules.applies("DELETE", "/api/v1/admin/users/abc"));
    assertTrue(CsrfRules.applies("PATCH", "/api/v1/anything"));
  }

  @Test
  void safeMethodsAreNeverInScope() {
    // A read cannot be forged into a change, and asking a GET for a token would mean every page
    // load needed one.
    assertFalse(CsrfRules.applies("GET", "/api/v1/auth/identity"));
    assertFalse(CsrfRules.applies("HEAD", "/api/v1/admin/users"));
    // The browser sends the preflight itself and attaches no header of ours to it.
    assertFalse(CsrfRules.applies("OPTIONS", "/api/v1/admin/users"));
  }

  @Test
  void aVerbNobodyAnticipatedIsProtectedRatherThanExempt() {
    // The list names the safe methods, not the unsafe ones, so the default for anything new is
    // "checked". The opposite arrangement fails open the first time someone adds a verb.
    assertTrue(CsrfRules.applies("PROPPATCH", "/api/v1/anything"));
  }

  @Test
  void theCredentialEndpointsThatRunBeforeASessionExistsAreExempt() {
    // Circular otherwise: these are how a caller obtains the token in the first place. And a
    // returning visitor may still hold a stale one, so enforcing here would break signing in for
    // precisely the people who have been here before.
    assertFalse(CsrfRules.applies("POST", "/api/v1/auth/login"));
    assertFalse(CsrfRules.applies("POST", "/api/v1/auth/register"));
    assertFalse(CsrfRules.applies("POST", "/api/v1/auth/restore-password"));
    assertFalse(CsrfRules.applies("POST", "/api/v1/auth/session"));
  }

  @Test
  void refreshIsExemptBecauseTheTokenItWouldNeedHasAlreadyExpired() {
    // The CSRF cookie's lifetime is the access token's; refresh is the endpoint a client calls
    // after that hour is up. Enforcing here would end every session at the access-token TTL
    // instead of at seven days, on every client, with no error a user could act on.
    assertFalse(CsrfRules.applies("POST", "/api/v1/auth/refresh"));
  }

  @Test
  void theJobTriggerIsExemptBecauseItsCallerIsAMachine() {
    // Cloud Scheduler has no cookie jar and no CSRF token. Enforcing here breaks scheduled
    // retention in production and the end-to-end gate with it; the endpoint's credential is its
    // own shared secret, which a browser cannot be made to send.
    assertFalse(CsrfRules.applies("POST", "/api/v1/jobs/trigger"));
  }

  @Test
  void everythingOutsideTheApiPrefixIsIgnored() {
    // The static handler serves the app bundle and the admin panel; neither changes state.
    assertFalse(CsrfRules.applies("POST", "/auth/callback"));
    assertFalse(CsrfRules.applies("POST", "/"));
    assertFalse(CsrfRules.applies("POST", "/.well-known/assetlinks.json"));
  }

  @Test
  void pathsAgreeWithOrWithoutTheirSlashes() {
    // UriInfo.getPath() differs between runtimes on the leading slash, so an exemption that only
    // matched one spelling would silently start enforcing on the trigger.
    for (String spelling :
        new String[] {"api/v1/jobs/trigger", "/api/v1/jobs/trigger", "/api/v1/jobs/trigger/"}) {
      assertFalse(CsrfRules.applies("POST", spelling), spelling + " must stay exempt");
    }
  }

  @Test
  void aNearMissOnAnExemptPathIsStillEnforced() {
    // Exact match only, like RedirectTargets: a prefix or suffix rule here would let an attacker
    // pick their own exemption by appending to a path that resolves to something else.
    assertTrue(CsrfRules.applies("POST", "/api/v1/auth/login/extra"));
    assertTrue(CsrfRules.applies("POST", "/api/v1/jobs/trigger-now"));
  }
}
