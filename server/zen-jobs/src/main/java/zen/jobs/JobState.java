package zen.jobs;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.List;

/**
 * The persisted state of one job: its schedule, whether it is enabled, and what happened last
 * time. Active-record Panache, like every other jZen entity (BLUEPRINT "Persistence").
 *
 * <p>State is persisted rather than compiled in for the reason the donor gives
 * (../DartZen/packages/dartzen_jobs/lib/src/models/job_config.dart:12-17): a schedule change or an
 * emergency stop must not need a redeploy. The row is seeded from the {@link ZenJob}'s defaults
 * the first time the job is seen and is owned by the database from then on.
 *
 * <p>{@code lastRunAt} is the field the whole design rests on - see {@link JobSchedule}. It records
 * when a run <em>started</em>, so a long job cannot become due again while it is still running.
 */
@Entity
@Table(name = "zen_jobs")
public class JobState extends PanacheEntityBase {

  /** The {@link ZenJob#id()} this row belongs to. */
  @Id public String id;

  /** Whether the scheduler may run this job. Flipping this to false stops it without a redeploy. */
  @Column(nullable = false)
  public boolean enabled;

  /** Interval between runs, stored in seconds so the column stays trivially readable in SQL. */
  @Column(name = "interval_seconds", nullable = false)
  public long intervalSeconds;

  /** When the last run started; {@code null} until the job has run once. */
  @Column(name = "last_run_at")
  public OffsetDateTime lastRunAt;

  /** Outcome of the last run; {@code null} until the job has run once. */
  @Enumerated(EnumType.STRING)
  @Column(name = "last_status")
  public JobStatus lastStatus;

  /** Wall-clock duration of the last run, in milliseconds. */
  @Column(name = "last_duration_ms")
  public Long lastDurationMs;

  /** Failure detail from the last run; cleared on the next success. */
  @Column(name = "last_error")
  public String lastError;

  /** How many times this job has run, successfully or not. */
  @Column(name = "run_count", nullable = false)
  public long runCount;

  /** How many of those runs failed. */
  @Column(name = "failure_count", nullable = false)
  public long failureCount;

  /** The persisted schedule, which always wins over the {@link ZenJob}'s compiled-in default. */
  public Duration interval() {
    return Duration.ofSeconds(intervalSeconds);
  }

  /** Looks up a single job's row by its {@link ZenJob#id()}. */
  public static JobState byId(String id) {
    return findById(id);
  }

  /** Every enabled row, ordered by id so a tick's execution order is stable and reproducible. */
  public static List<JobState> enabled() {
    return list("enabled = true order by id");
  }
}
