package zen.identity.schema;

import io.quarkus.runtime.Quarkus;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import javax.sql.DataSource;
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
 * <p><strong>The Data API exposure gate.</strong> Runs after a successful migration, on the same
 * DDL-credentialed connection: it asserts the OUTCOME {@code R__identity_data_api_lockdown.sql}
 * exists to guarantee, rather than trusting that file's revoke still applies to whoever creates or
 * grants on tables now. See {@link #dataApiExposure(Flyway)} for why a repeatable migration's
 * checksum-triggered re-run cannot be relied on for this (F10 of the 2026-08-13 architectural
 * security review; ADR-041).
 *
 * <p><strong>It asserts what a migration role can actually deliver, and warns about the rest.</strong>
 * Two things are fatal: an existing public-schema table that grants {@code anon} or
 * {@code authenticated} something, and a default-privilege grant belonging to a role this
 * connection is a member of — the second being F10's case, a rotated DDL role whose defaults the
 * lockdown never re-revoked. A default-privilege grant belonging to a role it is NOT a member of
 * is warned about every deploy and does not block: {@code ALTER DEFAULT PRIVILEGES} requires
 * membership, so no migration here can clear it, and treating it as fatal would wedge the deploy
 * path on every Supabase project (stock projects ship exactly this for {@code supabase_admin}).
 * That residual is real and is covered by per-table row-level security, ADR-036's second layer —
 * it is named in the log rather than asserted here.
 *
 * <p>Exit codes are distinct on purpose, because the deploy reads them and a human reads the
 * deploy: <strong>0</strong> migrated (or already up to date), <strong>1</strong> migration failed,
 * <strong>2</strong> the schema gate refused, <strong>3</strong> the Data API exposure gate found a
 * grant it could have revoked and did not. Nothing here returns 0 on a failure; a zero would let
 * {@code deploy:cloudrun} ship a revision over a schema that was never migrated, or one where a
 * public table is reachable through the Data API, which is the swallowed failure STANDARDS
 * forbids and is worse than the boot cost this change removes.
 */
@ApplicationScoped
public class MigrateOnlyRunner {

  /** Migrated, or there was nothing to do. */
  public static final int EXIT_OK = 0;

  /** Flyway raised. The schema is in whatever state Flyway left it; the deploy must stop. */
  public static final int EXIT_MIGRATION_FAILED = 1;

  /** The database is ahead of this image and no override was given. */
  public static final int EXIT_SCHEMA_AHEAD = 2;

  /**
   * A public-schema object still grants {@code anon} or {@code authenticated} something after
   * migration. See {@link #dataApiExposure(Flyway)}.
   */
  public static final int EXIT_DATA_API_EXPOSED = 3;

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

      List<String> exposed = dataApiExposure(runner);
      if (!exposed.isEmpty()) {
        LOG.errorf(
            "Data API exposure check: %d public-schema grant(s) still reach anon/authenticated"
                + " after migration: %s",
            exposed.size(), String.join("; ", exposed));
        LOG.error(
            "Refusing to deploy. R__identity_data_api_lockdown.sql's revoke did not hold for"
                + " whoever is creating or granting on public-schema objects now — either the DDL"
                + " role has rotated since that file last ran (it only re-runs on checksum"
                + " change, which a role rotation does not touch), or a grant was restored by"
                + " hand. See STANDARDS \"Database migrations\" and ADR-041.");
        return EXIT_DATA_API_EXPOSED;
      }
      return EXIT_OK;
    } catch (RuntimeException | SQLException failure) {
      // Logged here rather than left to propagate: an exception out of a startup observer exits
      // non-zero too, but with a stack trace wrapped in Quarkus bootstrap failures that reads as a
      // broken image rather than a failed migration. The deploy stops either way; this says why.
      LOG.error("Migrate-only: migration FAILED. The deploy must not continue.", failure);
      return EXIT_MIGRATION_FAILED;
    }
  }

  /**
   * Asserts the Data API lockdown's OUTCOME instead of trusting that its cause still applies
   * (F10 of the 2026-08-13 architectural security review; ADR-041).
   * {@code R__identity_data_api_lockdown.sql} revokes {@code anon}/{@code authenticated}
   * privileges for whichever role was {@code current_user} the moment it last ran — a repeatable
   * migration only re-runs on checksum change, and rotating the DDL role does not touch that
   * checksum. So a table created by a rotated role, or a grant restored by hand outside these
   * migrations (the file's own documented gap: a table created via the Supabase dashboard's
   * table editor, which runs as {@code supabase_admin}), can sit exposed while Flyway reports a
   * clean history. This queries what actually holds today rather than re-deriving it.
   *
   * <p>Runs once per deploy, on the DDL credentials {@link #migrate()} already has open — not
   * once per boot, which would reopen at every start exactly the connection ADR-038 removed.
   *
   * <p>Guarded on the {@code anon} role existing, the same way the SQL file is, so this is a
   * no-op against the plain Postgres Dev Services provisions for {@code @QuarkusTest}.
   */
  private static List<String> dataApiExposure(Flyway runner) throws SQLException {
    DataSource dataSource = runner.getConfiguration().getDataSource();
    try (Connection connection = dataSource.getConnection()) {
      if (!roleExists(connection, "anon")) {
        return List.of();
      }
      List<String> unreachable = futureGrants(connection, false);
      if (!unreachable.isEmpty()) {
        LOG.warnf(
            "Data API residual, not a deploy blocker: %d default-privilege grant(s) belong to"
                + " role(s) this migration role is not a member of, so no migration here can"
                + " revoke them: %s. A table created BY one of those roles — the Supabase"
                + " dashboard's table editor is the usual way — is exposed to the Data API on"
                + " creation, and per-table row-level security is what covers it (ADR-036's"
                + " second layer). Clearing this needs an operator with membership in that role,"
                + " or the project setting that stops exposing public through the Data API"
                + " (deploy:cloudrun ONE-TIME SETUP step 1d).",
            unreachable.size(), String.join("; ", unreachable));
      }
      List<String> exposed = new ArrayList<>(existingGrants(connection));
      exposed.addAll(futureGrants(connection, true));
      return exposed;
    }
  }

  private static boolean roleExists(Connection connection, String role) throws SQLException {
    try (PreparedStatement statement =
        connection.prepareStatement("SELECT 1 FROM pg_roles WHERE rolname = ?")) {
      statement.setString(1, role);
      try (ResultSet resultSet = statement.executeQuery()) {
        return resultSet.next();
      }
    }
  }

  /** Objects that already exist in {@code public} and currently grant anon/authenticated something. */
  private static List<String> existingGrants(Connection connection) throws SQLException {
    String sql =
        "SELECT table_name, grantee, privilege_type FROM information_schema.role_table_grants"
            + " WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated')";
    List<String> found = new ArrayList<>();
    try (PreparedStatement statement = connection.prepareStatement(sql);
        ResultSet resultSet = statement.executeQuery()) {
      while (resultSet.next()) {
        found.add(
            resultSet.getString("table_name")
                + " grants "
                + resultSet.getString("privilege_type")
                + " to "
                + resultSet.getString("grantee"));
      }
    }
    return found;
  }

  /**
   * Default privileges that would still hand a newly created table to {@code anon} —
   * <strong>split by whether this role could have done anything about them</strong>, which is the
   * difference between drift and the standing residual.
   *
   * <p>{@code ALTER DEFAULT PRIVILEGES FOR ROLE X} requires membership in X. So a default-ACL
   * belonging to a role the migration role is not a member of is not something
   * {@code R__identity_data_api_lockdown.sql} failed to revoke — it is something that file
   * documents it <em>cannot</em> revoke, and says so in its own header. On a stock Supabase
   * project that is exactly {@code supabase_admin}, which owns default privileges on tables,
   * sequences and functions and is what the dashboard's table editor creates as.
   *
   * <p><strong>Why this distinction is the gate rather than a detail.</strong> Without it the
   * check asserts an outcome no migration role can produce, so it fails every deploy on every
   * Supabase project forever — and since exit 3 has no override by design, it would wedge the
   * deploy path permanently while reporting a condition nobody can clear. A gate that cannot pass
   * teaches people to bypass gates. The first deploy after ADR-041 hit exactly this.
   *
   * <p>So: {@code pg_has_role(current_user, defaclrole, 'USAGE')} splits the two. Reachable roles
   * still granting anon/authenticated are drift and are fatal — that is F10's actual case, a DDL
   * role whose defaults this file's checksum-triggered re-run never revoked. Unreachable roles are
   * returned separately and WARNED about, loudly and every deploy, naming the residual rather than
   * hiding it: per-table row-level security is the layer that covers a table created that way
   * (ADR-036's second layer, STANDARDS "Database migrations"), and it is asserted by the
   * {@code R__*_row_level_security.sql} files rather than here.
   *
   * <p>A text match on the ACL array is enough: this only has to answer "is anon or authenticated
   * named at all", not parse the ACL.
   *
   * @param reachable when true, return only roles this connection could alter (fatal drift); when
   *     false, only those it could not (the warned residual)
   */
  private static List<String> futureGrants(Connection connection, boolean reachable)
      throws SQLException {
    String sql =
        "SELECT defaclrole::regrole::text AS creator, defaclacl::text AS acl FROM pg_default_acl"
            + " WHERE defaclnamespace = 'public'::regnamespace"
            + " AND (defaclacl::text LIKE '%anon=%' OR defaclacl::text LIKE '%authenticated=%')"
            + " AND pg_has_role(current_user, defaclrole, 'USAGE') = ?";
    List<String> found = new ArrayList<>();
    try (PreparedStatement statement = connection.prepareStatement(sql)) {
      statement.setBoolean(1, reachable);
      try (ResultSet resultSet = statement.executeQuery()) {
        while (resultSet.next()) {
          found.add(
              "default privileges for role "
                  + resultSet.getString("creator")
                  + " still grant anon/authenticated: "
                  + resultSet.getString("acl"));
        }
      }
    }
    return found;
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
