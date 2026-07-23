package zen.identity.event;

/**
 * The acknowledgement an observer hands back to say a message really went out.
 *
 * <p>It exists to close a hole ADR-007 knowingly accepted. {@code EmailService.send} is deliberately
 * non-fatal - it returns {@code false} and logs rather than throwing, because mail must never fail
 * the business action that triggered it - so a broken relay used to leave the retention timestamps
 * advancing regardless, and accounts whose owners were never actually warned were anonymised on
 * schedule. Warning someone is the entire legal basis for erasing their data, so an unsent warning
 * must stop the clock, not merely be logged.
 *
 * <p>The receipt is how that outcome travels back without re-coupling the modules. {@code
 * zen-identity} still fires an event and still knows nothing about {@code zen-email}: it learns only
 * that <em>something</em> confirmed delivery, and applications remain free to warn users by any
 * channel they like. An observer that never confirms simply leaves the account un-stamped, so the
 * failure mode is a retry on the next cycle rather than a silent erasure - the safe direction.
 *
 * <p>Mutable by design, and read only after the synchronous fire has returned.
 */
public final class DeliveryReceipt {

  private boolean confirmed;

  /** Called by an observer once the message has actually been handed to its transport. */
  public void confirm() {
    confirmed = true;
  }

  /** Whether any observer confirmed delivery. */
  public boolean isConfirmed() {
    return confirmed;
  }
}
