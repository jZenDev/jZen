package zen.demo;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/**
 * The default build still serves {@code /openapi}, which is the half of task 4.2 that is easy to
 * lose and expensive to notice.
 *
 * <p>The native/prod build drops {@code quarkus-smallrye-openapi} (see the {@code openapi} profile
 * in this module's pom), and {@code task verify:endpoints} asserts the endpoint is gone from the
 * image. Asserting only that direction proves nothing useful: a build that lost the extension
 * everywhere would satisfy it perfectly. This is the opposite assertion, and it is the one guarding
 * the contract pipeline.
 *
 * <p>What breaks if it goes: {@code task generate:api:schema} packages the app to make SmallRye
 * write {@code target/openapi/openapi.json}; {@code generate:api:ts} is guarded by
 * {@code status: test ! -f …/openapi.json}, so with no file it does not fail — it <em>skips</em>.
 * {@code sync:contracts} then diffs a {@code schema.generated.ts} nobody regenerated, finds it
 * clean, and reports the contracts in sync. The panel's types silently stop tracking the API, and
 * the first symptom is a TypeScript error about a field that does exist.
 *
 * <p>Being a {@code @QuarkusTest}, this runs in the default build by construction — which is
 * exactly the build the assertion is about.
 */
@QuarkusTest
class OpenApiProfileTest {

  @Test
  void theSchemaEndpointIsServedInTheDefaultBuild() {
    given()
        .accept("application/json")
        .when()
        .get("/openapi")
        .then()
        .statusCode(200)
        // Not merely a 200: the document has to contain the real surface, because an empty or
        // path-less schema would generate an empty TypeScript module just as quietly.
        .body(containsString("/api/v1/admin/users"));
  }
}
