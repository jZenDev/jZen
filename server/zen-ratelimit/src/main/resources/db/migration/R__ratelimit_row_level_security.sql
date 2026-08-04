/*
 * Row-level security for zen_rate_limit_counters, and the policy the limiter needs to keep
 * counting.
 *
 * WHY THIS EXISTS. V200 created this table with no row-level security. On a Supabase-managed
 * database the Data API (PostgREST) exposes the public schema and Supabase's default privileges
 * grant anon and authenticated full DML on tables created there, so a table with no RLS is
 * readable AND WRITABLE by anyone holding the project's anon key -- a key Supabase publishes on
 * purpose. See ADR-036 and the companion file in zen-identity.
 *
 * What that is worth HERE is a rate limiter that cannot be trusted. This table exists because the
 * hour-scale windows cannot live in memory: under --min-instances=0 the live process is replaced
 * about every hour (ADR-027), so an in-memory counter resets itself roughly as fast as an attacker
 * fills it. A DELETE over the Data API does the same thing on demand, and faster -- the attacker
 * clears their own window and the limit becomes decorative. An INSERT is the mirror image: rows
 * keyed to someone else's subject hash lock a legitimate address out. Neither leaves a trace the
 * application can see, because from its side the table simply says what it says.
 *
 * The rows themselves are salted hashes and a count, so this is not about confidentiality. It is
 * about a control surface being writable by the public.
 *
 * WHY REPEATABLE (R__), NO FORCE, AND WHY THE POLICY IS MANDATORY: identical reasoning to
 * zen-jobs' R__jobs_row_level_security.sql, and the reasoning is in that file rather than repeated
 * in full here. The short of it: a versioned migration in this module's band (200-299) would be
 * out-of-order and refuse to boot; this is desired state, not a step; the owner must keep
 * bypassing; and a policy-less RLS table returns zero rows to zen_runtime after ADR-031's cutover
 * instead of raising, which for a limiter means every window looks empty and nothing is ever
 * limited.
 *
 * ONE DIFFERENCE FROM zen_jobs, and it is why the policy carries WITH CHECK as well as USING.
 * DurableLimiter increments with a single INSERT ... ON CONFLICT DO UPDATE, which is both a write
 * of a new row and a modification of an existing one. USING alone governs the rows a statement may
 * SEE; WITH CHECK governs the rows it may PRODUCE, and an INSERT with no applicable WITH CHECK is
 * refused outright. FOR ALL ... USING (true) WITH CHECK (true) covers both halves of that upsert,
 * which is the whole of the limiter's write path.
 */

DO $$
BEGIN
    EXECUTE 'ALTER TABLE zen_rate_limit_counters ENABLE ROW LEVEL SECURITY';

    /*
     * Guarded on the role existing: zen_runtime comes from zen-identity, and an application may
     * rate-limit without depending on identity.
     */
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'zen_runtime') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_policies
                       WHERE tablename = 'zen_rate_limit_counters'
                         AND policyname = 'zen_rate_limit_counters_application') THEN
            EXECUTE 'CREATE POLICY zen_rate_limit_counters_application'
                || ' ON zen_rate_limit_counters FOR ALL TO zen_runtime'
                || ' USING (true) WITH CHECK (true)';
        END IF;
    ELSE
        RAISE NOTICE
            'No zen_runtime role; zen_rate_limit_counters has RLS and no application policy yet.';
    END IF;
END $$;
