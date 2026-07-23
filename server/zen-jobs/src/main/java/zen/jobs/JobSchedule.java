package zen.jobs;

import java.time.Duration;
import java.time.OffsetDateTime;

/**
 * The due-ness rule, as a pure function. This is the whole point of {@code zen-jobs}, so it is
 * kept free of CDI, JDBC, and wall-clock reads: every input is an argument and the result depends
 * on nothing else, which is what lets {@code JobScheduleTest} prove the behaviour without a
 * database, a scheduler, or a sleep.
 *
 * <h2>Due-ness is computed from the last run, never from "the timer fired"</h2>
 *
 * A job is due when the recorded completion of its previous run is at least one interval old.
 * Nothing here observes ticks, so a tick that never happened - because Cloud Run had scaled to
 * zero, because a deploy was in flight, or because the scheduler itself was down - costs nothing:
 * the next tick sees a stale {@code lastRunAt} and the job is still due. That is the difference
 * between a guarantee and a hope, and it is why the GDPR retention cycle can rest on it.
 *
 * <h2>Missed ticks coalesce: a due job runs once, not once per interval</h2>
 *
 * If a job with a one-hour interval was last run six hours ago, the next tick runs it exactly
 * once and stamps {@code lastRunAt} with that run's start - it does not run six times catching up,
 * and it does not advance the clock in interval-sized steps. jZen's jobs are reconciliations over
 * current state ("anonymise every account whose final warning has expired"), not per-period
 * batches, so replaying a backlog would repeat identical work. This is the framework contract for
 * every {@link ZenJob}, stated once here.
 */
public final class JobSchedule {

  private JobSchedule() {}

  /**
   * Decides whether a job may run now.
   *
   * @param lastRunAt when the job last started, or {@code null} if it has never run
   * @param interval how long after a run the job becomes due again
   * @param now the reference instant, supplied by the caller's clock
   * @return {@code true} when the job has never run, or when a full interval has elapsed
   */
  public static boolean isDue(OffsetDateTime lastRunAt, Duration interval, OffsetDateTime now) {
    if (lastRunAt == null) {
      /* Never run: due immediately, so a newly registered job does not wait out one interval. */
      return true;
    }
    /* Due at the boundary itself, not one instant later: `not after` rather than `before`. */
    return !lastRunAt.plus(interval).isAfter(now);
  }
}
