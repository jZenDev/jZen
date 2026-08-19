package zen.jobs;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import org.junit.jupiter.api.Test;

/**
 * The inert-deployment predicate, proven without a server (issue #65). {@code
 * JobScheduler.seedRegisteredJobs} touches a transaction and CDI, but the decision of whether to
 * warn is a pure function of two facts the startup observer already has, so it is fixed here
 * directly rather than through a boot.
 */
class JobSchedulerInertnessTest {

  @Test
  void registeredJobsWithNoTokenIsInert() {
    assertTrue(
        JobScheduler.isInert(3, Optional.empty()),
        "jobs registered but no token means none of them can ever run");
  }

  @Test
  void registeredJobsWithABlankTokenIsInert() {
    assertTrue(
        JobScheduler.isInert(1, Optional.of("   ")),
        "a blank token is treated the same as an absent one everywhere else in zen-jobs");
  }

  @Test
  void registeredJobsWithATokenIsNotInert() {
    assertFalse(JobScheduler.isInert(2, Optional.of("s3cret-trigger-token")));
  }

  @Test
  void noRegisteredJobsIsNeverInertRegardlessOfToken() {
    assertFalse(
        JobScheduler.isInert(0, Optional.empty()),
        "an app that assembles zen-jobs but registers no ZenJob has nothing to warn about");
  }
}
