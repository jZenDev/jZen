package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;

/**
 * Proves the static-resource validator is actually installed and actually answers.
 *
 * <p>{@code StaticCacheHeaders} is a Vert.x route contributed by {@code zen-transport}, so like
 * every other provider in a library jar it is discovered only through that module's Jandex index —
 * lose the index and the route is silently absent, with no error anywhere. The same silence is what
 * hid F2 for the life of the service: no {@code ETag} was ever sent, the class javadoc asserted one
 * was, and the only visible symptom was a bill. Behaviour asserted against an assembled application
 * is the answer to both, which is the precedent {@code RateLimitWiringTest} sets (ADR-029).
 *
 * <p><b>What this cannot assert, and where that is asserted instead.</b> The property that failed is
 * that a validator survives the process that issued it, and no in-process test can restart a
 * process. What is checked here is that the served validator is the configured build stamp and
 * nothing else — {@code StaticCacheHeadersTest} proves that value is a pure function of the build —
 * and {@code task test:native} replays an {@code ETag} across a real {@code docker restart} of the
 * real native image.
 *
 * <p>The probe files are test-scoped resources under {@code META-INF/resources}. The real bundle is
 * built by {@code task build:web} and gitignored, so keying on {@code main.dart.wasm} would make
 * this test's result depend on whether the frontend happened to be staged.
 */
@QuarkusTest
class StaticCacheHeadersWiringTest {

  private static final String LONG_CACHED = "/zen-probe/asset.txt";
  private static final String ENTRY_FILE = "/zen-probe/index.html";

  private static String etagOf(String path) {
    Response response = given().when().get(path).andReturn();
    assertEquals(200, response.statusCode(), path + " must be served for this test to mean anything");
    String etag = response.getHeader("ETag");
    assertNotNull(etag, "no ETag on " + path + ": the validator route is not installed");
    assertTrue(etag.startsWith("\"") && etag.endsWith("\""), "must be a strong entity-tag: " + etag);
    return etag;
  }

  @Test
  void staticResource_carriesAnEtag() {
    etagOf(ENTRY_FILE);
  }

  @Test
  void longCachedResource_carriesTheSameEtag() {
    // canvaskit/* and assets/* keep their day of `immutable` freshness; when it expires they
    // revalidate, and that revalidation has to be able to come back empty too.
    assertEquals(etagOf(ENTRY_FILE), etagOf(LONG_CACHED), "one build stamp validates every static resource");
  }

  @Test
  void matchingIfNoneMatch_returns304WithNoBody() {
    Response response =
        given().header("If-None-Match", etagOf(ENTRY_FILE)).when().get(ENTRY_FILE).andReturn();

    assertEquals(304, response.statusCode());
    assertEquals(0, response.getBody().asByteArray().length, "a 304 must carry no body");
  }

  /**
   * The RFC 9110 §13.2.2 precedence rule, which is the single most likely way this fix passes
   * review and does nothing. A real browser revalidates with <em>both</em> headers, and the static
   * handler still stamps a {@code Last-Modified} that moved when this process started — so if
   * {@code If-Modified-Since} were still evaluated, every browser would keep getting 200s and the
   * whole change would be invisible. The date used here is 1970: about as stale as a value can be,
   * and one that would certainly produce a 200 on its own.
   */
  @Test
  void ifNoneMatchWins_overAStaleIfModifiedSince() {
    Response response =
        given()
            .header("If-None-Match", etagOf(ENTRY_FILE))
            .header("If-Modified-Since", "Thu, 01 Jan 1970 00:00:00 GMT")
            .when()
            .get(ENTRY_FILE)
            .andReturn();

    assertEquals(304, response.statusCode(), "If-None-Match must be answered and If-Modified-Since ignored");
    assertEquals(0, response.getBody().asByteArray().length);
  }

  @Test
  void staleIfModifiedSinceAlone_stillSendsTheBody() {
    // Establishes that the header in the test above is genuinely one that forces a 200, so the 304
    // there can only have come from the ETag path.
    Response response =
        given()
            .header("If-Modified-Since", "Thu, 01 Jan 1970 00:00:00 GMT")
            .when()
            .get(ENTRY_FILE)
            .andReturn();

    assertEquals(200, response.statusCode());
    assertTrue(response.getBody().asByteArray().length > 0);
  }

  @Test
  void validatorFromAnEarlierBuild_returnsTheNewBytes() {
    // The rebuild case: a deploy changes zen.build.id, so a browser holding the previous validator
    // misses and downloads the new app instead of being told nothing changed.
    Response response =
        given()
            .header("If-None-Match", "\"a-previous-build\"")
            .when()
            .get(ENTRY_FILE)
            .andReturn();

    assertEquals(200, response.statusCode());
    assertTrue(response.getBody().asByteArray().length > 0);
  }

  @Test
  void entryFilesRevalidate_andLongCachedOnesDoNot() {
    assertTrue(given().when().get(ENTRY_FILE).andReturn().getHeader("Cache-Control").contains("no-cache"));
    assertTrue(given().when().get(LONG_CACHED).andReturn().getHeader("Cache-Control").contains("max-age=86400"));
  }

  @Test
  void the304RestatesTheCacheControlOfThe200() {
    // Otherwise a revalidated resource comes back without a freshness lifetime and the browser
    // revalidates it again on the very next load, which gives back most of what this saves.
    for (String path : new String[] {ENTRY_FILE, LONG_CACHED}) {
      String etag = etagOf(path);
      String served = given().when().get(path).andReturn().getHeader("Cache-Control");
      String revalidated =
          given().header("If-None-Match", etag).when().get(path).andReturn().getHeader("Cache-Control");
      assertEquals(served, revalidated, "the 200 and the 304 for " + path + " must agree");
    }
  }

  /**
   * A build-stable validator is only correct for build-stable bytes. These are the roots served by
   * something other than the static handler; an {@code ETag} on any of them would let a browser be
   * told "nothing changed" about a response that changes on every call. Adding a JAX-RS root
   * outside {@code StaticCacheHeaders.DYNAMIC_PREFIXES} fails here rather than silently.
   */
  @Test
  void dynamicEndpoints_carryNoValidator() {
    for (String path : new String[] {"/api/v1/health", "/api/v1/demo/ping", "/.well-known/assetlinks.json"}) {
      assertNull(
          given().when().get(path).andReturn().getHeader("ETag"),
          path + " is dynamic and must not be served with a build-stable validator");
    }
  }

  @Test
  void dynamicEndpoints_ignoreIfNoneMatch() {
    // The other half: even a client that guesses the validator must not be able to turn a dynamic
    // response into a 304.
    Response response =
        given()
            .header("If-None-Match", etagOf(ENTRY_FILE))
            .when()
            .get("/api/v1/health")
            .andReturn();
    assertEquals(200, response.statusCode());
  }

  /**
   * A 304 skips every route that has not run yet, so it must be ordered after the one that installs
   * the security headers. Two routes at the same order run in registration order, which nothing
   * here controls — this is what makes that ordering a decision rather than a coincidence.
   */
  @Test
  void the304CarriesTheSecurityHeaders() {
    io.restassured.response.Response response =
        given().header("If-None-Match", etagOf(ENTRY_FILE)).when().get(ENTRY_FILE).andReturn();
    assertEquals(304, response.statusCode());
    for (String header :
        new String[] {
          "Content-Security-Policy", "X-Frame-Options", "X-Content-Type-Options", "Referrer-Policy"
        }) {
      assertNotNull(response.getHeader(header), "a 304 must carry " + header + " like the 200 does");
    }
  }

  @Test
  void missingResource_getsNoValidator() {
    // A 404 that handed out an ETag would let a browser hold a validator for bytes that do not
    // exist yet, and be told they had not changed once they did.
    Response response = given().when().get("/zen-probe/does-not-exist.txt").andReturn();
    assertEquals(404, response.statusCode());
    assertNull(response.getHeader("ETag"));
  }
}
