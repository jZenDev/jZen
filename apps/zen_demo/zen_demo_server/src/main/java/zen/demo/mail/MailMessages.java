package zen.demo.mail;

import io.quarkus.qute.i18n.Message;
import io.quarkus.qute.i18n.MessageBundle;

/**
 * The reference app's email subject lines as a typed Qute {@code @MessageBundle} (DECISIONS
 * ADR-002), the same mechanism {@link zen.demo.DemoMessages} uses for the REST surface. The
 * default bundle is English; {@link MailMessagesUk} supplies the Ukrainian variant.
 *
 * <p>Named {@code mail} because a bundle name must be unique in an application and
 * {@code DemoMessages} already holds the default name.
 *
 * <p>Subjects live here, in the application, rather than in {@code zen-email}: the framework owns
 * the sending mechanism, the application owns every word a user reads (ADR-007). The message
 * bodies are the matching per-locale templates under {@code templates/mail/}.
 */
@MessageBundle("mail")
public interface MailMessages {

  /** Subject of the message greeting a newly registered user. */
  @Message("Welcome to jZen")
  String welcomeSubject();

  /** Subject of the first data-retention notice. */
  @Message("Your jZen account will be archived in {days} days")
  String deletionWarningSubject(int days);

  /** Subject of the last data-retention notice before the account is anonymised. */
  @Message("Last chance - your jZen account is deleted in {days} days")
  String finalWarningSubject(int days);
}
