package zen.demo;

import io.quarkus.qute.i18n.Message;
import io.quarkus.qute.i18n.MessageBundle;

/**
 * The demo's server-side messages as a typed Qute {@code @MessageBundle} (the Quarkus-idiomatic
 * i18n mechanism), replacing the hand-rolled {@code .properties} lookup. The default bundle is
 * English; {@link DemoMessagesUk} supplies the Ukrainian ({@code uk}) variant. {@link DemoResource}
 * injects both and selects one per request from {@code Accept-Language}
 * (via {@link zen.core.i18n.AcceptLanguage}).
 *
 * <p>This mirrors what ROADMAP step 6 will use for localized email (a {@code @MessageBundle} keyed
 * off {@code users.language}); the bundle mechanism is shared, only the locale source differs.
 */
@MessageBundle
public interface DemoMessages {

  /** The localized "server is alive" message returned by GET /api/v1/demo/ping. */
  @Message("Server is alive")
  String pingMessage();
}
