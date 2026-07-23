package zen.demo;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import zen.identity.user.User;
import zen.identity.user.UserRole;
import zen.jobs.JobState;
import zen.jobs.JobStatus;
import zen.jobs.JobTriggerAuthenticator;

/**
 * The trigger endpoint: who may pull it, and that pulling it really does the work.
 *
 * <p>The credential cases matter more than usual here. Cloud Run serves this application with
 * {@code --allow-unauthenticated}, so in production this path is reachable by anyone on the
 * internet, and what it drives is the job that erases personal data. The token used here comes from
 * {@code %test.zen.jobs.trigger.token} in {@code application.properties}, mirroring how a real
 * deployment supplies it from Secret Manager.
 */
@QuarkusTest
class JobTriggerResourceTest {

  private static final String TRIGGER_PATH = "/api/v1/jobs/trigger";
  private static final String TOKEN_HEADER = JobTriggerAuthenticator.TOKEN_HEADER;

  /** Matches %test.zen.jobs.trigger.token in application.properties. */
  private static final String VALID_TOKEN = "test-job-trigger-token";

  private static final String RETENTION_JOB = "user-retention";
  private static final int DORMANT_DAYS = 400;

  @Test
  void aTriggerCarryingTheSharedSecretRunsDueJobs() {
    armRetentionJob();

    Response response =
        given()
            .header(TOKEN_HEADER, VALID_TOKEN)
            .when()
            .post(TRIGGER_PATH)
            .andReturn();

    assertEquals(200, response.statusCode());
    assertEquals(1, response.jsonPath().getInt("due"), "the retention job was due");
    assertEquals(1, response.jsonPath().getInt("succeeded"));
    assertEquals(RETENTION_JOB, response.jsonPath().getString("runs[0].jobId"));
    assertEquals("success", response.jsonPath().getString("runs[0].status"));

    JobState state = reloadJob();
    assertNotNull(state.lastRunAt, "the run is visible after the fact, which is the point");
    assertEquals(JobStatus.SUCCESS, state.lastStatus);
  }

  @Test
  void aTriggerWithNoCredentialIsRejected() {
    Response response = given().when().post(TRIGGER_PATH).andReturn();

    assertEquals(401, response.statusCode());
    assertEquals("unauthorized", response.jsonPath().getString("code"), "a ZenError, not a stack trace");
  }

  @Test
  void aTriggerWithTheWrongSecretIsRejected() {
    assertEquals(
        401,
        given().header(TOKEN_HEADER, VALID_TOKEN + "-nope").when().post(TRIGGER_PATH).statusCode());
  }

  /**
   * The credential jZen uses everywhere else must not open this door. An admin session is the
   * strongest identity the application issues, and it is still not a job trigger: the two are
   * different kinds of caller, and conflating them would put a data-erasing endpoint behind a
   * cookie that browsers send automatically.
   */
  @Test
  @TestSecurity(user = "admin-user", roles = UserRole.Names.ADMIN)
  void anAdminSessionWithoutTheSecretIsStillRejected() {
    Response response = given().when().post(TRIGGER_PATH).andReturn();

    assertEquals(401, response.statusCode(), "the session path grants nothing here");
    assertEquals("unauthorized", response.jsonPath().getString("code"));
  }

  /**
   * The whole point of the step, end to end: an external caller pulls one trigger and a dormant
   * account is warned, with no cron and no in-process timer anywhere in the path.
   */
  @Test
  void retentionActuallyRunsThroughTheTrigger() {
    String email = "trigger-retention-" + UUID.randomUUID() + "@example.com";
    UUID id = persistDormantUser(email);
    armRetentionJob();

    assertEquals(
        200, given().header(TOKEN_HEADER, VALID_TOKEN).when().post(TRIGGER_PATH).statusCode());

    User warned = reloadUser(id);
    assertNotNull(
        warned.deletionWarningSentAt,
        "the dormant account was warned by the job the trigger ran, and the warning was delivered");
    assertTrue(reloadJob().runCount > 0, "and the run was recorded");
  }

  // --- helpers ---------------------------------------------------------------------------------

  /** Makes the retention job due now, so a trigger has something to do regardless of test order. */
  private void armRetentionJob() {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              JobState state = JobState.byId(RETENTION_JOB);
              state.enabled = true;
              state.lastRunAt = null;
            });
  }

  private JobState reloadJob() {
    return QuarkusTransaction.requiringNew().call(() -> JobState.byId(RETENTION_JOB));
  }

  private UUID persistDormantUser(String email) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User user = new User();
              user.id = id;
              user.email = email;
              user.language = "en";
              user.role = UserRole.USER;
              user.createdAt = OffsetDateTime.now().minus(DORMANT_DAYS + 1, ChronoUnit.DAYS);
              user.lastLoginAt = OffsetDateTime.now().minus(DORMANT_DAYS, ChronoUnit.DAYS);
              user.persist();
            });
    return id;
  }

  private User reloadUser(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> User.findById(id));
  }
}
