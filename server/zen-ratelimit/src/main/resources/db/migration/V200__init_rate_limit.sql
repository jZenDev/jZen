/*
 * Durable rate-limit counters for zen-ratelimit (DECISIONS ADR-029).
 *
 * Version 200, not 3 and not 101: every framework library owns a reserved Flyway version band so
 * two libraries can ship migrations into the same classpath location (db/migration, the single
 * value of quarkus.flyway.locations) without ever colliding on a version. zen-identity holds
 * 1-99, zen-jobs holds 100-199, this module claims 200-299, applications start at 1000. The band
 * is a convention with nothing enforcing it, so it is recorded in STANDARDS "Database migrations"
 * as well as here; a collision is a failed migration at boot, which is the good case.
 *
 * WHY THIS TABLE EXISTS AT ALL, given that in-process state is otherwise valid here:
 * --min-instances=0 means the container exists only while it is serving, and the live service's
 * process is measurably replaced about every hour (ADR-027). A counter whose window outlives an
 * hour therefore cannot be held in memory - it would reset itself roughly as fast as an attacker
 * filled it. The minute-scale burst tier stays in memory, where --max-instances=1 makes it
 * correct; only the hour-scale windows come here.
 *
 * subject is a SALTED HASH of the client address, never the address. An IP address is personal
 * data (GDPR Recital 30) and this table outlives the request by the configured retention, so
 * storing the address would keep more than the purpose needs - the limiter only ever compares for
 * equality. See DurableLimiter#hash.
 */

CREATE TABLE IF NOT EXISTS zen_rate_limit_counters (
    /* The RateLimitRule this row counts: 'auth', 'job_trigger', ... */
    bucket TEXT NOT NULL,
    /* Hex SHA-256 of the client address, domain-separated and truncated to 128 bits. */
    subject TEXT NOT NULL,
    /* Start of the fixed window, truncated to the bucket's configured window length. */
    window_start TIMESTAMPTZ NOT NULL,
    request_count BIGINT NOT NULL DEFAULT 0,

    /* The primary key is also the ON CONFLICT target of the single-statement upsert in
     * DurableLimiter. That is what makes the increment atomic under the row lock Postgres already
     * takes: a read-then-write would lose updates, and a rate limiter that loses updates has
     * whatever limit concurrency happens to produce. */
    PRIMARY KEY (bucket, subject, window_start)
);

/* The cleanup ZenJob deletes by window_start alone, across every bucket and subject, so it cannot
 * use the primary key's leading columns. Without this index that sweep is a full scan on the one
 * table that grows with attack traffic. */
CREATE INDEX IF NOT EXISTS zen_rate_limit_counters_window_start_idx
    ON zen_rate_limit_counters (window_start);
