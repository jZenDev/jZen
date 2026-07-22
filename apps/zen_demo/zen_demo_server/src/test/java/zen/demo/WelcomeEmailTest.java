package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.google.protobuf.util.JsonFormat;
import io.quarkus.mailer.Mail;
import io.quarkus.mailer.MockMailbox;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import jakarta.ws.rs.core.HttpHeaders;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.identity.user.User;
import zen.proto.v1.RegisterRequest;

/**
 * Proves ROADMAP step 6 end to end on the registration path: the language of the registering
 * request lands in {@code users.language}, and the welcome message that follows is localized from
 * that column - Ukrainian subject with Ukrainian body, English subject with English body, chosen
 * by no more than the {@code Accept-Language} header.
 *
 * <p>No SMTP anywhere: {@code quarkus.mailer.mock=true} means the mailer records instead of
 * sending, and {@link MockMailbox} is what the assertions read. The Supabase client is mocked
 * exactly as in {@code AuthResourceTest}; Dev Services provisions Postgres.
 *
 * <p>The mail is sent from an {@code @ObservesAsync} observer, so the assertions poll the mailbox
 * rather than assuming the message has arrived by the time the HTTP response has.
 */
@QuarkusTest
class WelcomeEmailTest {

  private static final String HEADER = "X-Zen-Transport";
  private static final String JSON = "json";
  private static final long MAIL_TIMEOUT_MS = 10_000;
  private static final long POLL_INTERVAL_MS = 50;

  @InjectMock @RestClient SupabaseAuthClient authClient;
  @Inject MockMailbox mailbox;

  @BeforeEach
  void clearMailbox() {
    mailbox.clear();
  }

  @Test
  void register_withUkrainianHeader_sendsUkrainianWelcome() throws Exception {
    UUID id = UUID.randomUUID();
    String email = "welcome-uk@example.com";
    when(authClient.signup(any(), any())).thenReturn(session(id, email));

    assertEquals(200, register(email, "uk-UA").statusCode());

    Mail mail = awaitSingleMailTo(email);
    assertEquals("Ласкаво просимо до jZen", mail.getSubject());
    assertTrue(
        mail.getHtml().contains("Ласкаво просимо до jZen"),
        "Ukrainian body expected, got: " + mail.getHtml());
    assertTrue(mail.getHtml().contains(email), "the body binds the recipient address");
    assertEquals("uk", languageOf(id), "Accept-Language seeds users.language");
  }

  @Test
  void register_withoutLanguageHeader_sendsEnglishWelcome() throws Exception {
    UUID id = UUID.randomUUID();
    String email = "welcome-en@example.com";
    when(authClient.signup(any(), any())).thenReturn(session(id, email));

    assertEquals(200, register(email, null).statusCode());

    Mail mail = awaitSingleMailTo(email);
    assertEquals("Welcome to jZen", mail.getSubject());
    assertTrue(
        mail.getHtml().contains("Welcome to jZen"), "English body expected, got: " + mail.getHtml());
    assertEquals("en", languageOf(id), "no header falls back to the default locale");
  }

  @Test
  void register_withUnsupportedLanguage_fallsBackToEnglish() throws Exception {
    UUID id = UUID.randomUUID();
    String email = "welcome-fr@example.com";
    when(authClient.signup(any(), any())).thenReturn(session(id, email));

    assertEquals(200, register(email, "fr-FR").statusCode());

    Mail mail = awaitSingleMailTo(email);
    assertEquals("Welcome to jZen", mail.getSubject());
    assertEquals("en", languageOf(id), "an unsupported tag is narrowed to the fallback");
  }

  /** A second registration for an identity that already has a profile must not greet it again. */
  @Test
  void register_forExistingProfile_doesNotResendWelcome() throws Exception {
    UUID id = UUID.randomUUID();
    String email = "welcome-once@example.com";
    when(authClient.signup(any(), any())).thenReturn(session(id, email));

    assertEquals(200, register(email, "en").statusCode());
    awaitSingleMailTo(email);
    mailbox.clear();

    assertEquals(200, register(email, "en").statusCode());
    /*
     * Nothing is expected to arrive, so there is no state change to poll for. Give the async
     * observer the same window a real send would need, then assert the mailbox stayed empty.
     */
    sleep(500);
    assertEquals(List.of(), mailbox.getMailsSentTo(email), "welcome is sent once per profile");
  }

  private io.restassured.response.Response register(String email, String acceptLanguage)
      throws Exception {
    RegisterRequest body =
        RegisterRequest.newBuilder().setEmail(email).setPassword("secret1").build();
    var request =
        given().header(HEADER, JSON).contentType("application/json").body(JsonFormat.printer().print(body));
    if (acceptLanguage != null) {
      request = request.header(HttpHeaders.ACCEPT_LANGUAGE, acceptLanguage);
    }
    return request.when().post("/api/v1/auth/register").andReturn();
  }

  private SupabaseSessionResponse session(UUID id, String email) {
    return new SupabaseSessionResponse(
        "access-jwt",
        "refresh-jwt",
        new SupabaseSessionResponse.UserPayload(id.toString(), email, "authenticated", Map.of()),
        null,
        null);
  }

  private String languageOf(UUID id) {
    return QuarkusTransaction.requiringNew()
        .call(
            () -> {
              User user = User.findById(id);
              return user == null ? null : user.language;
            });
  }

  private Mail awaitSingleMailTo(String address) {
    long deadline = System.currentTimeMillis() + MAIL_TIMEOUT_MS;
    while (System.currentTimeMillis() < deadline) {
      List<Mail> mails = mailbox.getMailsSentTo(address);
      if (!mails.isEmpty()) {
        assertEquals(1, mails.size(), "exactly one message expected for " + address);
        return mails.getFirst();
      }
      sleep(POLL_INTERVAL_MS);
    }
    return fail("No mail reached " + address + " within " + MAIL_TIMEOUT_MS + "ms");
  }

  private void sleep(long millis) {
    try {
      Thread.sleep(millis);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      fail("Interrupted while waiting for mail");
    }
  }
}
