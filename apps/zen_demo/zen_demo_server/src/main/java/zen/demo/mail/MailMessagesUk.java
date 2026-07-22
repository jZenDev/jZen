package zen.demo.mail;

import io.quarkus.qute.i18n.Localized;
import io.quarkus.qute.i18n.Message;

/**
 * Ukrainian ({@code uk}) variant of {@link MailMessages}. Quarkus registers it as the localized
 * bundle for {@code uk}; {@link DemoMailer} injects it via {@code @Localized("uk")} and picks it
 * when the recipient's {@code users.language} resolves to {@code uk}.
 */
@Localized("uk")
public interface MailMessagesUk extends MailMessages {

  @Override
  @Message("Ласкаво просимо до jZen")
  String welcomeSubject();

  @Override
  @Message("Ваш обліковий запис jZen буде заархівовано через {days} днів")
  String deletionWarningSubject(int days);

  @Override
  @Message("Останній шанс - ваш обліковий запис jZen буде видалено через {days} днів")
  String finalWarningSubject(int days);
}
