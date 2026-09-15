package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;
import zen.identity.user.UserRole;

/**
 * Proves {@code ZenTransportResponseFilter} sets the two cache-correctness headers (F6) on a real
 * {@code /api/} response, in an assembled application.
 *
 * <p>{@code /api/v1/auth/identity} is used for both cases because it is the one endpoint already
 * proven (in {@code CsrfWiringTest}) to answer both anonymously and under {@code @TestSecurity}
 * with no other setup — the header assertions here ride the same request shapes rather than
 * introducing a new one.
 */
@QuarkusTest
class ZenTransportHeadersTest {

  private static final String HEADER = "X-Zen-Transport";
  private static final String USER_ID = "3f4a1b2c-0000-4000-8000-00000000th01";

  @Test
  void everyApiResponseCarriesVary() {
    Response resp = given().header(HEADER, "json").when().get("/api/v1/auth/identity").andReturn();

    assertEquals(
        "X-Zen-Transport, Accept-Language, Origin, Cookie", resp.getHeader("Vary"));
  }

  @Test
  void anonymousResponseCarriesNoCacheControl() {
    // Nothing caller-specific to protect: no session was presented, so there is nothing here for
    // a cache to leak to the next request.
    Response resp = given().header(HEADER, "json").when().get("/api/v1/auth/identity").andReturn();

    assertNull(resp.getHeader("Cache-Control"));
  }

  @Test
  @TestSecurity(user = USER_ID, roles = UserRole.Names.USER)
  void authenticatedResponseCarriesNoStore() {
    Response resp = given().header(HEADER, "json").when().get("/api/v1/auth/identity").andReturn();

    assertEquals("no-store", resp.getHeader("Cache-Control"));
  }
}
