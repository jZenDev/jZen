/*
 * The Supabase Data API loses its privileges on the public schema.
 *
 * WHAT WAS WRONG. A Supabase project publishes a REST interface (PostgREST) over the public
 * schema, reached with the project's anon key -- a key Supabase publishes on purpose and documents
 * as public. Supabase's DEFAULT PRIVILEGES then grant anon and authenticated everything on every
 * table created there. Measured, not assumed (pg_default_acl on a stock Supabase database,
 * 2026-08-04):
 *
 *     postgres | r | {postgres=arwdDxtm/postgres, anon=arwdDxtm/postgres,
 *                     authenticated=arwdDxtm/postgres, service_role=arwdDxtm/postgres}
 *
 * `arwd` is INSERT, SELECT, UPDATE, DELETE; `D` is TRUNCATE. The role that creates jZen's tables
 * is the one Flyway connects as, which is `postgres` -- exactly the row above. So every table this
 * repository migrates into public is, by default, world-readable and world-WRITABLE over HTTPS,
 * and nothing in the application can tell.
 *
 * That was true of zen_jobs, zen_rate_limit_counters and flyway_schema_history until ADR-036. It
 * was NOT true of users, which V2 covered with the users_owner policy -- and the shape of the miss
 * is worth recording: ADR-031 correctly identified anon/authenticated as the surface row-level
 * security defends in jZen, then only ever defended one table on it. The two library tables came
 * from modules added later and nothing existed to notice.
 *
 * WHY REVOKE PRIVILEGES AND NOT SCHEMA USAGE, which was the first draft and is wrong. USAGE on
 * schema public is held by PUBLIC, not merely by the Data API roles (measured on the same
 * database: nspacl contains `=U/pg_database_owner`). Revoking it from anon therefore changes
 * nothing at all -- the role keeps reaching the schema through PUBLIC -- and revoking it from
 * PUBLIC would also strip every role that has no explicit grant, which includes PostgREST's own
 * `authenticator` login role. A control that either does nothing or breaks an unrelated component
 * is not the lever. TABLE privileges are: PostgREST needs SELECT on a table to read it, whatever
 * it holds on the schema, and without it answers 42501 before a row is touched.
 *
 * WHY REVOKE RATHER THAN RELY ON RLS. The companion migrations in zen-jobs and zen-ratelimit
 * enable row-level security on their own tables, and that is the layer visible in the Supabase
 * dashboard. It is not sufficient on its own: it protects the tables that exist today, and the
 * next table someone adds arrives unprotected again with nothing to say so. The default-privileges
 * revoke below holds for tables not yet written.
 *
 * Equally, this file is not sufficient on its own either -- a grant restored by hand in the
 * dashboard would put the surface back, while RLS would still deny. They are two independent
 * layers on purpose. Neither is the other's backstop. A third, operator-side, is to stop exposing
 * public through the Data API at all; that is deploy:cloudrun's ONE-TIME SETUP step 1d, and it is
 * outside this repository because it is a project setting rather than schema.
 *
 * WHY THIS IS SAFE, which is the question to ask before revoking anything. jZen never uses the
 * Data API. The client talks to one server and it is ours (STANDARDS "The client talks to one
 * server"); no client package may reach Supabase directly, and verify:boundaries fails the build
 * if one tries. Supabase is reached only by the server, only for authentication, and only over
 * GoTrue's REST API -- which lives in the auth schema under its own role and is untouched by
 * everything below. service_role is untouched too: it is the operator's key, not a client's, and
 * revoking it would break the dashboard's own table editor for no gain.
 *
 * WHAT THIS DOES NOT COVER, said plainly rather than left to be discovered. The default-privileges
 * revoke names the role Flyway connects as, because that is the role that creates jZen's tables.
 * A table created by something else -- the dashboard's table editor runs as supabase_admin -- gets
 * that role's defaults instead, which still grant anon everything. Altering another role's default
 * privileges requires membership in it, which the migration role does not have. So: a table
 * created outside these migrations is exposed until someone revokes it, and the per-table RLS
 * layer is what stands in for this one there.
 *
 * WHY flyway_schema_history GETS NO POLICY. It is covered by the revoke below and deliberately NOT
 * given row-level security. Flyway owns that table, takes a lock on it and rewrites it on every
 * migration; RLS on it is a way to break the migration lock rather than a way to protect anything.
 * R__identity_application_role.sql already revokes it from zen_runtime.
 *
 * WHY REPEATABLE (R__), and why a SEPARATE file from R__identity_application_role.sql. Repeatable
 * for the usual reason: this is desired state -- grants -- not a step, and STANDARDS "Database
 * migrations" reserves R__ for exactly that. Separate because the other file is about the role the
 * APPLICATION connects as, and this one is about roles the application never uses; folding a Data
 * API lockdown into a file named for the application role would hide it from anyone reading the
 * directory. Both are idempotent, both may be edited, and neither depends on the other.
 *
 * Guarded on the anon role existing, so this is a no-op on the plain PostgreSQL that Dev Services
 * provisions for @QuarkusTest -- the same shape of guard V2 uses for auth.uid().
 */

DO $$
DECLARE
    ddl_role text := current_user;
    data_api_role text;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
        RAISE NOTICE 'No anon role (non-Supabase database); there is no Data API to lock down.';
        RETURN;
    END IF;

    FOREACH data_api_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
        /*
         * Both roles are created by Supabase, but a project is entitled to drop one, and a revoke
         * naming a role that does not exist is an error rather than a no-op.
         */
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = data_api_role);

        /*
         * Existing objects first -- every grant Supabase's defaults already handed out for the
         * tables jZen has migrated. ALL rather than the four DML verbs on purpose: the measured
         * ACL also carries TRUNCATE, which empties a table without deleting a row and would
         * survive a revoke that named only DML.
         */
        EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', data_api_role);
        EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I', data_api_role);
        EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM %I', data_api_role);

        /*
         * Then future ones. Default privileges attach to the role that CREATES an object, which
         * for every jZen table is the role Flyway connects as -- so that is the one to alter. This
         * is what makes the next migration's table safe on the boot that creates it, rather than
         * on some later boot when this file's checksum happens to change and it re-runs.
         */
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public'
                || ' REVOKE ALL ON TABLES FROM %I', ddl_role, data_api_role);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public'
                || ' REVOKE ALL ON SEQUENCES FROM %I', ddl_role, data_api_role);
        EXECUTE format(
            'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public'
                || ' REVOKE ALL ON FUNCTIONS FROM %I', ddl_role, data_api_role);

        RAISE NOTICE 'Data API role % holds no privileges in the public schema.', data_api_role;
    END LOOP;
END $$;
