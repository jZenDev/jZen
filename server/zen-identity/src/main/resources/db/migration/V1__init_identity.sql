/*
 * Identity schema. Ports the users table from
 * ../BugEater/bugeater-quarkus/src/main/resources/db/migration/V1__init.sql, dropping every
 * learning-domain table (courses, modules, quizzes, xp, ...). Only the users table is
 * identity infrastructure.
 *
 * The id is the Supabase auth.users.id (assigned from the JWT sub). No foreign key to
 * auth.users: the @QuarkusTest Dev Services database is plain PostgreSQL with no auth schema,
 * and Supabase owns that table's lifecycle anyway.
 *
 * Beyond the donor's V1 columns this adds four first-class product columns (present in the
 * donor entity via later migrations): is_premium (payment) and analytics_consent /
 * deletion_warning_sent_at / final_warning_sent_at (GDPR data retention). See
 * docs/architecture/BLUEPRINT.md "Persistence".
 */

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
        CREATE EXTENSION pgcrypto;
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    nickname TEXT,
    display_name TEXT,
    email TEXT NOT NULL,
    email_verified BOOLEAN NOT NULL DEFAULT false,
    avatar_url TEXT,
    is_private BOOLEAN NOT NULL DEFAULT false,
    role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin', 'reviewer', 'b2b_admin')),
    language VARCHAR(5) DEFAULT 'en',
    theme VARCHAR(10) DEFAULT 'light',
    accepted_terms BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ,
    /* Payment. */
    is_premium BOOLEAN NOT NULL DEFAULT false,
    /* GDPR / data retention. */
    analytics_consent TEXT,
    deletion_warning_sent_at TIMESTAMPTZ,
    final_warning_sent_at TIMESTAMPTZ
);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind = 'i' AND relname = 'idx_users_email') THEN
        CREATE INDEX idx_users_email ON users (email);
    END IF;
END $$;
