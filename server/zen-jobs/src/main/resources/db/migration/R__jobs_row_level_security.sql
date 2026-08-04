/*
 * Row-level security for zen_jobs, and the policy that keeps the application able to read it.
 *
 * WHY THIS EXISTS. zen_jobs was created by V100 with no row-level security at all. On a
 * Supabase-managed database that is not a neutral default: the Data API (PostgREST) exposes the
 * public schema, and Supabase's default privileges grant anon and authenticated full DML on
 * tables created there. A table with no RLS is therefore READABLE AND WRITABLE by anyone holding
 * the project's anon key, which Supabase publishes on purpose and treats as public.
 *
 * What that is worth on THIS table is not "a row leaked". zen_jobs owns whether scheduled work
 * runs: one UPDATE setting enabled = false stops the retention job, and jZen's GDPR obligation is
 * discharged by that job alone (ADR-008). Nothing errors, nothing warns, and the next tick simply
 * finds nothing due. Setting interval_seconds to something enormous is the same attack with a
 * slower fuse. The rows are not sensitive; the control they carry is.
 *
 * ADR-031 decided that RLS in jZen is SUPABASE-SIDE ONLY -- it constrains the anon/authenticated
 * roles, whose identity Postgres genuinely knows per request, and is never the application's own
 * authorization. That decision is unchanged here. What was missing is that it was only ever
 * APPLIED to users; this file applies the same reasoning to the table this module owns. See
 * ADR-036.
 *
 * WHY REPEATABLE (R__). Two reasons, and the first is not optional. A versioned migration here
 * would have to sort above every version already applied anywhere, and this module's band (100-199)
 * is long past on any database that has run V200 -- Flyway answers an out-of-order migration by
 * refusing to start the application (STANDARDS "Database migrations", ADR-033). The second reason
 * is that everything below is DESIRED STATE, not a step: enabling RLS and owning a policy is
 * exactly what a repeatable is for, and it may be edited later, which a privilege model needs.
 * The obligation in exchange is idempotence, and every statement below is guarded or inherently
 * idempotent.
 *
 * NO FORCE ROW LEVEL SECURITY, deliberately, for ADR-031's reason: the table owner must keep
 * bypassing RLS. Migrations run as the owner and the deployed application still connects as it
 * today; forcing would make this file able to lock the schema out of its own table.
 *
 * THE POLICY IS NOT OPTIONAL, and this is the trap worth naming rather than rediscovering. Once
 * the application connects as zen_runtime (ADR-031's cutover, an operator step that has not
 * happened yet), it is no longer the owner and RLS applies to it. Enabling RLS with no policy for
 * that role makes every SELECT against zen_jobs return ZERO ROWS -- not an error. JobScheduler
 * would find nothing due, report success, and run nothing, forever. DatabasePrivilegeTest asserts
 * the row count in both directions for exactly that reason.
 */

DO $$
BEGIN
    EXECUTE 'ALTER TABLE zen_jobs ENABLE ROW LEVEL SECURITY';

    /*
     * Guarded on the role existing, not assumed. zen_runtime is created by zen-identity's
     * R__identity_application_role.sql, and an application may depend on zen-jobs without
     * depending on zen-identity -- scheduled work does not require identity. Repeatables run in
     * description order, so identity_ precedes jobs_ when both are present, but a guard states the
     * dependency instead of resting on alphabetical luck.
     */
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zen_runtime') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_policies
                       WHERE tablename = 'zen_jobs' AND policyname = 'zen_jobs_application') THEN
            EXECUTE 'CREATE POLICY zen_jobs_application ON zen_jobs FOR ALL TO zen_runtime'
                || ' USING (true) WITH CHECK (true)';
        END IF;
    ELSE
        RAISE NOTICE 'No zen_runtime role; zen_jobs has RLS and no application policy yet.';
    END IF;
END $$;
