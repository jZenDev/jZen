# The Supabase Data API exposure

A working document, not a source of truth. The architecture docs in
[`../../architecture/`](../../architecture/) remain authoritative; the decision this plan produced is
recorded as **ADR-036**.

**Found:** 2026-08-04
**Scope:** Flyway migrations under `server/*/src/main/resources/db/migration/`, the deployed
Supabase project behind `jzen-prod`
**Method:** review of every `CREATE TABLE` jZen ships against what Supabase grants by default, then
**measurement against the live project** with the anon key the deployment already holds, and
against a local Supabase stack before and after the fix.

**How it surfaced.** Not from an audit. From reading the ROADMAP to answer a different question —
whether the test environment could be torn down — and noticing that the Supabase dashboard was
flagging tables as unprotected. The answer to the original question turned out to be "no, and
teardown would not have helped": the defect was in the repository's migrations, so any redeploy of
any environment recreates it.

---

## 1. The finding

Supabase publishes a REST interface (PostgREST) over the `public` schema, reached with the
project's anon key — a key Supabase publishes on purpose and documents as public. Supabase's
default privileges grant `anon` and `authenticated` privileges on every table created there.

Three tables jZen migrates into `public` had no row-level security:

| Table | Shipped by |
|---|---|
| `zen_jobs` | `zen-jobs`, `V100__init_jobs.sql` |
| `zen_rate_limit_counters` | `zen-ratelimit`, `V200__init_rate_limit.sql` |
| `flyway_schema_history` | Flyway itself |

`users` was covered, by `V2__row_level_security.sql`'s `users_owner` policy.

### Measured against the deployed project, before any change

| Request, as `anon` | Result |
|---|---|
| `GET /rest/v1/zen_jobs` | **200**, every job row |
| `GET /rest/v1/zen_rate_limit_counters` | **200**, live counters and subject hashes |
| `GET /rest/v1/flyway_schema_history` | **200**, the full migration history |
| `GET /rest/v1/users` | **200 `[]`** — the policy working |
| `PATCH /rest/v1/zen_jobs` (filter matching no row) | **204** — the UPDATE was accepted |
| `DELETE /rest/v1/zen_rate_limit_counters` (filter matching no row) | **204** — accepted |

The write probes used filters that match nothing deliberately: `204` proves the statement executed
and zero rows qualified, while a missing privilege answers `401` / SQLSTATE `42501`. The privilege
was measured without touching a row.

## 2. Impact — control, not confidentiality

None of these tables holds a secret. `zen_rate_limit_counters` stores salted hashes by design
(ADR-029) and a job's schedule is not confidential. What is exposed is control:

- **Retention can be switched off with one `UPDATE`.** `zen_jobs.enabled = false` stops the job
  that discharges jZen's GDPR obligation (ADR-008). Nothing raises: the next tick finds nothing due
  and reports success. `interval_seconds` is the same attack with a slower fuse.
- **The durable rate limiter can be cleared on demand.** That table exists because hour-scale
  windows cannot live in memory under `--min-instances=0`, where the process is replaced about
  hourly (ADR-027). A `DELETE` erases an attacker's own window; an `INSERT` against someone else's
  subject hash locks a legitimate address out.
- **The schema's claimed version is writable.** `flyway_schema_history` was already revoked from
  `zen_runtime` for this reason (ADR-031) while remaining reachable over HTTPS.

**Severity: HIGH.** Unauthenticated, remote, no credential beyond a published key, and every
consequence fails silently.

## 3. Why it was missed

ADR-031 named this exact surface — "RLS is genuinely load-bearing for the client Postgres *does*
know per request — PostgREST's `anon` and `authenticated` roles" — and defended one table on it.
`zen-jobs` and `zen-ratelimit` added their tables afterwards, each the ordinary way, and nothing
connected them to that entry.

That is the signature of a missing **rule**, not a missing review: the work that created the gap was
careful, and would pass the same review again. The durable half of the remediation is therefore the
STANDARDS rule, not the migrations.

## 4. Remediation

Two independent layers, plus one operator-side. Neither of the first two is the other's backstop:
RLS protects the tables that exist and says nothing about the next one; the revoke covers future
tables and would be undone by one `GRANT` typed into the dashboard.

| # | Change | Where |
|---|---|---|
| 1 | RLS + a `zen_runtime` application policy on `zen_jobs` | `R__jobs_row_level_security.sql` |
| 2 | The same for `zen_rate_limit_counters`, whose policy needs `WITH CHECK` for the limiter's upsert | `R__ratelimit_row_level_security.sql` |
| 3 | `anon`/`authenticated` lose every privilege in `public`, including the default privileges that would re-grant future tables | `R__identity_data_api_lockdown.sql` |
| 4 | The rule: a new table ships RLS and a policy in the same change | STANDARDS "Database migrations" |
| 5 | Stop exposing `public` through the Data API, and a `curl` that checks reality rather than the settings page | `Taskfile.yml`, `deploy:cloudrun` step 1d |

All three migrations are repeatable (`R__`): they are desired state rather than steps, they must
reach tables from any version band, and a low version is out-of-order on any database past it
(ADR-033).

**Deliberately not included: ADR-031's `zen_runtime` cutover.** The policies above are inert until
the application stops connecting as owner. Shipping both at once would give a wrong policy and a
wrong role the identical symptom — zero rows, no error — and one deploy in which to hide.

## 5. Evidence

- **Before and after on one local Supabase database.** Before: `anon=Dxtm,authenticated=Dxtm` on all
  four tables, `relrowsecurity = false` on three. After: neither role appears in any table's ACL,
  `relrowsecurity = true` on both library tables, both `_application` policies present, and
  PostgREST answering `401` / `42501` on all four — including `users`, previously `200 []`.
  `service_role` untouched.
- **`DatabasePrivilegeTest` 14/14**, proving each layer with the other switched off, and proving the
  zero-rows trap in both directions.
- **Backend suite 136 tests; `task test:e2e` 16/16** against real Supabase + Quarkus.
  `verify:boundaries`, `verify:docs`, `sync:contracts` all pass.
- The application path is unaffected against the locked-down database: `/api/v1/health` and
  `/api/v1/demo/terms` answer normally.

## 6. A note on the local stack, because it nearly hid this

A Supabase stack started from today's CLI grants `anon` only `Dxtm` — TRUNCATE, REFERENCES,
TRIGGER, MAINTAIN — so its PostgREST already refuses a read, and the exploit **does not reproduce
locally**. The deployed project, created earlier, also carries `arwd`. A second stock database
inspected the same day still showed `postgres | r | {anon=arwdDxtm/postgres}` in `pg_default_acl`,
so this is not a retired default.

Two things follow. Local absence of a finding says nothing about a project created at another time,
which is the argument for establishing the property rather than inheriting it. And the revoke says
`ALL` rather than naming the four DML verbs, because **TRUNCATE is granted even on the "safe"
defaults** and it empties a table without deleting a row.
