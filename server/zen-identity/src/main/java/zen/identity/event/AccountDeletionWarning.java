package zen.identity.event;

import java.util.UUID;

/**
 * Fired once per stage per account when the data-retention cycle finds a warning due. Applications
 * observe it with {@code @Observes}, send the wording they choose, and confirm the {@link #receipt}
 * when the message actually went out; the framework decides only <em>whether</em> and <em>when</em>
 * a warning is due (see {@link zen.identity.user.UserRetentionService}).
 *
 * <p><strong>The timestamp is stamped after this event, not before it</strong> (ROADMAP step 7a,
 * DECISIONS ADR-008). The cycle finds the account, fires this, and writes
 * {@code deletion_warning_sent_at} only if the receipt came back confirmed. So an account is never
 * moved closer to anonymisation by a warning that failed to send, and an application that observes
 * nothing at all can never have its users erased. The previous order - stamp, then fire
 * asynchronously and hope - is what made that possible.
 *
 * <p>Observation is <strong>synchronous</strong>, unlike {@link UserRegistered}. There is no user
 * waiting on the other end of a retention cycle, so the latency argument that made registration
 * mail asynchronous does not apply, and only a synchronous fire can carry an answer back within the
 * cycle that asked the question.
 *
 * @param userId the account being warned
 * @param email the address to warn
 * @param language the profile's language tag, used to localize the message
 * @param stage which of the two warnings this is
 * @param daysUntilAnonymisation days remaining before the account is anonymised, derived from the
 *     configured retention offsets so the wording and the schedule cannot drift apart
 * @param receipt the acknowledgement an observer confirms once the message has been sent
 */
public record AccountDeletionWarning(
    UUID userId,
    String email,
    String language,
    Stage stage,
    int daysUntilAnonymisation,
    DeliveryReceipt receipt) {

  /** The two points in the retention cycle at which a user is told their account is at risk. */
  public enum Stage {
    /** The first notice, sent after the inactivity window elapses. */
    FIRST,
    /** The last notice, sent shortly before the account is anonymised. */
    FINAL
  }
}
