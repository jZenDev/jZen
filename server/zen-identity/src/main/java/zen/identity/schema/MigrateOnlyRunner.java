package zen.identity.schema;

import io.quarkus.runtime.Quarkus;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import java.util.Arrays;
import java.util.List;
import org.eclipse.microprofile.config.ConfigProvider;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.flywaydb.core.Flyway;
import org.flywaydb.core.api.MigrationInfo;
import org.flywaydb.core.api.MigrationState;
import org.jboss.logging.Logger;

/**
 * Runs Flyway and exits, so that migration is an act of the deploy rather than of every boot.
 *
 * <p>In {@code %prod} the application no longer migrates or validates at start (ADR-038): that cost
 * 41 of the boot's 53 database round trips and 2 of its 4 connections, ~2,100 ms of every cold
 * start, on a runtime that is replaced roughly hourly. Instead the deploy runs <em>this image</em>
 * with {@code zen.migrate-only=true} as a one-shot Cloud Run Job, and only deploys the service once
 * that job has succeeded.
 *
 * <p><strong>The same binary, the same Flyway, the same migrations.</strong> That is the whole
 * reason this class exists instead of a Flyway CLI container: a second migration runner would be a
 * second authority and a version-drift risk against STANDARDS "Database migrations", which allows
 * exactly one. Here the runner is the one the application already carries, reading the same
 * {@code db/migration} classpath location through the same configuration.
 *
 * <p><strong>Why this lives in zen-identity.</strong> This module owns the schema baseline — every
 * application depends on it and inherits {@code V1__init_identity.sql} and the roles and policies
 * around it — so the thing that applies that baseline belongs beside it, the way the reusable
 * {@code AuthResource} does. Putting it in an app module would make every future application
 * re-implement its own deploy step, and there would be nothing to keep the implementations honest
 * with each other. The cost of the choice is stated plainly: zen-identity now declares
 * {@code quarkus-flyway}, which it always shipped migrations for without declaring the runner.
 *
 * <p><strong>Discovery is silent when it fails</strong>, so it is asserted rather than assumed.
 * Quarkus finds a CDI bean in a dependency jar only through {@code META-INF/jandex.idx}; this
 * module runs {@code jandex-maven-plugin} for that reason, and {@code MigrateOnlyWiringTest} in the
 * assembled application fails if it ever stops. Without the index this class would simply never be
 * instantiated: the job would boot, serve nothing, migrate nothing, and exit 0 — a deploy that
 * reports a successful migration it never performed.
 *
 * <p><strong>The deploy-time schema gate.</strong> Boot-time validation used to catch one case that
 * nothing else did: an image whose migration set is <em>behind</em> the database, i.e. a rollback
 * onto a newer schema. It refused to start. That protection does not disappear with it — it moves
 * here, and runs before the migration: if the database has applied migrations this image does not
 * carry, the job refuses and the deploy stops. A rollback that genuinely must proceed says so with
 * {@code zen.allow-schema-rollback=true}, and is told exactly what it is giving up.
 *
 * <p>Exit codes are distinct on purpose, because the deploy reads them and a human reads the
 * deploy: <strong>0</strong> migrated (or already up to date), <strong>1</strong> migration failed,
 * <strong>2</strong> the schema gate refused. Nothing here returns 0 on a failure; a zero would let
 * {@code deploy:cloudrun} ship a revision over a schema that was never migrated, which is the
 * swallowed failure STANDARDS forbids and is worse than the boot cost this change removes.
 */
@ApplicationScoped
public class MigrateOnlyRunner {

  /** Migrated, or there was nothing to do. */
  public static final int EXIT_OK = 0;

  /** Flyway raised. The schema is in whatever state Flyway left it; the deploy must stop. */
  public static final int EXIT_MIGRATION_FAILED = 1;

  /** The database is ahead of this image and no override was given. */
  public static final int EXIT_SCHEMA_AHEAD = 2;

  static final String MIGRATE_ONLY_PROPERTY = "zen.migrate-only";
  static final String ALLOW_SCHEMA_ROLLBACK_PROPERTY = "zen.allow-schema-rollback";
  static final String HTTP_HOST_ENABLED_PROPERTY = "quarkus.http.host-enabled";

  private static final Logger LOG = Logger.getLogger(MigrateOnlyRunner.class);

  /**
   * Lazy on purpose. Resolving the {@code Flyway} bean builds its dedicated DDL-role datasource
   * (ADR-031), and doing that at every boot would re-open at start exactly the connection this
   * change exists to remove. Nothing touches it unless the mode is on.
   */
  @Inject Instance<Flyway> flyway;

  @ConfigProperty(name = MIGRATE_ONLY_PROPERTY, defaultValue = "false")
  boolean migrateOnly;

  @ConfigProperty(name = ALLOW_SCHEMA_ROLLBACK_PROPERTY, defaultValue = "false")
  boolean allowSchemaRollback;

  /**
   * Migrates and terminates the process when the mode is on, and does nothing at all when it is
   * off — which is every serving boot.
   *
   * <p><strong>{@code Quarkus.asyncExit}, never {@code System.exit}.</strong> Measured, not
   * assumed: {@code System.exit} from a startup observer <em>deadlocks</em>. The calling thread
   * blocks in {@code Runtime.exit} waiting for the shutdown hooks, and Quarkus's own hook waits in
   * {@code Application.awaitShutdown()} for a startup that can no longer finish, so the process
   * hangs with the migration already applied — the one outcome worse than failing, because Cloud
   * Run would sit on it until the task timeout and the deploy would be waiting for a job that is
   * done. {@code asyncExit} hands the code to the thread that owns the lifecycle and lets it shut
   * down in order.
   *
   * <p>The consequence is that startup completes before the process ends, so the job also sets
   * {@code quarkus.http.host-enabled=false} to keep the HTTP server from binding — see
   * {@link #HTTP_HOST_ENABLED_PROPERTY}. That is belt and braces rather than the mechanism: the
   * termination is what matters, and it no longer depends on where in the boot this runs.
   */
  void migrateAndExit(@Observes StartupEvent event) {
    if (!migrateOnly) {
      return;
    }
    if (ConfigProvider.getConfig()
        .getOptionalValue(HTTP_HOST_ENABLED_PROPERTY, Boolean.class)
        .orElse(true)) {
      // Not fatal — the job still terminates — but it is a misconfiguration worth seeing, because
      // a migration job that serves HTTP is one firewall change away from being a service.
      LOG.warnf(
          "Migrate-only with the HTTP server enabled. Set %s=false on the migration job.",
          HTTP_HOST_ENABLED_PROPERTY);
    }
    Quarkus.asyncExit(migrate());
  }

  /**
   * Runs the gate and then the migration, and returns the exit code the process should carry.
   *
   * <p>Separated from the observer so it can be exercised without ending the test JVM.
   */
  public int migrate() {
    try {
      // Inside the try, and not above it: resolving the bean is what first touches the database,
      // so an unreachable host raises here. Left outside, that failure would leave the process no
      // way to say which of its two jobs it was doing when it died.
      Flyway runner = flyway.get();

      List<MigrationInfo> ahead = migrationsTheDatabaseHasAndThisImageDoesNot(runner);
      if (!ahead.isEmpty()) {
        LOG.errorf(
            "Schema gate: the database has applied %d migration(s) this image does not carry: %s",
            ahead.size(), describe(ahead));
        if (!allowSchemaRollback) {
          LOG.error(
              "Refusing to migrate. This is a rollback onto a newer schema: the image about to be"
                  + " deployed does not understand the schema it would serve, and nothing at boot"
                  + " will notice any more. Fix it by deploying an image at or ahead of the"
                  + " database, or proceed deliberately with "
                  + ALLOW_SCHEMA_ROLLBACK_PROPERTY
                  + "=true — which gives up the only remaining check that the running binary and"
                  + " its schema agree.");
          return EXIT_SCHEMA_AHEAD;
        }
        LOG.warnf(
            "%s=true: proceeding onto a newer schema anyway. Nothing now checks that this image"
                + " and the database agree.",
            ALLOW_SCHEMA_ROLLBACK_PROPERTY);
        // The override has to reach Flyway too, or it is not an override. migrate() validates
        // before it migrates, and the very state being overridden — applied migrations this image
        // cannot resolve — is one validate refuses. Relaxed for exactly those two states and
        // nothing else: a checksum mismatch on a migration this image DOES carry still fails, and
        // must, because that is a rewritten migration rather than a rollback.
        runner =
            Flyway.configure()
                .configuration(runner.getConfiguration())
                .ignoreMigrationPatterns("*:missing", "*:future")
                .load();
      }

      int applied = runner.migrate().migrationsExecuted;
      if (applied == 0) {
        LOG.info("Migrate-only: schema already up to date, nothing applied.");
      } else {
        LOG.infof("Migrate-only: applied %d migration(s).", applied);
      }
      return EXIT_OK;
    } catch (RuntimeException failure) {
      // Logged here rather than left to propagate: an exception out of a startup observer exits
      // non-zero too, but with a stack trace wrapped in Quarkus bootstrap failures that reads as a
      // broken image rather than a failed migration. The deploy stops either way; this says why.
      LOG.error("Migrate-only: migration FAILED. The deploy must not continue.", failure);
      return EXIT_MIGRATION_FAILED;
    }
  }

  /**
   * The rollback case, and the only thing boot-time validation caught that nothing else did.
   *
   * <p>{@code MISSING_*} is a migration applied to the database and absent from this image;
   * {@code FUTURE_*} is one applied with a version above everything this image resolves. Both mean
   * the database is ahead. Pending migrations are deliberately not consulted — being <em>behind</em>
   * the database is what a migration is for.
   */
  private static List<MigrationInfo> migrationsTheDatabaseHasAndThisImageDoesNot(Flyway runner) {
    return Arrays.stream(runner.info().all())
        .filter(
            info -> {
              MigrationState state = info.getState();
              return state == MigrationState.MISSING_SUCCESS
                  || state == MigrationState.MISSING_FAILED
                  || state == MigrationState.FUTURE_SUCCESS
                  || state == MigrationState.FUTURE_FAILED;
            })
        .toList();
  }

  private static String describe(List<MigrationInfo> migrations) {
    return migrations.stream()
        .map(
            info ->
                (info.getVersion() == null ? "R" : info.getVersion().toString())
                    + " "
                    + info.getDescription()
                    + " ("
                    + info.getState()
                    + ")")
        .reduce((a, b) -> a + ", " + b)
        .orElse("");
  }
}
