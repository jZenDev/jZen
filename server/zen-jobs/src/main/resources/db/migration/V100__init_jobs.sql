/*
 * Job state for zen-jobs (ROADMAP step 7a, DECISIONS ADR-008).
 *
 * Version 100, not 3: every framework library owns a reserved Flyway version band so two libraries
 * can ship migrations to the same classpath location (db/migration) without ever colliding on a
 * version. zen-identity holds 1-99, zen-jobs holds 100-199, applications start at 1000. See
 * STANDARDS "Database migrations".
 *
 * This table is the reason scheduled work is a guarantee rather than a hope: last_run_at is what
 * due-ness is computed from, so a tick missed while the service was scaled to zero is caught up
 * on the next one instead of being lost. A job carries an interval, an enabled flag, and its run
 * outcome, and nothing more: retries come from the external scheduler's at-least-once delivery
 * plus the next tick.
 *
 * Rows are seeded from the registered ZenJob beans at startup and owned by the database
 * thereafter, so a schedule change or an emergency stop is an UPDATE, not a redeploy.
 */

CREATE TABLE IF NOT EXISTS zen_jobs (
    id TEXT PRIMARY KEY,
    enabled BOOLEAN NOT NULL DEFAULT true,
    interval_seconds BIGINT NOT NULL,
    /* When the last run STARTED. Null until the job has run once, which makes it due immediately. */
    last_run_at TIMESTAMPTZ,
    last_status TEXT CHECK (last_status IN ('SUCCESS', 'FAILURE')),
    last_duration_ms BIGINT,
    last_error TEXT,
    run_count BIGINT NOT NULL DEFAULT 0,
    failure_count BIGINT NOT NULL DEFAULT 0
);
