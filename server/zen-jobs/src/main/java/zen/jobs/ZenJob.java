package zen.jobs;

import java.time.Duration;

/**
 * A unit of scheduled work. Implement this as a CDI bean and the framework discovers it, seeds its
 * row in {@code zen_jobs}, and runs it whenever it is due.
 *
 * <p><strong>The body stays a plain callable.</strong> {@link #run()} is an ordinary method with no
 * scheduling annotation on it, so whether the work is triggered by an external scheduler, by the
 * {@code %dev} in-process tick, or by a test is a deployment choice rather than a code one
 * (STANDARDS "Deployment model"). {@code UserRetentionJob.runCycle()} was already written this way
 * and is the first registered job.
 *
 * <p><strong>Every job must be idempotent.</strong> An external scheduler delivers at-least-once
 * and jZen never suppresses a retry, so running twice in a row must be harmless. This is a contract,
 * not an aspiration: {@code JobSchedulerTest} asserts it for the shipped job.
 *
 * <p>Only the <em>defaults</em> live in code. {@link #defaultInterval()} seeds the row the first
 * time a job is seen; after that the database owns the schedule and the enabled flag, so an
 * operator changes a cadence or stops a job with an UPDATE rather than a redeploy - the one
 * property of the donor's persisted job config worth keeping
 * (../DartZen/packages/dartzen_jobs/lib/src/models/job_config.dart:12-17).
 */
public interface ZenJob {

  /**
   * Stable identifier, unique per application. It is the primary key of the {@code zen_jobs} row
   * and the handle an operator uses, so it outlives refactoring of the implementing class.
   */
  String id();

  /**
   * How long after a completed run this job becomes due again. Used only to seed the row; the
   * persisted value wins on every later tick.
   */
  Duration defaultInterval();

  /**
   * Performs the work. Runs outside any transaction - a job that needs one opens its own, so a
   * long job never holds a database transaction open across, say, an SMTP conversation.
   *
   * <p>Throwing marks the run failed and is recorded; it does not stop the other due jobs in the
   * same tick. The failed job is retried at its next due moment rather than on the next tick, so a
   * job whose dependency is down does not hammer it - which is safe precisely because this method
   * is required to be idempotent.
   */
  void run();
}
