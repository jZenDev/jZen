package zen.jobs;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * The trigger's credential check, proven without a server. The endpoint that uses it is reachable
 * from the internet ({@code --allow-unauthenticated}) and its first job erases personal data, so
 * the interesting cases are all the ways a call must be refused.
 *
 * <p>{@code JobTriggerResourceTest} covers the same rules over real HTTP; these fix the decision
 * itself, including the one an HTTP test cannot easily reach: what happens when the deployment
 * forgot to configure a secret at all.
 */
class JobTriggerAuthenticatorTest {

  private static final String SECRET = "s3cret-trigger-token";

  @Test
  void anUnconfiguredSecretRejectsEverything() {
    JobTriggerAuthenticator unconfigured = new JobTriggerAuthenticator(Optional.empty());

    assertFalse(unconfigured.isAuthorized(SECRET), "no configured secret means no valid token");
    assertFalse(unconfigured.isAuthorized(""), "an empty presented token is not a match either");
    assertFalse(unconfigured.isAuthorized(null), "and neither is an absent header");
  }

  @Test
  void aBlankConfiguredSecretRejectsEverything() {
    JobTriggerAuthenticator blank = new JobTriggerAuthenticator(Optional.of("   "));

    assertFalse(
        blank.isAuthorized("   "),
        "a blank secret is treated as unconfigured, so it can never be satisfied by matching it");
  }

  @Test
  void theConfiguredSecretIsAccepted() {
    assertTrue(new JobTriggerAuthenticator(Optional.of(SECRET)).isAuthorized(SECRET));
  }

  @Test
  void anythingOtherThanTheConfiguredSecretIsRejected() {
    JobTriggerAuthenticator authenticator = new JobTriggerAuthenticator(Optional.of(SECRET));

    assertFalse(authenticator.isAuthorized(null), "absent header");
    assertFalse(authenticator.isAuthorized(""), "empty header");
    assertFalse(authenticator.isAuthorized(SECRET + "x"), "a prefix of the secret is not the secret");
    assertFalse(authenticator.isAuthorized(SECRET.toUpperCase()), "comparison is case sensitive");
  }
}
