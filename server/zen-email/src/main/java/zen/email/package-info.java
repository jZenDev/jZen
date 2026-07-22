/**
 * jZen email (Java): localized transactional mail over {@code quarkus-mailer} (ROADMAP step 6).
 *
 * <p>{@link zen.email.EmailService} is the whole public surface: hand it a
 * {@link zen.email.LocalizedEmail} and it resolves the recipient's locale, renders the matching
 * per-locale Qute template, and sends - without ever throwing at the caller. The module is
 * deliberately content-free; wording and branding belong to the application (DECISIONS ADR-007).
 */
package zen.email;
