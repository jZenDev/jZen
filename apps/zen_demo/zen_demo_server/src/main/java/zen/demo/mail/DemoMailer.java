package zen.demo.mail;

import io.quarkus.qute.i18n.Localized;
import jakarta.enterprise.context.ApplicationScoped;
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
 * <p>Both observers are {@code @ObservesAsync}, so they run on a worker thread after the
 * triggering transaction has committed. Registration therefore neither waits for SMTP nor can be
 * failed by it, and {@link EmailService#send} never throws in the first place.
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

  /** Tells a dormant account's owner how long they have left, in their own language. */
  void onAccountDeletionWarning(@ObservesAsync AccountDeletionWarning event) {
    int days = event.daysUntilAnonymisation();
    MailMessages bundle = bundle(event.language());
    boolean isFinal = event.stage() == AccountDeletionWarning.Stage.FINAL;
    emailService.send(
        new LocalizedEmail(
            event.email(),
            event.language(),
            isFinal ? FINAL_WARNING_TEMPLATE : DELETION_WARNING_TEMPLATE,
            isFinal ? bundle.finalWarningSubject(days) : bundle.deletionWarningSubject(days),
            Map.of("email", event.email(), "siteUrl", siteUrl, "days", days)));
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
