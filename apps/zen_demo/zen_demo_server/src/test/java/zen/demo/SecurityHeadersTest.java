package zen.demo;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.nullValue;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.ValidatableResponse;
import org.junit.jupiter.api.Test;

/**
 * What the security headers actually say, on each of the three paths that take a different route
 * through the stack.
 *
 * <p>The three are not a formality. {@code /api/} is dispatched by JAX-RS; {@code /} and
 * {@code /admin/} are served by Quarkus's static-resource handler and never reach JAX-RS at all,
 * which is the entire reason these headers are installed on the Vert.x router instead of as a
 * {@code ContainerResponseFilter}. A filter would have passed a test that only probed the API and
 * shipped two bare browser documents.
 *
 * <p><strong>Status codes are deliberately not asserted for the two static paths.</strong> The web
 * bundle and the admin panel are staged into {@code META-INF/resources} by {@code task build:web}
 * and {@code build:web:admin}, and that directory is gitignored — so on a clean checkout those
 * paths 404. That is fine and is in fact the stronger assertion: the header route runs at
 * {@link Integer#MIN_VALUE}, before anything decides what to serve, so it must cover the response
 * whatever produces it. The headers on the <em>real</em> served bundle are asserted against a live
 * container by {@code task verify:endpoints}, which is where a built artifact exists.
 */
@QuarkusTest
class SecurityHeadersTest {

  @Test
  void theApiCarriesEveryHeader() {
    assertHeaders(given().header("X-Zen-Transport", "json").when().get("/api/v1/health").then());
  }

  @Test
  void theWebAppRootCarriesEveryHeader() {
    // The response that most needs a CSP: a browser document, with a DOM, that JAX-RS never sees.
    assertHeaders(given().when().get("/").then());
  }

  @Test
  void theAdminPanelCarriesEveryHeader() {
    // Same, and it is the surface holding an admin session.
    assertHeaders(given().when().get("/admin/").then());
  }

  @Test
  void anErrorResponseIsNotAnExemption() {
    // A 401 is still a response a browser renders, and an unauthenticated page is exactly where an
    // injected frame or an inline script would be most useful to an attacker.
    assertHeaders(given().header("X-Zen-Transport", "json").when().get("/api/v1/demo/profile").then());
  }

  @Test
  void theContentSecurityPolicyKeepsScriptSrcToThisOrigin() {
    // The term the whole 4.1 design turns on. The deployed page used to load its renderer from
    // www.gstatic.com; the build now serves the copy it was already shipping, so no CDN belongs in
    // script-src. A host appearing here is permission to execute whatever that host serves.
    given()
        .when()
        .get("/api/v1/health")
        .then()
        .header("Content-Security-Policy", containsString("script-src 'self' 'wasm-unsafe-eval'"))
        .header("Content-Security-Policy", not(containsString("gstatic.com/flutter-canvaskit")))
        .header("Content-Security-Policy", not(containsString("'unsafe-eval'; ")))
        .header("Content-Security-Policy", not(containsString("script-src 'self' *")));
  }

  @Test
  void theFontHostIsAllowedInBothDirectivesTheEngineCanUse() {
    // fonts.gstatic.com is the single relaxation this policy makes for anyone else, and it needs
    // BOTH of these. The Flutter engine fetches fonts with fetch(), which CSP governs by
    // connect-src, not by font-src — so naming the host only in font-src allows it in the
    // mechanism the engine does not use and blocks it in the one it does. That shipped once: the
    // app booted, the layout rendered, and there was no text on the page, with every test green.
    // Measured in Chrome against the real native image: fetch() BLOCKED, FontFace().load() ok.
    given()
        .when()
        .get("/api/v1/health")
        .then()
        .header(
            "Content-Security-Policy",
            containsString("font-src 'self' https://fonts.gstatic.com"))
        .header(
            "Content-Security-Policy",
            containsString("connect-src 'self' https://fonts.gstatic.com"))
        .header("Content-Security-Policy", containsString("default-src 'self'"));
  }

  @Test
  void connectSrcAdmitsNothingBeyondTheFontHost() {
    // The directive that decides where an injected script could send data. One named host that
    // serves static files is not an exfiltration channel; a wildcard or a scheme would be, and
    // widening it is the cheapest-looking way to make some future console error go away.
    String csp =
        given().when().get("/api/v1/health").then().extract().header("Content-Security-Policy");
    String connectSrc =
        java.util.Arrays.stream(csp.split(";"))
            .map(String::trim)
            .filter(d -> d.startsWith("connect-src"))
            .findFirst()
            .orElseThrow(() -> new AssertionError("no connect-src directive in: " + csp));
    org.junit.jupiter.api.Assertions.assertEquals(
        "connect-src 'self' https://fonts.gstatic.com",
        connectSrc,
        "connect-src has been widened. It is the term that stops an injected script from sending"
            + " data anywhere it likes, so anything added here needs the same argument the font"
            + " host got — and 'https:' or '*' cannot be given one.");
  }

  @Test
  void hstsIsNotSentOverPlainHttp() {
    // RestAssured reaches the test server over http, and this profile trusts no proxy header. A
    // browser that honoured an HSTS sent here would pin localhost to HTTPS for a year, against a
    // port with no TLS on it — so the header is gated on the effective scheme, and this is the
    // gate. The other direction is SecurityHeadersBehindProxyTest, which is where it must appear.
    given()
        .header("X-Zen-Transport", "json")
        .header("X-Forwarded-Proto", "https")
        .when()
        .get("/api/v1/health")
        .then()
        .header("Strict-Transport-Security", nullValue());
  }

  private static void assertHeaders(ValidatableResponse response) {
    response
        .header("Content-Security-Policy", containsString("default-src 'self'"))
        .header("X-Frame-Options", equalTo("DENY"))
        .header("X-Content-Type-Options", equalTo("nosniff"))
        .header("Referrer-Policy", equalTo("strict-origin-when-cross-origin"))
        .header(
            "Permissions-Policy",
            equalTo("geolocation=(), camera=(), microphone=(), payment=(), usb=()"))
        .header("Cross-Origin-Opener-Policy", equalTo("same-origin"))
        .header("Cross-Origin-Resource-Policy", equalTo("same-origin"));
  }
}
