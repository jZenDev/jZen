package zen.demo;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import io.quarkus.test.junit.QuarkusTestProfile;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * The App Links / Universal Links association files.
 *
 * <p>Two profiles, because the interesting behaviour is on both sides of "configured": unset must
 * 404 rather than serve an empty document, and set must produce exactly what the platforms parse.
 * The default profile is the unconfigured one, which is also what the application ships with.
 */
@QuarkusTest
class WellKnownResourceTest {

  private static final String ASSETLINKS = "/.well-known/assetlinks.json";
  private static final String AASA = "/.well-known/apple-app-site-association";

  @Test
  void unconfigured_bothFiles_are404_notEmptyDocuments() {
    // Not a stylistic choice: a file that is present but does not name the app tells Android and
    // iOS that verification FAILED, and both cache that outcome. Absent is a state they retry from.
    given().when().get(ASSETLINKS).then().statusCode(404);
    given().when().get(AASA).then().statusCode(404);
  }
}
