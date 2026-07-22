package zen.email;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.quarkus.qute.Engine;
import io.quarkus.qute.Template;
import io.quarkus.qute.TemplateInstance;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.Map;
import org.jboss.logging.Logger;
import zen.core.i18n.ZenLocales;

/**
 * Sends localized transactional email. New code, not a port: nothing in the donor backend
 * abstracted mail (its one sender injected {@code io.quarkus.mailer.Mailer} inline and hardcoded
 * English subjects), and that limitation is not carried forward -
 * ../BugEater/bugeater-quarkus/src/main/java/jlogicsoftware/user/UserCleanupService.java:28.
 *
 * <p>This is the framework <em>mechanism</em> only. It owns locale resolution, template selection,
 * rendering, and the guarantee that sending never breaks the caller. It owns no wording and no
 * branding: applications supply the subject (from their typed Qute {@code @MessageBundle}) and the
 * per-locale templates under {@code src/main/resources/templates/mail/}, exactly as an application
 * supplies the component schemas the framework's REST resources reference (TA-1). See DECISIONS
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

  private final Mailer mailer;
  private final Engine engine;

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
    String locale = ZenLocales.resolve(email.language());
    String templateName = TEMPLATE_ROOT + email.template() + LOCALE_SEPARATOR + locale;
    try {
      Template template = engine.getTemplate(templateName);
      if (template == null) {
        LOG.errorf(
            "No mail template '%s' for recipient locale '%s'; message not sent", templateName, locale);
        return false;
      }
      mailer.send(Mail.withHtml(email.to(), email.subject(), render(template, email.data())));
      LOG.debugf("Sent '%s' mail to %s in locale '%s'", email.template(), email.to(), locale);
      return true;
    } catch (RuntimeException e) {
      LOG.warnf("Failed to send '%s' mail to %s: %s", templateName, email.to(), e.toString());
      return false;
    }
  }

  private String render(Template template, Map<String, Object> data) {
    TemplateInstance instance = template.instance();
    data.forEach(instance::data);
    return instance.render();
  }
}
