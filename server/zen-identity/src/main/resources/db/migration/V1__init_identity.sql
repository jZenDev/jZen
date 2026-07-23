/*
 * Identity schema: the users table, the application profile keyed by the Supabase identity.
 * This is framework infrastructure only; an application's own tables go in the application
 * version band (see STANDARDS "Database migrations").
 *
 * The id is the Supabase auth.users.id (assigned from the JWT sub). No foreign key to
 * auth.users: the @QuarkusTest Dev Services database is plain PostgreSQL with no auth schema,
 * and Supabase owns that table's lifecycle anyway.
 *
 * Beyond the identity columns, four are first-class cross-cutting product concerns:
 * is_premium (payment) and analytics_consent / deletion_warning_sent_at /
 * final_warning_sent_at (GDPR data retention). See docs/architecture/BLUEPRINT.md
 * "Persistence".
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
