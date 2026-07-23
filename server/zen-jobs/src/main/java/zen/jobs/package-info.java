/**
 * Guaranteed scheduled work: an external scheduler calls one authenticated endpoint, and the
 * framework runs whatever is due.
 *
 * <p>The module exists because jZen's deployment model makes in-process time invalid. Cloud Run
 * runs {@code --min-instances=0}, so a container exists only while it is serving a request and a
 * {@code @Scheduled} cron has no thread alive at the hour it names (STANDARDS "Deployment model").
 * Everything here follows from that one fact:
 *
 * <ul>
 *   <li>{@link zen.jobs.JobTriggerResource} is the outside world's way in, guarded by a shared
 *       secret ({@link zen.jobs.JobTriggerAuthenticator}) because the service is served
 *       {@code --allow-unauthenticated}.
 *   <li>{@link zen.jobs.JobScheduler} runs the due jobs sequentially and records each outcome.
 *   <li>{@link zen.jobs.JobSchedule} holds the rule that makes the whole thing a guarantee:
 *       due-ness comes from the persisted last run, never from a timer having fired.
 *   <li>{@link zen.jobs.JobState} is that persisted state, so a schedule changes without a redeploy.
 *   <li>{@link zen.jobs.ZenJob} is all an application implements.
 * </ul>
 *
 * <p>Re-engineered from ../DartZen/packages/dartzen_jobs, keeping its master-tick batching and its
 * persisted job config, and dropping its Firestore store, its Cloud Tasks adapter, and the job
 * features nothing calls yet. See DECISIONS ADR-008.
 */
package zen.jobs;
