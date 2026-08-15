package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import zen.identity.user.User;
import zen.identity.user.UserStore;

/**
 * A blank {@code zen.i18n.supported} means "unconfigured", not "no languages at all".
 *
 * <p>This is the production shape, not an edge case: {@code deploy:cloudrun} passes the variable
 * through unconditionally as {@code ZEN_I18N_SUPPORTED=${ZEN_I18N_SUPPORTED:-}}, because
 * {@code --set-env-vars} replaces the whole environment and a variable left out is a variable
 * removed. So the common deployment has the variable *present and empty*. Read literally, that is
 * an empty supported set - every user resolves to English, on a service that looks correctly
 * configured. The test exists because the failure is invisible: nothing throws, nothing logs, and
 * the only symptom is that Ukrainian users start receiving English mail.
 */
@QuarkusTest
@TestProfile(BlankLocaleSetTest.BlankSetting.class)
class BlankLocaleSetTest {

  /** The variable present and empty - what an unset export produces at deploy time. */
  public static class BlankSetting implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("zen.i18n.supported", "");
    }
  }

  @Inject UserStore userStore;

  @Test
  void blankFallsBackToWhatJZenShips() {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () ->
                userStore.upsertOnLogin(
                    new UserPayload(id.toString(), "blank-" + id + "@example.test", null, null, null),
                    "uk-UA"));

    User stored = QuarkusTransaction.requiringNew().call(() -> User.findById(id));
    assertEquals("uk", stored.language, "a blank setting must not collapse the supported set");
  }
}
