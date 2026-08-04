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
 */
@QuarkusTest
class DatabasePrivilegeTest {

  /** Fixed by the migration; jZen ships one runtime role the way it ships one users table. */
  private static final String APP_ROLE = "zen_runtime";

  /** Throwaway, and revoked in teardown. Never leaves the Dev Services container. */
  private static final String APP_PASSWORD = "zen_runtime_test_only";

  /** PostgreSQL's SQLSTATE for insufficient_privilege — what every refusal below must be. */
  private static final String INSUFFICIENT_PRIVILEGE = "42501";

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
      }
    }
  }

  @AfterEach
  void takeTheLoginBack() throws SQLException {
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      st.execute("DELETE FROM users WHERE id = '" + seededUser + "'");
      st.execute("DROP SCHEMA IF EXISTS auth CASCADE");
      st.execute("ALTER ROLE " + APP_ROLE + " WITH NOLOGIN");
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
    try (Statement st = connection.createStatement();
        ResultSet rs = st.executeQuery("SELECT count(*) FROM users")) {
      assertTrue(rs.next());
      return rs.getLong(1);
    }
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
    try (var in =
        Thread.currentThread()
            .getContextClassLoader()
            .getResourceAsStream("db/migration/R__identity_application_role.sql")) {
      assertNotNull(in, "the application-role migration is not on the classpath");
      return new String(in.readAllBytes(), java.nio.charset.StandardCharsets.UTF_8);
    }
  }

  @Test
  void theMigrationIsIdempotent() throws Exception {
    // It is a repeatable migration, so it re-runs whenever its checksum changes — which means
    // "runs twice" is a normal state and not an edge case. Running it again here is the cheapest
    // way to keep that true as the file grows.
    try (Connection owner = dataSource.getConnection();
        Statement st = owner.createStatement()) {
      st.execute(migrationSql());
      st.execute(migrationSql());
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
