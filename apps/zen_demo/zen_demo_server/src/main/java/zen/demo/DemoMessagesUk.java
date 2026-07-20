package zen.demo;

import io.quarkus.qute.i18n.Localized;
import io.quarkus.qute.i18n.Message;

/**
 * Ukrainian ({@code uk}) variant of {@link DemoMessages}. Quarkus registers it as the localized
 * bundle for {@code uk}; {@link DemoResource} injects it via {@code @Localized("uk")}.
 */
@Localized("uk")
public interface DemoMessagesUk extends DemoMessages {

  @Override
  @Message("Сервер працює")
  String pingMessage();
}
