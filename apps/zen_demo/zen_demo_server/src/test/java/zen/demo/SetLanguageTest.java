package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.mailer.Mail;
import io.quarkus.mailer.MockMailbox;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.email.EmailService;
import zen.email.LocalizedEmail;
import zen.identity.auth.SessionService;
import zen.identity.auth.SupabaseSessionResponse.UserPayload;
import zen.identity.user.User;
import zen.identity.user.UserStore;

/**
 * {@code PUT /api/v1/auth/language}: a signed-in person changes their own {@code users.language},
 * and the e-mail the server sends them outside a request follows it.
 *
 * <p>The session is minted with {@code @TestSecurity} (the cookie path is proven by
 * {@code AuthResourceTest}); the subject is the user's id, which is all the route reads from it.
 * The language the route stores is what {@code EmailService} reads, so the e-mail assertion goes
 * through the stored column rather than through the request.
 */
@QuarkusTest
class SetLanguageTest {

  private static final String ME = "00000000-0000-0000-0000-0000000000a1";
  private static final String OTHER = "00000000-0000-0000-0000-0000000000b2";

  @Inject UserStore userStore;
  @Inject EmailService emailService;
  @Inject MockMailbox mailbox;

  @BeforeEach
  void seed() {
    mailbox.clear();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User.deleteAll();
              userStore.upsertOnLogin(payload(ME), "en");
              userStore.upsertOnLogin(payload(OTHER), "en");
            });
  }

  private static UserPayload payload(String id) {
    return new UserPayload(id, "lang-" + id + "@example.test", null, null, null);
  }

  private static String languageOf(String id) {
    return QuarkusTransaction.requiringNew()
        .call(() -> ((User) User.findById(UUID.fromString(id))).language);
  }

  /** JSON body plus the double-submit CSRF pair a cookie-session mutation carries. */
  private static io.restassured.specification.RequestSpecification put(String language) {
    String token = UUID.randomUUID().toString();
    return given()
        .header("X-Zen-Transport", "json")
        .contentType("application/json")
        .cookie(SessionService.CSRF_COOKIE, token)
        .header(SessionService.CSRF_HEADER, token)
        .body("{\"language\":\"" + language + "\"}");
  }

  @Test
  @TestSecurity(user = ME)
  void registeredInOneLanguage_changesIt_andTheNextEmailFollows() {
    assertEquals("en", languageOf(ME));

    assertEquals(204, put("uk").when().put("/api/v1/auth/language").statusCode());

    String stored = languageOf(ME);
    assertEquals("uk", stored);
    assertTrue(
        emailService.send(
            new LocalizedEmail(
                "me@example.test",
                stored,
                "welcome",
                "subject",
                Map.of("email", "me@example.test", "siteUrl", "https://example.test"),
                ME)));
    Mail mail = mailbox.getMailsSentTo("me@example.test").getFirst();
    assertTrue(
        mail.getHtml().contains("Ласкаво просимо до jZen"),
        "the Ukrainian template was expected, got: " + mail.getHtml());
  }

  @Test
  @TestSecurity(user = ME)
  void aRegionQualifiedTag_isStoredAsItsPrimarySubtag() {
    assertEquals(204, put("uk-UA").when().put("/api/v1/auth/language").statusCode());
    assertEquals("uk", languageOf(ME));
  }

  @Test
  @TestSecurity(user = ME)
  void anUnsupportedTag_is400_leavesTheStoredLanguage_andIsNotEchoed() {
    Response response = put("xx-secret").when().put("/api/v1/auth/language").andReturn();

    assertEquals(400, response.statusCode());
    assertFalse(response.asString().contains("xx"), "the submitted value must not be echoed");
    assertEquals("en", languageOf(ME), "a refusal changes nothing");
  }

  @Test
  @TestSecurity(user = ME)
  void aBlankTag_is400() {
    assertEquals(400, put("").when().put("/api/v1/auth/language").statusCode());
    assertEquals("en", languageOf(ME));
  }

  @Test
  @TestSecurity(user = ME)
  void anotherUsersRow_isUntouched() {
    assertEquals(204, put("uk").when().put("/api/v1/auth/language").statusCode());
    assertEquals("en", languageOf(OTHER));
  }

  @Test
  void withoutASession_is401() {
    assertEquals(401, put("uk").when().put("/api/v1/auth/language").statusCode());
    assertEquals("en", languageOf(ME));
  }
}
