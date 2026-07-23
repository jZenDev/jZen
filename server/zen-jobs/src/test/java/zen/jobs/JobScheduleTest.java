package zen.jobs;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

/**
 * The due-ness rule, proven directly. No Quarkus, no database, and no sleeping: {@link JobSchedule}
 * takes "now" as an argument precisely so that scheduling behaviour can be asserted at chosen
 * instants rather than waited for.
 *
 * <p>These are the properties ROADMAP step 7a calls the difference between a guarantee and a hope,
 * so they are tested as properties rather than as incidental behaviour of the scheduler.
 */
class JobScheduleTest {

  private static final OffsetDateTime NOW = OffsetDateTime.of(2026, 7, 22, 3, 0, 0, 0, ZoneOffset.UTC);
  private static final Duration HOURLY = Duration.ofHours(1);
  private static final Duration DAILY = Duration.ofDays(1);

  @Test
  void aJobThatHasNeverRunIsDue() {
    assertTrue(
        JobSchedule.isDue(null, DAILY, NOW),
        "a newly registered job must not have to wait out one interval before its first run");
  }

  @Test
  void aJobRunLessThanAnIntervalAgoIsNotDue() {
    assertFalse(JobSchedule.isDue(NOW.minusMinutes(59), HOURLY, NOW));
  }

  @Test
  void aJobIsDueExactlyAtTheIntervalBoundary() {
    assertTrue(
        JobSchedule.isDue(NOW.minus(HOURLY), HOURLY, NOW),
        "the boundary itself counts as due, so an hourly job called on the hour is not deferred");
  }

  /**
   * The catch-up property. The container was not alive for any of the intervening ticks, and no
   * timer fired; due-ness is read off the last run, so the backlog is noticed rather than lost.
   */
  @Test
  void aJobIsStillDueAfterManyMissedTicks() {
    assertTrue(
        JobSchedule.isDue(NOW.minusDays(9), DAILY, NOW),
        "a tick missed while scaled to zero must be caught up, not skipped");
  }

  /**
   * The other half of the catch-up rule: nine missed days is one run, not nine. Expressed here as
   * the predicate going false immediately after a single run stamps the current instant -
   * {@code JobSchedulerTest} then proves the scheduler actually behaves this way end to end.
   */
  @Test
  void oneRunClearsAnEntireBacklog() {
    OffsetDateTime longOverdue = NOW.minusDays(9);
    assertTrue(JobSchedule.isDue(longOverdue, DAILY, NOW), "overdue before the run");

    /* The scheduler stamps last_run_at with the run's start, not with lastRunAt + interval. */
    OffsetDateTime afterOneRun = NOW;
    assertFalse(
        JobSchedule.isDue(afterOneRun, DAILY, NOW),
        "a single run must satisfy the whole backlog, never queue one run per missed interval");
  }

  @Test
  void aLastRunInTheFutureIsNotDue() {
    assertFalse(
        JobSchedule.isDue(NOW.plusMinutes(5), HOURLY, NOW),
        "a clock that jumped backwards must not make a job due, only late");
  }
}
