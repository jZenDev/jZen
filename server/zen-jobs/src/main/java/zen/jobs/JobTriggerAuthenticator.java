package zen.jobs;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Guards the job trigger with a shared secret.
 *
 * <p><strong>Why a secret and not the ambient session.</strong> Cloud Run serves jZen with
 * {@code --allow-unauthenticated} (Taskfile {@code deploy:cloudrun}), so this endpoint is reachable
 * from the internet and cannot lean on platform IAM. The obvious alternative - verifying the Google
 * OIDC token Cloud Scheduler can attach - collides with the way jZen already reads credentials:
 * {@code mp.jwt.token.header=Cookie} points SmallRye JWT at the Supabase session cookie, so a
 * bearer token in {@code Authorization} is never even parsed, and a second issuer would mean
 * hand-wiring a second parser plus a live JWKS fetch that no hermetic test could satisfy. A header
 * secret is one configuration property, is what Cloud Scheduler sends natively, and is testable
 * without GCP. See DECISIONS ADR-008.
 *
 * <p><strong>Fails closed.</strong> The property is deliberately absent from this library's
 * defaults, so an application that has not configured a secret rejects every trigger rather than
 * accepting every trigger. A jobs endpoint that opens itself by omission would be a data-destroying
 * default, since retention is what it drives.
 */
@ApplicationScoped
public class JobTriggerAuthenticator {

  private static final Logger LOG = Logger.getLogger(JobTriggerAuthenticator.class);

  /** The header Cloud Scheduler is configured to send. Constant, not config: it is wire contract. */
  public static final String TOKEN_HEADER = "X-Zen-Job-Token";

  private final Optional<String> configuredToken;

  @Inject
  public JobTriggerAuthenticator(
      @ConfigProperty(name = "zen.jobs.trigger.token") Optional<String> configuredToken) {
    this.configuredToken = configuredToken;
  }

  /**
   * Compares a presented token against the configured secret in constant time, so a caller cannot
   * recover the secret one byte at a time from response latency.
   *
   * @param presented the value of {@link #TOKEN_HEADER}, or {@code null} when absent
   * @return {@code true} only when a secret is configured and the presented value matches it
   */
  public boolean isAuthorized(String presented) {
    String expected = configuredToken.filter(token -> !token.isBlank()).orElse(null);
    if (expected == null) {
      LOG.warn(
          "Job trigger called but zen.jobs.trigger.token is not configured; rejecting. Set the"
              + " secret to enable scheduled work.");
      return false;
    }
    if (presented == null) {
      return false;
    }
    return MessageDigest.isEqual(
        presented.getBytes(StandardCharsets.UTF_8), expected.getBytes(StandardCharsets.UTF_8));
  }
}
