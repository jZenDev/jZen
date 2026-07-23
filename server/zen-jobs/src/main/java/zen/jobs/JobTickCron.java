package zen.jobs;

import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;

/**
 * Drives {@link JobScheduler#tick()} from an in-process cron, for local development only.
 *
 * <p>It exists so that working on jZen needs no Google Cloud account: with the cron on, a developer
 * sees jobs run exactly as they will in production, because this fires <em>the same</em> tick the
 * external trigger fires. Dev and prod differ in who pulls the trigger, not in what happens next.
 *
 * <p><strong>Off by default, and pinned off in {@code %prod}.</strong> Under
 * {@code --min-instances=0} the container exists only while it is serving a request, so a cron here
 * has no thread alive at the hour it names: it usually does not fire, and when it does that is an
 * accident of traffic rather than a schedule (STANDARDS "Deployment model"). In production the
 * trigger is external, which also wakes the instance.
 */
@ApplicationScoped
public class JobTickCron {

  private final JobScheduler scheduler;

  @Inject
  public JobTickCron(JobScheduler scheduler) {
    this.scheduler = scheduler;
  }

  @Scheduled(cron = "{zen.jobs.tick.cron}", identity = "zen-jobs-tick")
  void tick() {
    scheduler.tick();
  }
}
