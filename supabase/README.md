# supabase/ — the local Supabase stack

Supabase is a **real, named dependency** in jZen, not something hidden behind a portability
layer (MANIFESTO "Real dependencies are first-class"). It owns **authentication**, and its
bundled PostgreSQL is the local database. This directory holds the local stack's configuration;
the [Supabase CLI](https://supabase.com/docs/guides/cli) reads it.

## Running it

```bash
task run:supabase     # supabase start (idempotent — no-op if already running)
task stop:supabase    # supabase stop
```

Most workflows start it for you: `task run:all`, `task run:demo`, and `task test:e2e` each bring
the stack up before they need it.

## Ports (`config.toml`)

| Service | Port |
|---|---|
| API (GoTrue auth, REST) | `54321` |
| Database (PostgreSQL) | `54322` |
| Studio (web console) | `54323` |
| Inbucket (captured local email) | `54324` |

These match the JDBC and Supabase URLs the app server defaults to in its
`application.properties`, so a fresh `task run:all` needs no configuration. The backend reads
`SUPABASE_URL`, `SUPABASE_KEY`, and `DB_URL`/`DB_USERNAME`/`DB_PASSWORD` from the environment,
falling back to these local defaults.

## Migrations live in Flyway, not here

`supabase/migrations/` **stays empty** (it holds only a `.gitkeep`). **Flyway is the single
migration authority** — the schema is owned by the framework libraries under
`zen-identity/db/migration/` and friends, migrated at server start. Two migration systems on one
database is exactly the failure this avoids (STANDARDS "Database migrations"). Do not add SQL
here.

## Auth and JWKS wiring

Supabase owns `auth.users`; the jZen `users` table is the **application profile**, keyed by the
JWT `sub`, with **no foreign key** to `auth.users` (the `@QuarkusTest` Dev Services database is
plain PostgreSQL with no `auth` schema, and Supabase owns that table's lifecycle). For the same
reason the row-level-security migration is guarded on `to_regprocedure('auth.uid()')`, so it is
a no-op on plain Postgres and tests still migrate.

The token path:

- A Supabase JWT is verified against the stack's **JWKS** endpoint
  (`{SUPABASE_URL}/auth/v1/.well-known/jwks.json`) with **ES256**.
- The access token is read from a normal httpOnly cookie, `zen_access_token`
  (`mp.jwt.token.cookie`, with `quarkus.http.auth.proactive=true`).
- The user's **role is loaded from the `users` table** by a `SecurityIdentityAugmentor`, **not**
  from the JWT — roles are application data, so revoking one must not wait for a token to expire.

This normally-named-cookie path works because jZen serves Cloud Run directly, with nothing in
front that strips or renames cookies. See
[`../docs/architecture/BLUEPRINT.md`](../docs/architecture/BLUEPRINT.md) "Authentication" and
STANDARDS "Deployment model".

## Studio and captured email

Open Studio at `http://localhost:54323` to inspect the database. Local email (welcome and
retention-warning mail) is captured by Inbucket rather than sent — the app's mailer is mocked in
dev — so nothing leaves the machine while you develop.
