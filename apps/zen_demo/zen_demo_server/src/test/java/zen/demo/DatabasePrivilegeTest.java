package zen.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Proves what the {@code zen_runtime} role created by {@code R__identity_application_role.sql}
 * can and cannot reach — by connecting as it and trying, not by reading the migration.
 *
 * <p>The migration is the security control, so an assertion over its text would prove only that the
 * text is what it is. Everything here runs real SQL over a real connection opened as
 * {@code zen_runtime} against the Dev Services database the rest of the suite uses.
 *
 * <p>Two things the test has to supply that production does not, and both are honest about what
 * they stand in for:
 *
 * <ul>
 *   <li><b>A login.</b> The migration deliberately creates the role {@code NOLOGIN} and without a
 *       password — a credential in a migration would be plaintext in git, readable by everyone
 *       who can read the repository. Production's is provisioned by an operator
 *       (deploy:cloudrun step 1c); this test grants a throwaway one to the same role and takes it
 *       away again.
 *   <li><b>An {@code auth} schema.</b> Dev Services provisions plain PostgreSQL, which has none —
 *       and the whole point of the split is what happens to Supabase's {@code auth.users} when the
 *       application's own schema is compromised. The setup below creates a stand-in and seeds it,
 *       so "denied" is a denial of something that is genuinely there to read.
 * </ul>
 *
 * <p>Note what the suite as a whole does <em>not</em> cover: the application itself still connects
 * as the Dev Services owner under {@code %test}, because Dev Services generates those credentials
 * and there is nothing to point at {@code zen_runtime}. The split is exercised here, on the
 * privileges, not end to end through the resources.
 *
 * <p>Since ADR-036 it also covers the <b>other</b> side of the same schema: the Supabase Data API
 * roles {@code anon} and {@code authenticated}, which reach {@code public} over PostgREST with a key
 * Supabase publishes on purpose. Those roles need a third stand-in for the same reason the
 * {@code auth} schema does — Dev Services has neither — and the setup below grants them exactly what
 * Supabase's default privileges grant, so what the lockdown migration then takes away is a real
 * privilege rather than an absence dressed up as a denial.
 */
@QuarkusTest
class DatabasePrivilegeTest {

  /** Fixed by the migration; jZen ships one runtime role the way it ships one users table. */
  private static final String APP_ROLE = "zen_runtime";

  /** Throwaway, and revoked in teardown. Never leaves the Dev Services container. */
  private static final String APP_PASSWORD = "zen_runtime_test_only";

  /** PostgreSQL's SQLSTATE for insufficient_privilege — what every refusal below must be. */
  private static final String INSUFFICIENT_PRIVILEGE = "42501";

  /**
   * The Supabase Data API roles. Fixed names on every Supabase project: PostgREST connects as
   * {@code authenticator} and switches to one of these two depending on whether the request carried
   * a JWT, so they are the identities an anon key actually reaches the database as.
   */
  private static final String[] DATA_API_ROLES = {"anon", "authenticated"};

  /** The seeded job and rate-limit rows, so a refusal is a refusal of something that is there. */
  private static final String SEEDED_JOB = "privilege-test-job";

  private static final String SEEDED_BUCKET = "privilege-test-bucket";

  @Inject DataSource dataSource;

  private String jdbcUrl;
  private UUID seededUser;

  @BeforeEach
  void grantAThrowawayLoginAndSeedTheDatabase() throws SQLException {
    try (Connection owner = dataSource.getConnection()) {
      jdbcUrl = owner.getMetaData().getURL();
      try (Statement st = owner.createStatement()) {
        st.execute("ALTER ROLE " + APP_ROLE + " WITH LOGIN PASSWORD '" + APP_PASSWORD + "'");

        // The stand-in for Supabase's auth schema. Owned by the DDL role, granted to nobody —
        // which is precisely the arrangement production has, where Supabase created it.
        st.execute("CREATE SCHEMA IF NOT EXISTS auth");
        st.execute(
            "CREATE TABLE IF NOT EXISTS auth.users"
                + " (id UUID PRIMARY KEY, encrypted_password TEXT)");
        st.execute("DELETE FROM auth.users");
        st.execute(
            "INSERT INTO auth.users (id, encrypted_password) VALUES ('"
                + UUID.randomUUID()
                + "', 'not-a-real-hash')");
      }

      seededUser = UUID.randomUUID();
      try (Statement st = owner.createStatement()) {
        st.executeUpdate(
            "INSERT INTO users (id, email, role) VALUES ('"
                + seededUser
                + "', 'privilege-test@example.com', 'user')");

        // A row in each library table the Data API could reach, so "denied" below denies access to
        // something real. Both are upserts: the suite shares one database and re-runs per test.
        st.executeUpdate(
            "INSERT INTO zen_jobs (id, enabled, interval_seconds) VALUES ('"
                + SEEDED_JOB
                + "', true, 3600) ON CONFLICT (id) DO NOTHING");
        st.executeUpdate(
            "INSERT INTO zen_rate_limit_counters (bucket, subject, window_start, request_count)"
                + " VALUES ('"
                + SEEDED_BUCKET
                + "', 'deadbeef', now(), 1)"
                + " ON CONFLICT (bucket, subject, window_start) DO NOTHING");
      }

      standInForTheSupabaseDataApiRoles(owner);
    }
  }

  /**
   * Creates {@code anon} and {@code authenticated} and grants them what Supabase grants them.
   *
   * <p>The grant is the point. Dev Services provisions plain PostgreSQL, where these roles do not
   * exist, so a test that merely asserted "anon cannot read {@code zen_jobs}" would be asserting
   * that a nonexistent role cannot do anything — true, and worth nothing. What the setup reproduces
   * is the measured production state: {@code pg_default_acl} on a stock Supabase database grants
   * {@code arwdDxtm} — every DML verb plus TRUNCATE — to both roles for every table created by the
   * role Flyway connects as. So the roles here arrive holding real privileges over real rows, and
   * {@code R__identity_data_api_lockdown.sql} has something to take away.
   *
   * <p>They are given a login the same way {@code zen_runtime} is, and taken away again in teardown.
   * On a real Supabase project they have none: PostgREST reaches them by {@code SET ROLE}.
   */
  private void standInForTheSupabaseDataApiRoles(Connection owner) throws SQLException {
    try (Statement st = owner.createStatement()) {
      for (String role : DATA_API_ROLES) {
        if (!roleExists(owner, role)) {
          st.execute("CREATE ROLE " + role + " NOLOGIN");
        }
        st.execute("ALTER ROLE " + role + " WITH LOGIN PASSWORD '" + APP_PASSWORD + "'");
        st.execute("GRANT USAGE ON SCHEMA public TO " + role);
        st.execute("GRANT ALL ON ALL TABLES IN SCHEMA public TO " + role);
        st.execute("GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO " + role);

        // And the half that makes the exposure a standing condition rather than a past mistake:
        // Supabase's grant to these roles is ALTER DEFAULT PRIVILEGES, so every table created
        // later arrives granted. Reproduced here or aTableCreatedAfterTheLockdownIsNotExposedEither
        // would pass for the wrong reason — a new table anon cannot read because nothing ever
        // granted it, rather than because the lockdown revoked it.
        st.execute(
            "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO " + role);
        st.execute(
            "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO " + role);
      }
    }
  }

  private boolean roleExists(Connection connection, String role) throws SQLException {
    try (Statement st = connection.createStatement();
        ResultSet rs =
            st.executeQuery("SELECT 1 FROM pg_roles WHERE rolname = '" + role + "'")) {
      return rs.next();
    }
  }

  @AfterEach
  void takeTheLoginBack() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      st.execute("DELETE FROM users WHERE id = '" + seededUser + "'");
      st.execute("DELETE FROM zen_jobs WHERE id = '" + SEEDED_JOB + "'");
      st.execute("DELETE FROM zen_rate_limit_counters WHERE bucket = '" + SEEDED_BUCKET + "'");
      st.execute("DROP SCHEMA IF EXISTS auth CASCADE");
      st.execute("ALTER ROLE " + APP_ROLE + " WITH NOLOGIN");

      // The stand-ins leave the database exactly as they found it — no anon role, which is the
      // state every other test in the suite ran against before ADR-036. DROP OWNED first: it
      // removes the grants and the default-privilege entries the lockdown migration created, which
      // DROP ROLE would otherwise refuse over.
      for (String role : DATA_API_ROLES) {
        if (roleExists(owner, role)) {
          st.execute("DROP OWNED BY " + role);
          st.execute("DROP ROLE " + role);
        }
      }
    }
  }

  private Connection asApplicationRole() throws SQLException {
    return DriverManager.getConnection(jdbcUrl, APP_ROLE, APP_PASSWORD);
  }

  /** Asserts the statement is refused for want of privilege, and not for some other reason. */
  private void assertRefused(Connection connection, String sql) {
    try (Statement st = connection.createStatement()) {
      st.execute(sql);
      fail("the application role was allowed to run: " + sql);
    } catch (SQLException e) {
      assertEquals(
          INSUFFICIENT_PRIVILEGE,
          e.getSQLState(),
          "expected a privilege refusal for [" + sql + "] but got: " + e.getMessage());
    }
  }

  private long countUsersAs(Connection connection) throws SQLException {
    return countAs(connection, "users");
  }

  @Test
  void theApplicationRoleExistsAndCannotLogInOnItsOwn() throws SQLException {
    // Teardown revokes LOGIN, so this asserts the shipped state: the migration creates the role,
    // and the credential that makes it usable comes from somewhere else entirely.
    takeTheLoginBack();
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement();
        ResultSet rs =
            st.executeQuery(
                "SELECT rolcanlogin FROM pg_roles WHERE rolname = '" + APP_ROLE + "'")) {
      assertTrue(
          rs.next(), "the application-role migration did not create the " + APP_ROLE + " role");
      assertEquals(false, rs.getBoolean(1), APP_ROLE + " ships with a login it should not have");
    }
  }

  @Test
  void theApplicationRoleReadsAndWritesTheUsersTable() throws SQLException {
    try (Connection app = asApplicationRole()) {
      assertTrue(
          countUsersAs(app) >= 1,
          "the application role read zero rows from users — the least-privilege grant is"
              + " incomplete, or a row-level policy is matching nothing");

      UUID mine = UUID.randomUUID();
      try (Statement st = app.createStatement()) {
        assertEquals(
            1,
            st.executeUpdate(
                "INSERT INTO users (id, email, role) VALUES ('"
                    + mine
                    + "', 'written-by-app-role@example.com', 'user')"));
        assertEquals(
            1, st.executeUpdate("UPDATE users SET display_name = 'x' WHERE id = '" + mine + "'"));
        assertEquals(1, st.executeUpdate("DELETE FROM users WHERE id = '" + mine + "'"));
      }
    }
  }

  @Test
  void theApplicationRoleCannotReachTheAuthSchema() throws SQLException {
    // The finding this whole wave is about (F5). As the owner, a SQL injection anywhere in the
    // application reads Supabase's password hashes and can mint identities; as zen_runtime it reads
    // the application's own schema and stops there.
    try (Connection app = asApplicationRole()) {
      assertRefused(app, "SELECT * FROM auth.users");
      assertRefused(app, "INSERT INTO auth.users (id) VALUES ('" + UUID.randomUUID() + "')");
    }
  }

  @Test
  void theApplicationRoleCannotChangeTheSchema() throws SQLException {
    try (Connection app = asApplicationRole()) {
      assertRefused(app, "CREATE TABLE public.smuggled (id INT)");
      assertRefused(app, "DROP TABLE users");
      assertRefused(app, "ALTER TABLE users ADD COLUMN backdoor TEXT");
      assertRefused(app, "CREATE SCHEMA elsewhere");
    }
  }

  @Test
  void theApplicationRoleCannotRewriteFlywayHistory() throws SQLException {
    // A role that can edit the schema-history table can make the database claim to be at any
    // version, which turns the migration gate into a suggestion.
    try (Connection app = asApplicationRole()) {
      assertRefused(app, "SELECT * FROM flyway_schema_history");
      assertRefused(app, "DELETE FROM flyway_schema_history");
    }
  }

  /**
   * The trap this wave was most likely to fall into, asserted in both directions.
   *
   * <p>V2 enables row-level security on {@code users} with a policy of {@code id = auth.uid()}.
   * {@code auth.uid()} reads a request-scoped Supabase JWT claim that a pooled JDBC connection does
   * not carry, so for the application path that predicate is NULL and matches nothing. The owner
   * connection never noticed because owners bypass RLS. A non-owner does not — and the symptom is
   * an empty result set, not an error: every user authenticated, nobody holding a role,
   * {@code @RolesAllowed} refusing everything, and it all reading like a permissions bug.
   *
   * <p>So the assertion is on rows returned. The Supabase policy is stood in for by {@code USING
   * (false)}, which is what {@code id = auth.uid()} evaluates to here, and the test drops
   * {@code users_application} to show that it is the policy doing the work rather than something
   * else.
   */
  @Test
  void withRowLevelSecurityOn_theApplicationPathStillSeesItsRows() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement admin = owner.createStatement()) {
      admin.execute("ALTER TABLE users ENABLE ROW LEVEL SECURITY");
      admin.execute("CREATE POLICY users_owner_standin ON users FOR ALL USING (false)");
      try {
        try (Connection app = asApplicationRole()) {
          assertTrue(
              countUsersAs(app) >= 1,
              "row-level security hid the application's own rows — users_application is missing"
                  + " or does not cover the runtime role");

          admin.execute("DROP POLICY users_application ON users");
          assertEquals(
              0L,
              countUsersAs(app),
              "dropping users_application changed nothing, so this test is not measuring the"
                  + " policy it claims to");

          admin.execute(
              "CREATE POLICY users_application ON users FOR ALL TO "
                  + APP_ROLE
                  + " USING (true) WITH CHECK (true)");
          assertTrue(countUsersAs(app) >= 1);
        }
      } finally {
        admin.execute("DROP POLICY IF EXISTS users_owner_standin ON users");
        admin.execute("ALTER TABLE users DISABLE ROW LEVEL SECURITY");
        // Restore the shipped policy even if an assertion above left it dropped: every later test
        // in this suite runs against the same database.
        admin.execute(
            "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'users'"
                + " AND policyname = 'users_application') THEN EXECUTE 'CREATE POLICY"
                + " users_application ON users FOR ALL TO "
                + APP_ROLE
                + " USING (true) WITH CHECK (true)'; END IF; END $$");
      }
    }
  }

  /** The migration's own text, read from the classpath so the test runs what production runs. */
  private String migrationSql() throws java.io.IOException {
    return migrationSql("R__identity_application_role.sql");
  }

  private String migrationSql(String fileName) throws java.io.IOException {
    try (var in =
        Thread.currentThread()
            .getContextClassLoader()
            .getResourceAsStream("db/migration/" + fileName)) {
      assertNotNull(in, fileName + " is not on the classpath");
      return new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    }
  }

  @Test
  void theMigrationIsIdempotent() throws Exception {
    // It is a repeatable migration, so it re-runs whenever its checksum changes — which means
    // "runs twice" is a normal state and not an edge case. Running it again here is the cheapest
    // way to keep that true as the file grows.
    //
    // All four repeatables, not just the application role: each one re-runs on the boot after any
    // edit to it, and the Data API lockdown is the one where "runs twice" is least obvious — the
    // second run revokes privileges that are already gone, and ALTER DEFAULT PRIVILEGES ... REVOKE
    // is applied against an entry that no longer exists. The stand-in roles are present here, so
    // the lockdown runs its real body rather than taking its no-anon early return.
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      for (String file :
          new String[] {
            "R__identity_application_role.sql",
            "R__identity_data_api_lockdown.sql",
            "R__jobs_row_level_security.sql",
            "R__ratelimit_row_level_security.sql"
          }) {
        st.execute(migrationSql(file));
        st.execute(migrationSql(file));
      }
    }
  }

  @Test
  void grantingTheApplicationRoleAccessToAuthRefusesToMigrate() throws Exception {
    // The migration cannot REVOKE this: on Supabase the auth schema is owned by supabase_admin
    // while migrations run as postgres, so a revoke is answered with a warning and no effect
    // (measured against the live database). What it does instead is refuse to start, and this is
    // the assertion that the refusal is real rather than a comment.
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      st.execute("GRANT USAGE ON SCHEMA auth TO " + APP_ROLE);
      try {
        st.execute(migrationSql());
        fail("the migration accepted an application role that can reach the auth schema");
      } catch (SQLException e) {
        assertTrue(
            e.getMessage().contains("auth schema"),
            "expected the auth-schema refusal, got: " + e.getMessage());
      } finally {
        st.execute("REVOKE USAGE ON SCHEMA auth FROM " + APP_ROLE);
      }
      // And it migrates again once the grant is gone, so the guard is a gate and not a wall.
      st.execute(migrationSql());
    }
  }

  private Connection asDataApiRole(String role) throws SQLException {
    return DriverManager.getConnection(jdbcUrl, role, APP_PASSWORD);
  }

  private long countAs(Connection connection, String table) throws SQLException {
    try (Statement st = connection.createStatement();
        ResultSet rs = st.executeQuery("SELECT count(*) FROM " + table)) {
      assertTrue(rs.next());
      return rs.getLong(1);
    }
  }

  /**
   * Layer one, on its own: row-level security stops the Data API roles even while they hold every
   * privilege Supabase granted them.
   *
   * <p>The exposure is demonstrated by <em>removing</em> the fix rather than by describing it. With
   * RLS disabled — the state {@code V100} shipped and every deployment ran in until ADR-036 —
   * {@code anon} reads {@code zen_jobs} and can <b>switch off a scheduled job</b> with one UPDATE.
   * That is the whole severity of this finding: the rows are not sensitive, the control they carry
   * is, because retention is what discharges jZen's GDPR obligation and nothing anywhere raises when
   * it stops. With RLS back on, the same statements see and change nothing.
   *
   * <p>Note the asymmetry that makes RLS insufficient alone, and why {@code users} is in this test:
   * on this database {@code V2} skipped enabling RLS ({@code auth.uid()} does not exist off
   * Supabase), so {@code users} is readable here by grant alone. A table is protected by whichever
   * layer is actually present on it, which is the argument for having two.
   */
  @Test
  void rowLevelSecurityAloneStopsTheDataApiRoles() throws Exception {
    try (Connection owner = dataSource.getConnection();
        Statement admin = owner.createStatement()) {
      try (Connection dataApi = asDataApiRole("anon")) {
        assertEquals(
            0L,
            countAs(dataApi, "zen_jobs"),
            "zen_jobs is readable by anon as shipped — row-level security is not enabled on it");
        try (Statement st = dataApi.createStatement()) {
          assertEquals(
              0,
              st.executeUpdate("UPDATE zen_jobs SET enabled = false WHERE id = '" + SEEDED_JOB + "'"),
              "anon disabled a scheduled job through the Data API");
        }

        // Now the pre-ADR-036 state, so the assertion above is measuring the policy and not some
        // unrelated absence.
        admin.execute("ALTER TABLE zen_jobs DISABLE ROW LEVEL SECURITY");
        try {
          assertTrue(
              countAs(dataApi, "zen_jobs") >= 1,
              "with RLS off, anon still could not read zen_jobs — the stand-in grant is wrong, so"
                  + " this test proves nothing in either direction");
          try (Statement st = dataApi.createStatement()) {
            assertEquals(
                1,
                st.executeUpdate(
                    "UPDATE zen_jobs SET enabled = false WHERE id = '" + SEEDED_JOB + "'"),
                "this is the exposure ADR-036 closes and it did not reproduce");
          }
        } finally {
          admin.execute("ALTER TABLE zen_jobs ENABLE ROW LEVEL SECURITY");
        }
      }
    }
  }

  /**
   * Layer two, on its own: the privileges go, so the roles are refused even where no policy stands
   * between them and the table.
   *
   * <p>RLS is disabled on {@code zen_jobs} for the duration on purpose. A refusal that only holds
   * while a policy is in place would not distinguish this migration from the other two, and the
   * claim in its header is that they are independent layers — a grant restored by hand should still
   * meet RLS, and a table with no policy should still meet this.
   *
   * <p>Running the migration inside the test rather than relying on boot is deliberate: at boot
   * there was no {@code anon} role, so it took its early return and did nothing.
   */
  @Test
  void theDataApiRolesLoseEveryPrivilegeOnThePublicSchema() throws Exception {
    try (Connection owner = dataSource.getConnection();
        Statement admin = owner.createStatement()) {
      admin.execute("ALTER TABLE zen_jobs DISABLE ROW LEVEL SECURITY");
      admin.execute("ALTER TABLE zen_rate_limit_counters DISABLE ROW LEVEL SECURITY");
      try {
        for (String role : DATA_API_ROLES) {
          try (Connection dataApi = asDataApiRole(role)) {
            assertTrue(
                countAs(dataApi, "users") >= 1,
                role
                    + " could not read users before the lockdown — the stand-in grant is wrong, so"
                    + " anything this test proves afterwards is proof of nothing");
            assertTrue(countAs(dataApi, "zen_jobs") >= 1);
            assertTrue(countAs(dataApi, "zen_rate_limit_counters") >= 1);
          }
        }

        admin.execute(migrationSql("R__identity_data_api_lockdown.sql"));

        for (String role : DATA_API_ROLES) {
          try (Connection dataApi = asDataApiRole(role)) {
            assertRefused(dataApi, "SELECT count(*) FROM users");
            assertRefused(dataApi, "SELECT count(*) FROM zen_jobs");
            assertRefused(dataApi, "SELECT count(*) FROM zen_rate_limit_counters");
            assertRefused(dataApi, "SELECT count(*) FROM flyway_schema_history");
            assertRefused(
                dataApi, "UPDATE zen_jobs SET enabled = false WHERE id = '" + SEEDED_JOB + "'");
            assertRefused(dataApi, "DELETE FROM zen_rate_limit_counters");
            // TRUNCATE is why the revoke says ALL rather than naming the four DML verbs: the
            // measured Supabase grant carries it, and it empties a table without deleting a row.
            assertRefused(dataApi, "TRUNCATE zen_rate_limit_counters");
          }
        }
      } finally {
        admin.execute("ALTER TABLE zen_jobs ENABLE ROW LEVEL SECURITY");
        admin.execute("ALTER TABLE zen_rate_limit_counters ENABLE ROW LEVEL SECURITY");
      }
    }
  }

  /**
   * A table created <em>after</em> the lockdown ran is covered too, which is the half that keeps
   * this from being a one-off cleanup.
   *
   * <p>Supabase's exposure is not a set of grants someone made once; it is {@code ALTER DEFAULT
   * PRIVILEGES}, so every new table arrives granted. Revoking the tables that exist today would
   * leave the next migration's table exposed on the boot that creates it, and nothing would say so.
   */
  @Test
  void aTableCreatedAfterTheLockdownIsNotExposedEither() throws Exception {
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      // First, the default privilege doing its work — otherwise the assertion after the lockdown
      // would hold on a database where nothing ever granted anything, and prove nothing.
      st.execute("CREATE TABLE IF NOT EXISTS public.added_before_the_lockdown (id INT)");
      try {
        try (Connection dataApi = asDataApiRole("anon")) {
          assertEquals(0L, countAs(dataApi, "added_before_the_lockdown"));
        }
      } finally {
        st.execute("DROP TABLE IF EXISTS public.added_before_the_lockdown");
      }

      st.execute(migrationSql("R__identity_data_api_lockdown.sql"));
      st.execute("CREATE TABLE IF NOT EXISTS public.added_after_the_lockdown (id INT)");
      try {
        for (String role : DATA_API_ROLES) {
          try (Connection dataApi = asDataApiRole(role)) {
            assertRefused(dataApi, "SELECT * FROM added_after_the_lockdown");
            assertRefused(dataApi, "INSERT INTO added_after_the_lockdown (id) VALUES (1)");
          }
        }
      } finally {
        st.execute("DROP TABLE IF EXISTS public.added_after_the_lockdown");
      }
    }
  }

  /**
   * The zero-rows trap again, on the two tables ADR-036 enabled row-level security for — and the
   * reason those migrations ship a policy rather than only an {@code ENABLE}.
   *
   * <p>Enabling RLS on {@code zen_jobs} without {@code zen_jobs_application} does not raise
   * anything. It makes {@code JobScheduler} see an empty table: nothing due, nothing run, a
   * successful tick, and scheduled work silently stopped. The assertion is therefore on rows
   * returned, and the policy is dropped and restored to show it is the policy doing the work.
   */
  @Test
  void withRowLevelSecurityOn_theApplicationRoleStillSeesTheLibraryTables() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement admin = owner.createStatement()) {
      try (Connection app = asApplicationRole()) {
        assertTrue(
            countAs(app, "zen_jobs") >= 1,
            "row-level security hid zen_jobs from the application role — zen_jobs_application is"
                + " missing, and the symptom in production is a scheduler that runs nothing and"
                + " reports success");
        assertTrue(countAs(app, "zen_rate_limit_counters") >= 1);

        // The limiter's write path is a single INSERT ... ON CONFLICT DO UPDATE, so the policy has
        // to permit rows it PRODUCES and not only rows it sees — WITH CHECK, not just USING.
        try (Statement st = app.createStatement()) {
          assertEquals(
              1,
              st.executeUpdate(
                  "INSERT INTO zen_rate_limit_counters (bucket, subject, window_start,"
                      + " request_count) VALUES ('"
                      + SEEDED_BUCKET
                      + "', 'deadbeef', now(), 1) ON CONFLICT (bucket, subject, window_start)"
                      + " DO UPDATE SET request_count = zen_rate_limit_counters.request_count + 1"));
        }

        admin.execute("DROP POLICY zen_jobs_application ON zen_jobs");
        assertEquals(
            0L,
            countAs(app, "zen_jobs"),
            "dropping zen_jobs_application changed nothing, so this test is not measuring the"
                + " policy it claims to");
      } finally {
        admin.execute(
            "DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'zen_jobs'"
                + " AND policyname = 'zen_jobs_application') THEN EXECUTE 'CREATE POLICY"
                + " zen_jobs_application ON zen_jobs FOR ALL TO "
                + APP_ROLE
                + " USING (true) WITH CHECK (true)'; END IF; END $$");
      }
    }
  }

  /** The shipped state: both library tables carry RLS and a policy, applied by boot, not by a test. */
  @Test
  void theLibraryTablesShipWithRowLevelSecurityEnabled() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      for (String table : new String[] {"zen_jobs", "zen_rate_limit_counters"}) {
        try (ResultSet rs =
            st.executeQuery(
                "SELECT relrowsecurity FROM pg_class WHERE relname = '"
                    + table
                    + "' AND relnamespace = 'public'::regnamespace")) {
          assertTrue(rs.next(), table + " does not exist");
          assertTrue(
              rs.getBoolean(1),
              table
                  + " has no row-level security, so on Supabase it is readable and writable by"
                  + " anyone holding the anon key");
        }
        try (ResultSet rs =
            st.executeQuery(
                "SELECT policyname FROM pg_policies WHERE tablename = '"
                    + table
                    + "' AND policyname = '"
                    + table
                    + "_application'")) {
          assertTrue(
              rs.next(),
              table
                  + " has row-level security and no application policy — the application will read"
                  + " zero rows from it the moment it stops connecting as the owner");
        }
      }
    }
  }

  @Test
  void theMigrationRanAtAll() throws SQLException {
    // A guard against the whole file being a no-op: if the migration were never applied, every
    // assertion above would fail for the wrong reason (no such role) and this says so directly.
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement();
        ResultSet rs =
            st.executeQuery(
                "SELECT policyname FROM pg_policies WHERE tablename = 'users'"
                    + " AND policyname = 'users_application'")) {
      assertTrue(
          rs.next(), "the application-role migration did not create the users_application policy");
      assertNotNull(rs.getString(1));
    }
  }
}
