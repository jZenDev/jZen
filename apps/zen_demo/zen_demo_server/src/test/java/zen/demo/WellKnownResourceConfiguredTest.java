package zen.demo;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import java.util.Map;
import org.junit.jupiter.api.Test;

/**
 * The association files as a deployment that has ADOPTED App Links serves them.
 *
 * <p>A class of its own rather than a @Nested one inside {@link WellKnownResourceTest}, because
 * Quarkus refuses @TestProfile on a nested class — a profile means a differently configured
 * application, and that is a whole boot, not an inner scope. The unconfigured half lives there;
 * both halves matter, since 404-when-unset is as much the contract as the file's contents.
 */
@QuarkusTest
@TestProfile(WellKnownResourceConfiguredTest.Configured.class)
class WellKnownResourceConfiguredTest {

  private static final String ASSETLINKS = "/.well-known/assetlinks.json";
  private static final String AASA = "/.well-known/apple-app-site-association";

    @Test
  void assetLinks_namesThePackageAndEveryFingerprint() {
    given()
        .when()
        .get(ASSETLINKS)
        .then()
        .statusCode(200)
        .contentType(containsString("application/json"))
        .body(containsString("delegate_permission/common.handle_all_urls"))
        .body(containsString("\"namespace\":\"android_app\""))
        .body(containsString("dev.jzen.zen_demo_client"))
        // Both keys, deliberately: a debug keystore and a release key sign different builds of
        // the same app, and a build signed by an unlisted key fails verification silently.
        .body(containsString("AA:BB"))
        .body(containsString("CC:DD"));
  }

  @Test
  void appleAssociation_namesTheTeamQualifiedBundleId() {
    given()
        .when()
        .get(AASA)
        .then()
        .statusCode(200)
        .contentType(containsString("application/json"))
        .body(containsString("\"applinks\""))
        .body(containsString("TEAMID123.dev.jzen.zenDemoClient"))
        .body(containsString("\"components\""));
  }

  @Test
  void theAppleFileIsServedWithoutAnExtension() {
    // Required by iOS, and the kind of thing a well-meaning static-file rule breaks.
    given().when().get(AASA + ".json").then().statusCode(404);
  }

  @Test
  void neitherFileRedirects() {
    // A redirect fails verification on both platforms, so the 200 must be the first response.
    given().redirects().follow(false).when().get(ASSETLINKS).then().statusCode(200);
    given().redirects().follow(false).when().get(AASA).then().statusCode(200);
  }

  @Test
  void bothFilesAreAnonymous() {
    // The OS fetches them with no cookies and no credentials. If auth ever leaked onto these
    // paths the association would break in a way nothing else would show.
    given().when().get(ASSETLINKS).then().statusCode(not(401));
    given().when().get(AASA).then().statusCode(not(401));
  }

  /** A deployment that has adopted App Links on both platforms. */
  public static class Configured implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      return Map.of(
          "auth.applinks.android-package", "dev.jzen.zen_demo_client",
          "auth.applinks.android-fingerprints", "AA:BB,CC:DD",
          "auth.applinks.apple-app-ids", "TEAMID123.dev.jzen.zenDemoClient");
    }
  }
}
