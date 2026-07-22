package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

import com.google.protobuf.util.JsonFormat;
import io.quarkus.mailer.Mail;
import io.quarkus.mailer.Mailer;
import io.quarkus.test.InjectMock;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.response.Response;
import jakarta.enterprise.inject.Alternative;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;
import org.eclipse.microprofile.rest.client.inject.RestClient;
import org.junit.jupiter.api.Test;
import zen.email.EmailService;
import zen.email.LocalizedEmail;
import zen.identity.auth.SupabaseAuthClient;
import zen.identity.auth.SupabaseSessionResponse;
import zen.proto.v1.RegisterRequest;

/**
 * The other half of the email contract: what happens when mail cannot be sent. Email is a side
 * effect of a business action, so an unreachable mail server, a missing template, or a rendering
 * error must degrade to a log line and nothing more - never a failed registration.
 *
 * <p>The outage is injected as a real CDI alternative that always throws, enabled only for this
 * class's test profile. That is closer to the truth than stubbing a method and, unlike pointing
 * the mailer at an unreachable host, it keeps the suite hermetic: CI never talks to SMTP.
 */
@QuarkusTest
@TestProfile(EmailFailureTest.UnreachableMailerProfile.class)
class EmailFailureTest {

  private static final String HEADER = "X-Zen-Transport";
  private static final long SEND_TIMEOUT_MS = 10_000;
  private static final long POLL_INTERVAL_MS = 50;

  @InjectMock @RestClient SupabaseAuthClient authClient;
  @Inject EmailService emailService;

  /** Enables {@link UnreachableMailer} for this class only, leaving the other suites unaffected. */
  public static class UnreachableMailerProfile implements QuarkusTestProfile {
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      return Set.of(UnreachableMailer.class);
    }
  }

  /**
   * A mailer that behaves like an SMTP server refusing connections. Deliberately carries no
   * {@code @Priority}: that would enable the alternative for every bean archive in the module and
   * break every other suite's mail assertions. The test profile above is what switches it on, and
   * only here.
   */
  @Alternative
  @Singleton
  public static class UnreachableMailer implements Mailer {

    static final AtomicInteger ATTEMPTS = new AtomicInteger();

    @Override
    public void send(Mail... mails) {
      ATTEMPTS.incrementAndGet();
      throw new IllegalStateException("SMTP unavailable");
    }
  }

  @Test
  void registration_succeedsWhenTheMailServerIsDown() throws Exception {
    UnreachableMailer.ATTEMPTS.set(0);
    UUID id = UUID.randomUUID();
    String email = "smtp-down@example.com";
    when(authClient.signup(any(), any())).thenReturn(session(id, email));

    RegisterRequest body =
        RegisterRequest.newBuilder().setEmail(email).setPassword("secret1").build();
    Response resp =
        given()
            .header(HEADER, "json")
            .header("Accept-Language", "uk")
            .contentType("application/json")
            .body(JsonFormat.printer().print(body))
            .when()
            .post("/api/v1/auth/register")
            .andReturn();

    assertEquals(200, resp.statusCode(), "registration must not depend on the welcome message");
    /* The send really was attempted, and the exception it raised went no further. */
    assertTrue(awaitSendAttempt(), "the welcome message was attempted and its failure swallowed");
  }

  @Test
  void send_withNoTemplateForTheLocale_reportsFailureWithoutThrowing() {
    boolean sent =
        emailService.send(
            LocalizedEmail.of("nobody@example.com", "en", "no_such_template", "Subject"));

    assertFalse(sent, "a missing template is reported, never thrown");
  }

  @Test
  void send_whenTheMailerThrows_reportsFailureWithoutThrowing() {
    boolean sent =
        emailService.send(
            new LocalizedEmail(
                "nobody@example.com",
                "uk",
                "welcome",
                "Subject",
                Map.of("email", "nobody@example.com", "siteUrl", "http://localhost:8080")));

    assertFalse(sent, "an SMTP failure is reported, never thrown");
  }

  /** The welcome message is sent from an async observer, so the attempt is awaited, not assumed. */
  private boolean awaitSendAttempt() {
    long deadline = System.currentTimeMillis() + SEND_TIMEOUT_MS;
    while (System.currentTimeMillis() < deadline) {
      if (UnreachableMailer.ATTEMPTS.get() > 0) {
        return true;
      }
      try {
        Thread.sleep(POLL_INTERVAL_MS);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
        return false;
      }
    }
    return false;
  }

  private SupabaseSessionResponse session(UUID id, String email) {
    return new SupabaseSessionResponse(
        "access-jwt",
        "refresh-jwt",
        new SupabaseSessionResponse.UserPayload(id.toString(), email, "authenticated", Map.of()),
        null,
        null);
  }
}
