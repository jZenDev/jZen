package zen.demo;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * {@code Strict-Transport-Security} appears exactly where it can be honoured: behind a proxy that
 * terminated TLS.
 *
 * <p>This needs its own profile because it is the only way to reproduce production's shape. Cloud
 * Run terminates TLS at its frontend, so the connection Quarkus accepts is plain HTTP and the only
 * evidence the client used TLS is {@code X-Forwarded-Proto} — which Vert.x reads into
 * {@code scheme()} only when {@code proxy-address-forwarding} is on. Those two settings live in
 * {@code %prod} (beside {@code allow-x-forwarded}, which the rate limiter's address arithmetic also
 * depends on), and this profile turns them on so the assertion is about the deployed
 * configuration rather than about the test one.
 *
 * <p>Without this class the suite could only ever prove that HSTS is absent, which is half a
 * control: a gate that always closes and a gate that never opens look identical from the closed
 * side. {@code SecurityHeadersTest.hstsIsNotSentOverPlainHttp} is the other half, and neither is
 * worth much alone.
 */
@QuarkusTest
@TestProfile(SecurityHeadersBehindProxyTest.TrustedProxyProfile.class)
class SecurityHeadersBehindProxyTest {

  @Test
  void hstsIsSentWhenTheProxySaysTheClientUsedTls() {
    given()
        .header("X-Zen-Transport", "json")
        .header("X-Forwarded-Proto", "https")
        .when()
        .get("/api/v1/health")
        .then()
        .header("Strict-Transport-Security", equalTo("max-age=31536000"));
  }

  @Test
  void hstsPromisesNothingAboutSubdomainsAndEntersNoPreloadList() {
    // Both are deliberate omissions, not oversights, so they are asserted rather than left to a
    // comment. The service answers on a generated *.run.app hostname and the domain question is
    // still open (ADR-027) — includeSubDomains would bind names that do not exist, and preload is
    // a submission to a browser-vendor list that takes months to leave. They become correct when
    // there is a real domain; until then this assertion is what stops them arriving by habit.
    given()
        .header("X-Zen-Transport", "json")
        .header("X-Forwarded-Proto", "https")
        .when()
        .get("/api/v1/health")
        .then()
        .header("Strict-Transport-Security", not(containsString("includeSubDomains")))
        .header("Strict-Transport-Security", not(containsString("preload")));
  }

  @Test
  void aPlainRequestBehindTheProxyStillGetsNoHsts() {
    // The proxy is trusted here, so this asks the question the other way round: a client that
    // genuinely arrived over plain HTTP must not be told to upgrade for a year on the strength of
    // nothing. Sent unconditionally, the header would be wrong for exactly this caller.
    given()
        .header("X-Zen-Transport", "json")
        .header("X-Forwarded-Proto", "http")
        .when()
        .get("/api/v1/health")
        .then()
        .header("Strict-Transport-Security", org.hamcrest.Matchers.nullValue());
  }

  /**
   * Production's proxy settings, and the one thing that has to travel with them.
   *
   * <p>{@code zen.ratelimit.forwarded-hops=1} is not padding. {@code RateLimitAddressGuard} refuses
   * to boot when proxy forwarding is on and the hop count is 0, because that pairing makes the
   * limiter count an address the caller chooses — so turning forwarding on without it would not
   * produce a failing assertion here, it would produce an application that does not start. That
   * the guard fires on this profile is itself confirmation the two settings belong together, which
   * is exactly what {@code %prod} declares.
   */
  public static class TrustedProxyProfile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "quarkus.http.proxy.proxy-address-forwarding", "true",
          "quarkus.http.proxy.allow-x-forwarded", "true",
          "zen.ratelimit.forwarded-hops", "1");
    }
  }
}
