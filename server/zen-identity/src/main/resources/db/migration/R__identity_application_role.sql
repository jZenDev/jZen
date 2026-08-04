/*
 * The least-privilege application role, and what row-level security here is actually for.
 *
 * WHY THIS IS REPEATABLE (R__) AND NOT VERSIONED, which is not a stylistic choice. The obvious
 * name was V3, inside zen-identity's reserved band 1-99 (STANDARDS "Database migrations"). It
 * does not work, and the way it fails is worth recording: every database that has run V100
 * (zen-jobs) and V200 (zen-ratelimit) is already past version 3, so a new V3 is an OUT-OF-ORDER
 * migration and Flyway refuses to start the application at all -- "Detected resolved migration
 * not applied to database: 3". Production is in exactly that state. The version bands allocate
 * ownership so two libraries cannot collide; they do not, and cannot, make a low-numbered band
 * still usable once a high-numbered one has shipped. The remedies for that are
 * out-of-order=true or ignoreMigrationPatterns, and both work by making Flyway stop checking.
 *
 * A repeatable migration is the right shape here for a reason beyond dodging the number.
 * Everything below is a DESIRED STATE -- grants, revokes, one policy -- not a step. Repeatables
 * run after every versioned migration, so ALL TABLES IN SCHEMA public reaches tables from any
 * band, on a fresh database and an existing one alike. And unlike a versioned migration this
 * file is NOT immutable: editing it changes its checksum and re-runs it on the next boot, which
 * is how a privilege model should evolve. The obligation that comes with that is idempotence,
 * and it is why every statement below is either inherently idempotent or guarded.
 *
 * Repeatables are keyed by DESCRIPTION rather than version, so the name carries the owning
 * module (identity_) the way a version band otherwise would.
 *
 * WHY THE ROLE IS CALLED zen_runtime AND NOT zen_app. It is the role the running server CONNECTS
 * AS -- the counterpart of the DDL role, distinguished by what it may do and not by who owns it.
 * "zen_app" was the first name and it was wrong in a repository that has an apps/ directory: it
 * reads as "the zen application", which is a thing that exists (zen_demo) and is not this. One
 * role serves every application, the way one users table does.
 *
 * The role is a FRAMEWORK-WIDE concern living in zen-identity, which is worth naming rather than
 * leaving to be noticed: it needs privileges over zen-jobs' and zen-ratelimit's tables too. It
 * sits here because zen-identity owns the schema baseline (V1, V2) and every application depends
 * on it, so the role exists before anything needs it -- and because the grants below are
 * SCHEMA-WIDE and never name another module's table, so no library reaches into a sibling.
 *
 * WHY. Until now the application connected as the database owner. Nothing exploits that today --
 * the audit verified there is no injection anywhere (docs/plans/SECURITY-REMEDIATION.md, F5) --
 * so this is blast-radius reduction, not a fix. The difference it makes is to what a future
 * injection or a leaked DB_PASSWORD is worth: as owner it is "auth.users, password hashes, and
 * the ability to forge identities", because Supabase's auth schema lives in the same database as
 * the application's. As zen_runtime it is the public schema this application already serves from.
 *
 * WHAT THIS MIGRATION DOES NOT DO: give zen_runtime a password, or a login. It creates the role
 * NOLOGIN and grants it what the application needs. A password written here would be a plaintext
 * credential in git, readable by everyone who can read the repository and rotated only by editing
 * source. The operator provisions the login out of band; the commands are in Taskfile.yml's
 * deploy:cloudrun summary, step 1c. Until they do, this migration is inert and the application
 * keeps connecting as it did -- which is why applying it is safe on a running deployment.
 *
 * ROW-LEVEL SECURITY, decided here rather than left ambiguous (ADR-031). V2 enabled RLS on users
 * with a users_owner policy of id = auth.uid(), and its own header states plainly that the owner
 * connection bypasses it. That reads as a second line of defence the application path does not
 * receive, and it is worse than it looks: auth.uid() reads a request-scoped Supabase JWT claim,
 * and jZen reaches Postgres over a plain pooled JDBC connection that has no such claim. The
 * moment the application stops being the owner, auth.uid() is NULL, the predicate matches
 * nothing, and every query against users returns ZERO ROWS -- not an error. RoleAugmentor would
 * then fail closed on every request and the symptom would read as a permissions bug.
 *
 * The decision is that RLS on users is SUPABASE-SIDE ONLY. It exists to constrain PostgREST's
 * anon/authenticated roles, whose identity Postgres genuinely knows per request. It is not, and
 * cannot be, a second line for the application path: the application legitimately reads rows it
 * does not own (the admin panel lists every user, retention scans every user), so any policy the
 * application path could satisfy is a policy that permits everything it does. FORCE ROW LEVEL
 * SECURITY is therefore deliberately NOT set, and users_application below says so in the schema
 * itself instead of leaving it to be inferred from an absence.
 */

DO $$
DECLARE
    ddl_role text := current_user;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zen_runtime') THEN
        EXECUTE 'CREATE ROLE zen_runtime NOLOGIN';
    END IF;

    EXECUTE format('GRANT CONNECT ON DATABASE %I TO zen_runtime', current_database());
    EXECUTE 'GRANT USAGE ON SCHEMA public TO zen_runtime';

    /*
     * Existing tables, then future ones. ALL TABLES covers everything that exists when this runs,
     * which -- because a repeatable runs last -- is every table every band has created. The
     * default privileges cover tables created by a LATER migration on a later boot, in the window
     * before this file's checksum changes again and it re-runs; they attach to the role Flyway
     * connects as, which is the role that will create them.
     */
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO zen_runtime';
    EXECUTE 'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO zen_runtime';
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public'
            || ' GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO zen_runtime', ddl_role);
    EXECUTE format(
        'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public'
            || ' GRANT USAGE, SELECT ON SEQUENCES TO zen_runtime', ddl_role);

    /*
     * Flyway's own history is not application data. The grant above swept it up with everything
     * else in public; an application role that can rewrite migration history can make the schema
     * claim to be any version it likes.
     */
    IF EXISTS (SELECT 1 FROM pg_class
               WHERE relname = 'flyway_schema_history'
                 AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE 'REVOKE ALL ON TABLE flyway_schema_history FROM zen_runtime';
    END IF;

    /*
     * No DDL. PostgreSQL 15 removed CREATE on the public schema from PUBLIC, so on any database
     * jZen targets this is already the state -- but the whole point of this migration is that the
     * property is established rather than inherited, and on an older cluster PUBLIC still holds
     * it, which would silently hand zen_runtime the ability to create tables. Named roles that
     * were granted CREATE explicitly (Supabase grants it to anon, authenticated, service_role and
     * postgres by name) are untouched by this.
     */
    EXECUTE 'REVOKE CREATE ON SCHEMA public FROM PUBLIC';

    /*
     * The auth schema, which is the reason this migration exists -- CHECKED, not revoked, and the
     * difference was measured against the live database rather than reasoned about.
     *
     * The obvious thing to write here is REVOKE ALL ON SCHEMA auth (and its tables, sequences and
     * functions) FROM zen_runtime. It does not work, and it does not fail either: on Supabase the
     * auth schema is owned by supabase_admin, while migrations run as postgres, which holds only
     * USAGE
     * on it and no grant option. PostgreSQL answers a revoke you are not entitled to make with a
     * WARNING rather than an error -- one per object, and per COLUMN for tables -- so the version
     * of this file that revoked printed dozens of "no privileges could be revoked" lines on every
     * boot while changing nothing. A migration that warns routinely is a migration whose warnings
     * stop being read.
     *
     * The revoke was never the valuable part anyway: a freshly created role holds nothing on auth,
     * so the property is already true and what matters is that it STAYS true. An assertion says
     * that, and says it in the only direction that helps -- if anyone ever grants zen_runtime
     * access to auth, the application refuses to start instead of quietly serving with it. A
     * security control that cannot enforce itself should fail closed rather than warn.
     *
     * Guarded on the schema existing: the @QuarkusTest Dev Services database is plain PostgreSQL
     * with no auth schema, the same reason V2 guards on auth.uid().
     */
    IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'auth') THEN
        IF has_schema_privilege('zen_runtime', 'auth', 'USAGE') THEN
            RAISE EXCEPTION
                'zen_runtime can reach the auth schema. That is the privilege this migration '
                'exists to withhold: it puts Supabase''s identity tables, including password '
                'hashes, '
                'inside the blast radius of any injection in the application. Revoke it as the '
                'schema owner (supabase_admin) and restart.';
        END IF;
        RAISE NOTICE 'Verified: zen_runtime holds no access to the auth schema.';
    ELSE
        RAISE NOTICE 'No auth schema (non-Supabase database); nothing to check for zen_runtime.';
    END IF;

    /*
     * The policy that keeps the paragraph in this file's header from being a comment nobody
     * enforces. Permissive policies are OR'd, so this grants the application path the visibility
     * users_owner (id = auth.uid()) would otherwise take away from it the instant it stops being
     * the table owner. Created unconditionally: on a database where V2 skipped enabling RLS the
     * policy is simply inert, and creating it there keeps the two databases the same shape.
     *
     * Deleting this policy does not raise an error anywhere. It makes every query against users
     * return zero rows. DatabasePrivilegeTest asserts the row count for exactly that reason.
     */
    IF NOT EXISTS (SELECT 1 FROM pg_policies
                   WHERE tablename = 'users' AND policyname = 'users_application') THEN
        EXECUTE 'CREATE POLICY users_application ON users FOR ALL TO zen_runtime'
            || ' USING (true) WITH CHECK (true)';
    END IF;
END $$;
