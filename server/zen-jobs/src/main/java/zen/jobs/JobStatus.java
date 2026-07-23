package zen.jobs;

/**
 * Terminal outcome of one job run, persisted in {@code zen_jobs.last_status} and echoed in the
 * {@code JobRun} proto.
 *
 * <p>Two values only. jZen has no job dependencies, skip dates, or start/end windows, so there
 * are no "skipped" outcomes to record: a status that can never be written is not a status.
 */
public enum JobStatus {
  /** The job returned normally. */
  SUCCESS,
  /** The job threw. The failure is recorded and the job stays due. */
  FAILURE;

  /** Lower-case wire form, as carried by the {@code JobRun} proto's {@code status} field. */
  public String wireValue() {
    return name().toLowerCase();
  }
}
