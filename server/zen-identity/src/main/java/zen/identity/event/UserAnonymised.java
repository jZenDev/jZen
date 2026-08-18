package zen.identity.event;

import java.util.UUID;

/**
 * Fired once per row, synchronously, from inside the same transaction that anonymises it (see
 * {@link zen.identity.user.UserRetentionService#anonymiseExpiredAccounts()}). Applications observe
 * it with {@code @Observes} and cascade their own cleanup of anything keyed on {@code userId} - the
 * framework knows only that the identity was anonymised; only the application knows what else in
 * its own tables should go with it (DECISIONS ADR-007).
 *
 * <p>The fire happens before the anonymising transaction commits, not after, so an observer's
 * cascade is part of the same unit of work: if the cascade throws, the anonymisation it was
 * reacting to rolls back with it rather than leaving the identity anonymised and the application's
 * own data orphaned. An application that observes nothing loses nothing it did not already have -
 * the row is anonymised exactly as it would have been with no observers at all.
 *
 * <p>Mirrors {@link UserRegistered}'s shape for the opposite event in the account's lifecycle.
 *
 * @param userId the account that was anonymised
 */
public record UserAnonymised(UUID userId) {}
