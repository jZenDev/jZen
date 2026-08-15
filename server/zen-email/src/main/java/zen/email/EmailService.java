package zen.email;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.quarkus.qute.Engine;
import io.quarkus.qute.Template;
import io.quarkus.qute.TemplateInstance;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;
import zen.core.i18n.ZenLocales;

/**
 * Sends localized transactional email. An inline {@code io.quarkus.mailer.Mailer} call with a
 * hardcoded English subject cannot be localized, which is the limitation this service exists to
 * prevent.
 *
 * <p>This is the framework <em>mechanism</em> only. It owns locale resolution, template selection,
 * rendering, and the guarantee that sending never breaks the caller. It owns no wording and no
 * branding: applications supply the subject (from their typed Qute {@code @MessageBundle}) and the
 * per-locale templates under {@code src/main/resources/templates/mail/}, exactly as an application
 * supplies the component schemas the framework's REST resources reference. See DECISIONS
 * ADR-007.
 *
 * <p>The provider is irrelevant here: {@code quarkus-mailer} speaks plain SMTP, so Brevo is only a
 * value of {@code SMTP_HOST}. Nothing in this class is provider-specific. In dev and test
 * {@code quarkus.mailer.mock=true} means nothing leaves the process, and {@code MockMailbox}
 * captures what would have been sent.
 */
@ApplicationScoped
public class EmailService {

  private static final Logger LOG = Logger.getLogger(EmailService.class);

  /** Template directory, relative to {@code src/main/resources/templates/}. */
  private static final String TEMPLATE_ROOT = "mail/";

  /** Separates a template's base name from its locale: {@code welcome} + {@code _} + {@code uk}. */
  private static final String LOCALE_SEPARATOR = "_";

  /** Stands in for the local part of an address in a log line. See {@link #recipient}. */
  private static final String MASK = "***";

  private final Mailer mailer;
  private final Engine engine;

  /**
   * The languages <em>this application</em> supports, as language tags (ADR-044); jZen's own
   * inventory when unconfigured. The templates are the application's, so the set that decides
   * which {@code <template>_<locale>.html} is asked for must be the application's too - resolving
   * against the framework's would refuse to render a template the application actually ships.
   */
  @Inject
  @ConfigProperty(name = "zen.i18n.supported")
  Optional<List<String>> supportedLocales;

  @Inject
  public EmailService(Mailer mailer, Engine engine) {
    this.mailer = mailer;
    this.engine = engine;
  }

  /**
   * Renders {@code templates/mail/<template>_<locale>.html} for the recipient's locale and sends
   * it as an HTML message.
   *
   * <p><strong>Never throws.</strong> A missing template, a rendering error, or an SMTP failure is
   * logged and reported through the return value. Email is a side effect of a business action, so
   * a mail problem must never roll back or fail the action that triggered it - registration
   * succeeds whether or not the welcome message goes out.
   *
   * @return {@code true} when the message was handed to the mailer, {@code false} when it was not
   */
  public boolean send(LocalizedEmail email) {
    // An empty value counts as unconfigured: the deploy passes the variable through blank when
    // the operator sets nothing, and an empty set would send every message in English.
    List<String> supported = supportedLocales.filter(set -> !set.isEmpty()).orElse(ZenLocales.SHIPPED);
    String locale = ZenLocales.resolve(email.language(), supported);
    String templateName = TEMPLATE_ROOT + email.template() + LOCALE_SEPARATOR + locale;
    try {
      Template template = engine.getTemplate(templateName);
      if (template == null) {
        LOG.errorf(
            "No mail template '%s' for recipient locale '%s'; message not sent", templateName, locale);
        return false;
      }
      mailer.send(Mail.withHtml(email.to(), email.subject(), render(template, email.data())));
      LOG.debugf("Sent '%s' mail to %s in locale '%s'", email.template(), recipient(email), locale);
      return true;
    } catch (RuntimeException e) {
      LOG.warnf("Failed to send '%s' mail to %s: %s", templateName, recipient(email), e.toString());
      return false;
    }
  }

  /**
   * How a recipient is named in a log line — never by their address.
   *
   * <p>An email address is personal data, and a log line is not a private place: in production
   * these go to Cloud Logging, which has its own retention and its own access list. So the caller's
   * {@code recipientRef} (normally the user id) is preferred, and when there is none the local part
   * is masked and only the domain survives. The domain is what actually diagnoses a send failure —
   * a refusing MX, an unroutable vanity domain, a typo'd TLD — while the local part is the half
   * that identifies a person, and it is the half that is dropped.
   */
  private static String recipient(LocalizedEmail email) {
    if (email.recipientRef() != null && !email.recipientRef().isBlank()) {
      return email.recipientRef();
    }
    String address = email.to();
    int at = address.lastIndexOf('@');
    return at < 0 ? MASK : MASK + address.substring(at);
  }

  private String render(Template template, Map<String, Object> data) {
    TemplateInstance instance = template.instance();
    data.forEach(instance::data);
    return instance.render();
  }
}
