package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.junit.QuarkusTestProfile;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import zen.identity.user.User;
import zen.identity.user.UserStore;

/**
 * The supported locale set belongs to the application, and the framework must not clamp a stored
 * preference back to its own inventory (ADR-044).
 *
 * <p>This is the server half of the second application's first framework defect. jZen ships
 * {@code {en, uk}}; an application shipping Polish sets {@code zen.i18n.supported} and every
 * Polish user's {@code users.language} must hold {@code pl}. Before this, {@code UserStore}
 * resolved against the framework's own set, so the column was written {@code en} — and because
 * that column is the sole locale source for email, every later message to that user went out in
 * the wrong language. Nothing failed; the data was just quietly wrong, which is why this is
 * asserted against the database rather than read off the config.
 */
@QuarkusTest
@TestProfile(ApplicationLocaleSetTest.PolishSpeakingApp.class)
class ApplicationLocaleSetTest {

  /** An application that supports a language jZen ships no strings for. */
  public static class PolishSpeakingApp implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of("zen.i18n.supported", "en,uk,pl");
    }
  }

  @Inject UserStore userStore;

  private static UserPayload payload(UUID id) {
    return new UserPayload(id.toString(), "locale-" + id + "@example.test", null, null, null);
  }

  @Test
  void keepsALocaleTheFrameworkDoesNotShip() {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew().run(() -> userStore.upsertOnLogin(payload(id), "pl-PL"));

    User stored = QuarkusTransaction.requiringNew().call(() -> User.findById(id));
    assertEquals("pl", stored.language, "an application's locale must survive registration");
  }

  @Test
  void stillFallsBackForALocaleNobodySupports() {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew().run(() -> userStore.upsertOnLogin(payload(id), "de"));

    User stored = QuarkusTransaction.requiringNew().call(() -> User.findById(id));
    assertEquals("en", stored.language, "the set is wider, not open");
  }
}
