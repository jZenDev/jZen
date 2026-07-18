/*
 * Row-level security for the users table. Adapts
 * ../BugEater/bugeater-quarkus/src/main/resources/db/migration/V9__enable_rls.sql, which
 * guarded learning-domain tables (user_xp / user_badges / favorites) with Supabase auth.uid().
 * jZen has only the users table, so the owner policy is applied there: a row is visible only
 * to the Supabase user it belongs to (id = auth.uid()).
 *
 * auth.uid() and the auth schema exist only on the Supabase-managed database, not on the
 * plain PostgreSQL that Quarkus Dev Services provisions for @QuarkusTest. The whole body is
 * therefore guarded on the presence of auth.uid(): on Supabase it enables RLS and creates the
 * policy; on plain PostgreSQL it is a no-op, so Flyway still migrates cleanly under test.
 *
 * The Quarkus JDBC connection uses the postgres/service role, which is the table owner and
 * bypasses RLS (no FORCE ROW LEVEL SECURITY); the policy guards direct Supabase-side access.
 */

DO $$
BEGIN
    IF to_regprocedure('auth.uid()') IS NOT NULL THEN
        EXECUTE 'ALTER TABLE users ENABLE ROW LEVEL SECURITY';
        IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'users_owner') THEN
            EXECUTE 'CREATE POLICY users_owner ON users FOR ALL USING (id = auth.uid())';
        END IF;
    ELSE
        RAISE NOTICE 'auth.uid() not present (non-Supabase database); skipping RLS on users.';
    END IF;
END $$;
