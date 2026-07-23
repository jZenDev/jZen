package zen.jobs;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import java.time.Clock;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import org.jboss.logging.Logger;
import zen.proto.v1.JobRun;
import zen.proto.v1.JobTickResult;

/**
 * The master tick: one call runs every job that is due.
 *
 * <p>Batched deliberately, for a cost reason: N scheduler
 * entries would mean N container starts, which fights the single-instance, scale-to-zero model in
 * STANDARDS "Deployment model". One external entry hits {@link JobTriggerResource}, this class
 * reads the enabled jobs, decides which are due from their persisted {@code last_run_at}, and runs
 * them <em>sequentially</em> - no fan-out, no hidden concurrency.
 *
 * <p>Each job's outcome is committed in its own short transaction, and the job body itself runs
 * outside any transaction, so a slow job never holds one open. A job that throws is recorded as
 * failed and does not stop the rest of the tick; it is retried at its next due moment rather than
 * on the very next tick, because {@code last_run_at} records that the job <em>ran</em>, not that it
 * succeeded. Retrying a broken job every minute would hammer whatever dependency broke it, and
 * every {@link ZenJob} is idempotent by contract, so a skipped interval is caught up rather than
 * lost.
 *
 * <p><strong>Overlap guard.</strong> A second tick arriving while one is running does nothing and
 * says so. An in-process flag is sufficient here for exactly the reason in-process rate limiting
 * is: at most one instance ever runs ({@code --max-instances=1}). Raising max-instances above 1 is
 * the trigger to replace this with a Postgres advisory lock - the same rule, and the same trigger,
 * that STANDARDS already states for in-process state.
 */
@ApplicationScoped
public class JobScheduler {

  private static final Logger LOG = Logger.getLogger(JobScheduler.class);

  /** Held for the duration of a tick; a concurrent tick returns immediately rather than queueing. */
  private final AtomicBoolean ticking = new AtomicBoolean();

  private final Instance<ZenJob> jobs;
  private final Clock clock;

  @Inject
  public JobScheduler(Instance<ZenJob> jobs, Clock clock) {
    this.jobs = jobs;
    this.clock = clock;
  }

  /**
   * Seeds a row for every registered job that does not have one yet. Existing rows are left
   * untouched: once a job exists, the database owns its schedule and its enabled flag, so an
   * operator's change survives the next deploy.
   */
  void seedRegisteredJobs(@Observes StartupEvent startup) {
    Map<String, ZenJob> registry = registry();
    QuarkusTransaction.requiringNew()
        .run(
            () ->
                registry.forEach(
                    (id, job) -> {
                      if (JobState.byId(id) != null) {
                        return;
                      }
                      JobState state = new JobState();
                      state.id = id;
                      state.enabled = true;
                      state.intervalSeconds = job.defaultInterval().toSeconds();
                      state.persist();
                      LOG.infof(
                          "Registered job '%s', first run due immediately, then every %s",
                          id, job.defaultInterval());
                    }));
  }

  /**
   * Runs every enabled, registered job whose interval has elapsed since its last run.
   *
   * @return what was due and what happened to it, for the trigger's caller and for the logs
   */
  public JobTickResult tick() {
    OffsetDateTime startedAt = OffsetDateTime.now(clock);
    if (!ticking.compareAndSet(false, true)) {
      LOG.info("Job tick skipped: a tick is already running");
      return JobTickResult.newBuilder()
          .setStartedAtMs(startedAt.toInstant().toEpochMilli())
          .setSkippedOverlap(true)
          .build();
    }
    try {
      return runDueJobs(startedAt);
    } finally {
      ticking.set(false);
    }
  }

  private JobTickResult runDueJobs(OffsetDateTime startedAt) {
    Map<String, ZenJob> registry = registry();
    List<JobState> due = dueJobs(registry, startedAt);

    JobTickResult.Builder result =
        JobTickResult.newBuilder()
            .setStartedAtMs(startedAt.toInstant().toEpochMilli())
            .setDue(due.size());

    int succeeded = 0;
    int failed = 0;
    for (JobState state : due) {
      JobRun run = runOne(registry.get(state.id), state.id);
      result.addRuns(run);
      if (JobStatus.SUCCESS.wireValue().equals(run.getStatus())) {
        succeeded++;
      } else {
        failed++;
      }
    }
    if (!due.isEmpty()) {
      LOG.infof("Job tick ran %d due job(s): %d succeeded, %d failed", due.size(), succeeded, failed);
    }
    return result.setSucceeded(succeeded).setFailed(failed).build();
  }

  /** Reads the enabled rows and keeps the ones that are both registered in this build and due. */
  private List<JobState> dueJobs(Map<String, ZenJob> registry, OffsetDateTime now) {
    return QuarkusTransaction.requiringNew()
        .call(
            () -> {
              List<JobState> selected = new ArrayList<>();
              for (JobState state : JobState.enabled()) {
                if (!registry.containsKey(state.id)) {
                  /* A row left behind by a job this build no longer ships. Not an error: the row
                   * is the operator's, and deleting it here would destroy their configuration. */
                  LOG.debugf("Ignoring job row '%s': no ZenJob with that id is registered", state.id);
                  continue;
                }
                if (JobSchedule.isDue(state.lastRunAt, state.interval(), now)) {
                  selected.add(state);
                }
              }
              return selected;
            });
  }

  /** Runs one job outside a transaction, then records its outcome inside its own. */
  private JobRun runOne(ZenJob job, String id) {
    OffsetDateTime startedAt = OffsetDateTime.now(clock);
    /* Stamped before the body runs, and kept whatever the outcome: last_run_at means "last ran".
     * A job that throws therefore waits out its interval instead of being retried on every tick,
     * which is what stops a broken job from hammering whatever broke it. */
    recordStart(id, startedAt);

    String error = null;
    try {
      job.run();
    } catch (RuntimeException e) {
      error = e.toString();
      LOG.errorf(e, "Job '%s' failed", id);
    }

    long durationMs = Duration.between(startedAt, OffsetDateTime.now(clock)).toMillis();
    JobStatus status = error == null ? JobStatus.SUCCESS : JobStatus.FAILURE;
    recordOutcome(id, status, durationMs, error);

    JobRun.Builder run =
        JobRun.newBuilder()
            .setJobId(id)
            .setStatus(status.wireValue())
            .setStartedAtMs(startedAt.toInstant().toEpochMilli())
            .setDurationMs(durationMs);
    if (error != null) {
      run.setError(error);
    }
    return run.build();
  }

  private void recordStart(String id, OffsetDateTime startedAt) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              JobState state = JobState.byId(id);
              state.lastRunAt = startedAt;
              state.runCount++;
            });
  }

  private void recordOutcome(String id, JobStatus status, long durationMs, String error) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              JobState state = JobState.byId(id);
              state.lastStatus = status;
              state.lastDurationMs = durationMs;
              state.lastError = error;
              if (status == JobStatus.FAILURE) {
                state.failureCount++;
              }
            });
  }

  /** The jobs this build ships, keyed by id. Duplicate ids are a wiring bug, so they are fatal. */
  private Map<String, ZenJob> registry() {
    Map<String, ZenJob> registry = new LinkedHashMap<>();
    for (ZenJob job : jobs) {
      ZenJob previous = registry.put(job.id(), job);
      if (previous != null) {
        throw new IllegalStateException(
            "Two ZenJob beans share the id '"
                + job.id()
                + "': "
                + previous.getClass().getName()
                + " and "
                + job.getClass().getName());
      }
    }
    return registry;
  }
}
