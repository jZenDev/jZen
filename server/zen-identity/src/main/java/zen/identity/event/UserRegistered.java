package zen.identity.event;

import java.util.UUID;

/**
 * Fired once, asynchronously, after a new local profile row has been committed for a freshly
 * registered identity. Applications observe it with {@code @ObservesAsync} to react - the
 * reference app sends a localized welcome message.
 *
 * <p>Why an event rather than a direct call: the framework knows <em>that</em> a user registered;
 * only the application knows what should happen next and in whose words. Firing an event keeps
 * {@code zen-identity} free of any dependency on {@code zen-email} and leaves the reaction
 * optional - an application that wants no welcome message simply observes nothing (DECISIONS
 * ADR-007).
 *
 * <p>The payload is a detached copy, never the managed {@link zen.identity.user.User} entity: the
 * observer runs on another thread with no persistence context, so handing it a managed entity
 * would be a lazy-loading trap.
 *
 * @param userId the Supabase identity id, also the {@code users} primary key
 * @param email the address that registered
 * @param language the profile's language tag, resolved when the row was created
 */
public record UserRegistered(UUID userId, String email, String language) {}
