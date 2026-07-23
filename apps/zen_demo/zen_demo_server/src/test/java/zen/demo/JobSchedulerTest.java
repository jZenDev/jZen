package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import jakarta.enterprise.inject.Alternative;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.jobs.JobScheduler;
import zen.jobs.JobState;
import zen.jobs.JobStatus;
import zen.jobs.ZenJob;
import zen.proto.v1.JobTickResult;

/**
 * The scheduling guarantee, driven by a clock this test owns (ROADMAP step 7a).
 *
 * <p>Time is injected rather than read, so every property below is asserted at a chosen instant
 * instead of waited for: the suite never sleeps and never depends on how long a job took. The
 * clock, the two test jobs, and the re-entrant job are CDI alternatives enabled only by this
 * class's profile, the same mechanism {@code EmailFailureTest} uses for its unreachable mailer, so
 * no other suite sees them.
 *
 * <p>Each test sets the job rows it cares about explicitly and disables the ones it does not, so
 * the class is independent of test order and of what other suites left in the shared database.
 */
@QuarkusTest
@TestProfile(JobSchedulerTest.DrivenClockProfile.class)
class JobSchedulerTest {

  private static final String COUNTING_JOB = "test-counting";
  private static final String FAILING_JOB = "test-failing";
  private static final String REENTRANT_JOB = "test-reentrant";

  private static final Duration HOURLY = Duration.ofHours(1);
  private static final OffsetDateTime T0 =
      OffsetDateTime.of(2026, 7, 22, 3, 0, 0, 0, ZoneOffset.UTC);

  @Inject JobScheduler scheduler;

  @BeforeEach
  void resetWorld() {
    DrivenClock.set(T0);
    CountingJob.RUNS.set(0);
    FailingJob.RUNS.set(0);
    ReentrantJob.RUNS.set(0);
    ReentrantJob.NESTED.set(null);
    /* Every job off by default; each test enables exactly what it is about. The application's real
     * UserRetentionZenJob is not among them: enabling alternatives for ZenJob eliminates the
     * non-alternative beans of that type from resolution, so this profile sees these three jobs
     * and nothing else. That is why the tick counts below are exact.
     * JobTriggerResourceTest covers the real retention job over the real trigger. */
    disable(COUNTING_JOB);
    disable(FAILING_JOB);
    disable(REENTRANT_JOB);
  }

  @Test
  void aJobThatHasNeverRunIsRunOnTheFirstTick() {
    arm(COUNTING_JOB, null);

    JobTickResult result = scheduler.tick();

    assertEquals(1, result.getDue(), "a job that has never run is due immediately");
    assertEquals(1, result.getSucceeded());
    assertEquals(1, CountingJob.RUNS.get());
    assertEquals(T0.toInstant().toEpochMilli(), result.getStartedAtMs(), "the tick used our clock");

    JobState state = reload(COUNTING_JOB);
    assertEquals(T0.toInstant(), state.lastRunAt.toInstant(), "last_run_at is stamped from the clock");
    assertEquals(JobStatus.SUCCESS, state.lastStatus);
    assertEquals(1, state.runCount);
    assertEquals(0, state.failureCount);
  }

  @Test
  void aJobRunLessThanAnIntervalAgoIsNotRunAgain() {
    arm(COUNTING_JOB, T0.minusMinutes(30));

    JobTickResult result = scheduler.tick();

    assertEquals(0, result.getDue(), "half an interval is not an interval");
    assertEquals(0, CountingJob.RUNS.get());
  }

  /**
   * The property the whole step exists for. Nine hourly ticks were missed because the container was
   * scaled to zero; no timer fired for any of them. The next tick notices from {@code last_run_at}
   * alone - and runs the job <strong>once</strong>, not nine times, because these jobs reconcile
   * current state rather than replay periods.
   */
  @Test
  void ticksMissedWhileScaledToZeroAreCaughtUpExactlyOnce() {
    arm(COUNTING_JOB, T0.minusHours(9));

    JobTickResult caughtUp = scheduler.tick();

    assertEquals(1, caughtUp.getDue(), "a nine-hour-old run makes an hourly job due");
    assertEquals(1, CountingJob.RUNS.get(), "nine missed intervals is one run, never nine");
    assertEquals(
        T0.toInstant(),
        reload(COUNTING_JOB).lastRunAt.toInstant(),
        "the clock is set to the run, not advanced interval by interval through the backlog");

    JobTickResult immediatelyAfter = scheduler.tick();

    assertEquals(0, immediatelyAfter.getDue(), "one run satisfies the entire backlog");
    assertEquals(1, CountingJob.RUNS.get());
  }

  @Test
  void aDisabledJobIsNeverRunHoweverOverdue() {
    arm(COUNTING_JOB, T0.minusYears(1));
    disable(COUNTING_JOB);

    assertEquals(0, scheduler.tick().getDue(), "disabling a job stops it without a redeploy");
    assertEquals(0, CountingJob.RUNS.get());
  }

  @Test
  void aFailingJobIsRecordedAndTheRestOfTheTickStillRuns() {
    arm(FAILING_JOB, null);
    arm(COUNTING_JOB, null);

    JobTickResult result = scheduler.tick();

    assertEquals(2, result.getDue());
    assertEquals(1, result.getFailed());
    assertEquals(1, result.getSucceeded(), "one job throwing must not abort the others");
    assertEquals(1, CountingJob.RUNS.get());

    JobState failed = reload(FAILING_JOB);
    assertEquals(JobStatus.FAILURE, failed.lastStatus);
    assertEquals(1, failed.failureCount);
    assertNotNull(failed.lastError, "the failure detail is recorded for an operator to read");
    assertTrue(
        result.getRunsList().stream()
            .anyMatch(run -> FAILING_JOB.equals(run.getJobId()) && !run.getError().isEmpty()),
        "and is reported back to the caller of the trigger");
  }

  /**
   * A failure does not leave the job spinning: {@code last_run_at} records that it ran, not that it
   * succeeded, so a broken job waits out its interval instead of retrying on every tick and
   * hammering whatever broke it.
   */
  @Test
  void aFailedJobWaitsOutItsIntervalBeforeRetrying() {
    arm(FAILING_JOB, null);
    scheduler.tick();
    assertEquals(1, FailingJob.RUNS.get());

    assertEquals(0, scheduler.tick().getDue(), "not retried immediately");

    DrivenClock.set(T0.plus(HOURLY));
    assertEquals(1, scheduler.tick().getDue(), "retried once its interval has elapsed");
    assertEquals(2, FailingJob.RUNS.get());
  }

  /**
   * The overlap guard, proven without threads: the job re-enters the scheduler from inside its own
   * run, which is exactly the state a second concurrent trigger would find.
   */
  @Test
  void aTickArrivingWhileOneIsRunningDoesNothingAndSaysSo() {
    arm(REENTRANT_JOB, null);

    JobTickResult outer = scheduler.tick();

    assertFalse(outer.getSkippedOverlap(), "the first tick runs normally");
    assertEquals(1, ReentrantJob.RUNS.get());

    JobTickResult nested = ReentrantJob.NESTED.get();
    assertNotNull(nested, "the job did re-enter the scheduler");
    assertTrue(nested.getSkippedOverlap(), "the overlapping tick is refused");
    assertEquals(0, nested.getDue(), "and runs nothing");
    assertEquals(1, ReentrantJob.RUNS.get(), "so the job is not re-entered");
  }

  // --- helpers ---------------------------------------------------------------------------------

  /** Enables a job at the hourly interval with the given last run, creating nothing new. */
  private void arm(String id, OffsetDateTime lastRunAt) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              JobState state = JobState.byId(id);
              state.enabled = true;
              state.intervalSeconds = HOURLY.toSeconds();
              state.lastRunAt = lastRunAt;
              state.lastStatus = null;
              state.lastError = null;
              state.runCount = 0;
              state.failureCount = 0;
            });
  }

  private void disable(String id) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              JobState state = JobState.byId(id);
              state.enabled = false;
            });
  }

  private JobState reload(String id) {
    return QuarkusTransaction.requiringNew().call(() -> JobState.byId(id));
  }

  /** Enables the driven clock and the three test jobs for this class only. */
  public static class DrivenClockProfile implements QuarkusTestProfile {
    @Override
    public Set<Class<?>> getEnabledAlternatives() {
      return Set.of(DrivenClock.class, CountingJob.class, FailingJob.class, ReentrantJob.class);
    }
  }

  /**
   * A clock the test moves by hand. It replaces the framework's {@code JobClock} producer, which is
   * why {@code Clock} is injected there rather than called statically.
   */
  @Alternative
  @Singleton
  public static class DrivenClock {

    private static final AtomicReference<Instant> NOW = new AtomicReference<>(T0.toInstant());

    static void set(OffsetDateTime instant) {
      NOW.set(instant.toInstant());
    }

    @Produces
    @Singleton
    public Clock drivenClock() {
      return new Clock() {
        @Override
        public ZoneId getZone() {
          return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
          return this;
        }

        @Override
        public Instant instant() {
          return NOW.get();
        }
      };
    }
  }

  /** A job that does nothing but count, so "did it run, and how often" is directly observable. */
  @Alternative
  @Singleton
  public static class CountingJob implements ZenJob {
    static final AtomicInteger RUNS = new AtomicInteger();

    @Override
    public String id() {
      return COUNTING_JOB;
    }

    @Override
    public Duration defaultInterval() {
      return HOURLY;
    }

    @Override
    public void run() {
      RUNS.incrementAndGet();
    }
  }

  /** A job that always throws, standing in for any dependency being down. */
  @Alternative
  @Singleton
  public static class FailingJob implements ZenJob {
    static final AtomicInteger RUNS = new AtomicInteger();

    @Override
    public String id() {
      return FAILING_JOB;
    }

    @Override
    public Duration defaultInterval() {
      return HOURLY;
    }

    @Override
    public void run() {
      RUNS.incrementAndGet();
      throw new IllegalStateException("job dependency unavailable");
    }
  }

  /** A job that triggers a second tick from inside the first, to expose the overlap guard. */
  @Alternative
  @Singleton
  public static class ReentrantJob implements ZenJob {
    static final AtomicInteger RUNS = new AtomicInteger();
    static final AtomicReference<JobTickResult> NESTED = new AtomicReference<>();

    @Inject JobScheduler scheduler;

    @Override
    public String id() {
      return REENTRANT_JOB;
    }

    @Override
    public Duration defaultInterval() {
      return HOURLY;
    }

    @Override
    public void run() {
      RUNS.incrementAndGet();
      NESTED.set(scheduler.tick());
    }
  }
}
