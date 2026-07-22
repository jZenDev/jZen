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
 * @param to recipient address
 * @param language the recipient's raw language tag, normally the {@code users.language} column;
 *     null, blank, or unsupported values fall back to the default locale
 * @param template the locale-free template base name under {@code templates/mail/}
 * @param subject the subject line, already localized by the caller
 * @param data values bound into the template; defensively copied, never null
 */
public record LocalizedEmail(
    String to, String language, String template, String subject, Map<String, Object> data) {

  public LocalizedEmail {
    Objects.requireNonNull(to, "to");
    Objects.requireNonNull(template, "template");
    Objects.requireNonNull(subject, "subject");
    data = data == null ? Map.of() : Map.copyOf(data);
  }

  /** A message whose template binds no data. */
  public static LocalizedEmail of(String to, String language, String template, String subject) {
    return new LocalizedEmail(to, language, template, subject, Map.of());
  }
}
