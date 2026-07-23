package zen.demo.mail;

import io.quarkus.qute.i18n.Localized;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.event.ObservesAsync;
import jakarta.inject.Inject;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import zen.core.i18n.ZenLocales;
import zen.email.EmailService;
import zen.email.LocalizedEmail;
import zen.identity.event.AccountDeletionWarning;
import zen.identity.event.UserRegistered;

/**
 * The reference app's half of the email story: it observes the framework's identity events and
 * turns each into a localized message built from this application's own subjects
 * ({@link MailMessages}) and templates ({@code templates/mail/}).
 *
 * <p>This is what ADR-007 splits. {@code zen-identity} decides that a user registered or that an
 * account is due a retention warning; {@code zen-email} knows how to render and send in a locale;
 * neither knows what jZen says or how it looks. A second application observing the same events
 * with its own wording needs no framework change.
 *
 * <p>The two observers differ deliberately. {@link UserRegistered} is {@code @ObservesAsync}: it
 * runs on a worker thread after the triggering transaction has committed, so registration neither
 * waits for SMTP nor can be failed by it. {@link AccountDeletionWarning} is <em>synchronous</em>,
 * because the retention cycle needs the answer: it stamps the account only if this observer
 * confirms the warning was delivered, and an account that was not warned is not moved closer to
 * erasure (ADR-008). There is no user waiting on a retention cycle, so nothing is paid for that.
 * {@link EmailService#send} never throws either way.
 */
@ApplicationScoped
public class DemoMailer {

  /** Locale-free template bases; {@link EmailService} appends {@code _<locale>}. */
  static final String WELCOME_TEMPLATE = "welcome";

  static final String DELETION_WARNING_TEMPLATE = "deletion_warning";
  static final String FINAL_WARNING_TEMPLATE = "final_warning";

  private final EmailService emailService;
  private final MailMessages messages;
  private final MailMessages messagesUk;
  private final String siteUrl;

  @Inject
  public DemoMailer(
      EmailService emailService,
      MailMessages messages,
      @Localized("uk") MailMessages messagesUk,
      @ConfigProperty(name = "site.url") String siteUrl) {
    this.emailService = emailService;
    this.messages = messages;
    this.messagesUk = messagesUk;
    this.siteUrl = siteUrl;
  }

  /** Greets a newly registered user in the language their registration request arrived in. */
  void onUserRegistered(@ObservesAsync UserRegistered event) {
    emailService.send(
        new LocalizedEmail(
            event.email(),
            event.language(),
            WELCOME_TEMPLATE,
            bundle(event.language()).welcomeSubject(),
            Map.of("email", event.email(), "siteUrl", siteUrl)));
  }

  /**
   * Tells a dormant account's owner how long they have left, in their own language, and confirms
   * the receipt when the message actually went out. Withholding that confirmation is what stops an
   * unwarned account from being anonymised, so the confirmation is bound to the send's own return
   * value and nothing else.
   */
  void onAccountDeletionWarning(@Observes AccountDeletionWarning event) {
    int days = event.daysUntilAnonymisation();
    MailMessages bundle = bundle(event.language());
    boolean isFinal = event.stage() == AccountDeletionWarning.Stage.FINAL;
    boolean sent =
        emailService.send(
            new LocalizedEmail(
                event.email(),
                event.language(),
                isFinal ? FINAL_WARNING_TEMPLATE : DELETION_WARNING_TEMPLATE,
                isFinal ? bundle.finalWarningSubject(days) : bundle.deletionWarningSubject(days),
                Map.of("email", event.email(), "siteUrl", siteUrl, "days", days)));
    if (sent) {
      event.receipt().confirm();
    }
  }

  /**
   * Selects the subject bundle for a stored language tag. It resolves through the same
   * {@link ZenLocales} the {@link EmailService} uses for the template, so a subject can never end
   * up in a different language from the body it heads.
   */
  private MailMessages bundle(String language) {
    return ZenLocales.UK.equals(ZenLocales.resolve(language)) ? messagesUk : messages;
  }
}
