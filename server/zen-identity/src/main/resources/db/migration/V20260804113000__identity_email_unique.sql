/*
 * users.email becomes UNIQUE, and the plain index V1 created for it goes away.
 *
 * WHY THE VERSION IS A TIMESTAMP AND NOT V3 (DECISIONS ADR-033, superseding ADR-008's band table
 * for every migration written from now on). The obvious name was V3, inside zen-identity's
 * reserved band 1-99. It cannot work: production has run V100 (zen-jobs) and V200
 * (zen-ratelimit), so a new V3 is out-of-order and Flyway refuses to start the application --
 * "Detected resolved migration not applied to database: 3". R__identity_application_role.sql hit
 * this in Wave 3 and escaped it by being genuinely repeatable. This file cannot: a UNIQUE
 * constraint is a schema STEP, not a desired state, so it needs a version, and the version has to
 * be above every version any database has already applied.
 *
 * A band cannot express that, because "above everything applied" is a fact about the whole
 * repository over time and a band is an allocation to one module. Picking the next free integer
 * by hand (V201) would work today and re-create exactly the collision the bands were invented to
 * prevent the moment two libraries are developed on parallel branches. A UTC timestamp is
 * monotonic by construction and needs no coordination between branches, which is why it is the
 * industry-standard answer to this problem. The owning module moves into the description --
 * identity_ -- the same way R__ migrations already carry it.
 *
 * WHY pgcrypto IS NOT DROPPED HERE, although the audit's F18 pairs the two. It was measured
 * against the live database rather than reasoned about, and the measurement reversed the task.
 *
 * V1 wrote CREATE EXTENSION pgcrypto guarded on the extension not already existing. On Supabase
 * -- production and the local stack alike -- pgcrypto is provisioned by the platform, in the
 * `extensions` schema, before jZen's first migration ever runs. So V1's guard has never fired
 * there and jZen has never created it. Dropping it would not be undoing a jZen mistake; it would
 * be deleting a platform-provided extension out of a schema this application neither owns nor
 * migrates, on the strength of a CREATE that never happened. Supabase's own dashboard lists it
 * as a managed extension, and platform code that resolves crypto functions through search_path at
 * call time leaves no trace in pg_depend, so a drop that the catalog says is safe can still break
 * something at runtime -- later, elsewhere, and silently. That is the shape of failure this
 * repository refuses.
 *
 * The plain-PostgreSQL half is where V1's CREATE does take effect (Dev Services, the native smoke
 * container), and there the extension is created and unused. Dropping it only there would mean a
 * migration whose behaviour depends on which database it meets, which is a worse property to own
 * than one unused extension on a throwaway database. It is left alone deliberately, in both
 * places, and this paragraph is the record of the decision rather than an omission.
 */

DO $$
DECLARE
    collisions text;
BEGIN
    /*
     * Duplicates would make the constraint fail at ALTER TABLE, and a migration that fails at
     * boot is a service that does not start. That is the correct outcome -- a duplicate address
     * means two profiles claim one identity, and there is no safe default for which one wins --
     * but it is only an acceptable outcome if the operator is told exactly what to fix. The
     * generic constraint-violation message names one offending row and no context.
     *
     * Measured on jzen-prod 2026-08-04 before this file was written: 8 rows, 8 distinct
     * addresses, 8 distinct lowercased addresses, 0 anonymised. The check is here for the
     * databases nobody measured.
     */
    SELECT string_agg(email || ' (' || n || ' rows)', ', ' ORDER BY email)
      INTO collisions
      FROM (SELECT email, count(*) AS n FROM users GROUP BY email HAVING count(*) > 1) dupes;

    IF collisions IS NOT NULL THEN
        RAISE EXCEPTION
            'users.email cannot be made UNIQUE: % ', collisions
            USING HINT =
                'Two or more profiles share an address, so two Supabase identities are claiming '
                'one mailbox. Decide which row is the live account and delete or re-address the '
                'others, then restart. Nothing here can choose for you.';
    END IF;

    /*
     * Named rather than left to PostgreSQL so a later migration, or a human reading \d users,
     * can refer to it. Guarded so the file is safe to re-run against a database where the
     * constraint was added by hand during an incident.
     */
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'users_email_key'
                     AND conrelid = 'public.users'::regclass) THEN
        EXECUTE 'ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email)';
    END IF;

    /*
     * V1's idx_users_email is a plain btree on exactly the column the UNIQUE constraint now
     * indexes, so it answers no query the constraint's index does not, and every INSERT and every
     * email UPDATE -- which is every login, since UserStore reconciles the address from the
     * provider on each one -- maintained both. Dropping it is the point of doing this in the same
     * migration: adding the constraint without it leaves the table permanently paying twice.
     */
    IF EXISTS (SELECT 1 FROM pg_class
               WHERE relkind = 'i'
                 AND relname = 'idx_users_email'
                 AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE 'DROP INDEX idx_users_email';
    END IF;
END $$;

/*
 * Anonymisation and this constraint agree, and the agreement is not accidental.
 * UserRetentionService writes anon_<user id>@deleted.invalid, and the user id is the primary key,
 * so every anonymised address is unique by construction. A constant placeholder would have made
 * the second account of any batch unerasable -- the constraint would refuse it, the retention
 * transaction would roll back, and GDPR erasure would stop working with no signal beyond a stack
 * trace in an hourly job. UserEmailUniquenessTest asserts both halves.
 */
COMMENT ON CONSTRAINT users_email_key ON users IS
    'One profile per address. Anonymised rows stay distinct because the placeholder embeds the '
    'user id (zen.identity.user.UserRetentionService).';
