package zen.email;

import java.util.Map;
import java.util.Objects;

/**
 * One localized message handed to {@link EmailService}: who it goes to, in which language, which
 * template family renders it, the already-localized subject, and the data the template binds.
 *
 * <p>The split is deliberate. The <em>subject</em> arrives localized because it comes from the
 * caller's typed Qute {@code @MessageBundle} (DECISIONS ADR-002) - the framework has no business
 * owning an application's wording. The <em>body</em> is named by a locale-free {@code template}
 * base (e.g. {@code "welcome"}); {@link EmailService} appends the resolved locale and looks up
 * {@code templates/mail/welcome_<locale>.html}. Both sides therefore resolve the same
 * {@code language} through {@code ZenLocales}, so subject and body can never disagree.
 *
 * <p>{@code recipientRef} exists so that {@link EmailService} can say <em>who</em> a failed send was
 * for without writing an email address into the log. An address is personal data the moment it
 * reaches a log sink, and in production that sink is Cloud Logging with its own retention — so the
 * caller, which is the layer that actually knows the user's id, hands down a non-identifying
 * reference instead. It is nullable because a message need not correspond to an account at all;
 * when it is absent {@link EmailService} logs the domain and masks the local part, which still
 * diagnoses a deliverability problem without naming a person.
 *
 * @param to recipient address
 * @param language the recipient's raw language tag, normally the {@code users.language} column;
 *     null, blank, or unsupported values fall back to the default locale
 * @param template the locale-free template base name under {@code templates/mail/}
 * @param subject the subject line, already localized by the caller
 * @param data values bound into the template; defensively copied, never null
 * @param recipientRef an opaque, non-personal identifier for logs — normally the user id; may be
 *     null for a message that belongs to no account
 */
public record LocalizedEmail(
    String to,
    String language,
    String template,
    String subject,
    Map<String, Object> data,
    String recipientRef) {

  public LocalizedEmail {
    Objects.requireNonNull(to, "to");
    Objects.requireNonNull(template, "template");
    Objects.requireNonNull(subject, "subject");
    data = data == null ? Map.of() : Map.copyOf(data);
  }

  /** A message whose template binds no data and belongs to no account. */
  public static LocalizedEmail of(String to, String language, String template, String subject) {
    return new LocalizedEmail(to, language, template, subject, Map.of(), null);
  }
}
