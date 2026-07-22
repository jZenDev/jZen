package zen.identity.event;

import java.util.UUID;

/**
 * Fired asynchronously, once per stage per account, after the data-retention cycle has committed
 * the matching warning timestamp on the {@code users} row. Applications observe it with
 * {@code @ObservesAsync} and send the wording they choose; the framework decides only
 * <em>whether</em> and <em>when</em> a warning is due (see
 * {@link zen.identity.user.UserRetentionService}).
 *
 * <p>The stamp is committed before the event is fired, so a warning is never mailed for a row that
 * was not recorded as warned - the failure mode that would spam a user on every cycle.
 *
 * @param userId the account being warned
 * @param email the address to warn
 * @param language the profile's language tag, used to localize the message
 * @param stage which of the two warnings this is
 * @param daysUntilAnonymisation days remaining before the account is anonymised, derived from the
 *     configured retention offsets so the wording and the schedule cannot drift apart
 */
public record AccountDeletionWarning(
    UUID userId, String email, String language, Stage stage, int daysUntilAnonymisation) {

  /** The two points in the retention cycle at which a user is told their account is at risk. */
  public enum Stage {
    /** The first notice, sent after the inactivity window elapses. */
    FIRST,
    /** The last notice, sent shortly before the account is anonymised. */
    FINAL
  }
}
