# Security Remediation Plan

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative; where this plan proposes changing one
of them, it says so and names the ADR that has to record it.

**Audit date:** 2026-08-03
**Scope:** `server/`, `apps/zen_demo/`, `client/`, `admin/`, `Taskfile.yml`, Flyway migrations
**Method:** source review of every security-relevant path, plus `pnpm audit` and `dart pub outdated`

Two areas are **not** covered and must not be read as clean: Maven dependencies have never been
CVE-scanned (F20), and the GCP pricing behind the Cloud Armor rejection comes from model knowledge
rather than a live pricing page — though the margin is wide enough that the conclusion holds.

---

## 1. What is already correct — do not touch

This section exists to stop the plan from "fixing" working code. Every item was verified against
source during the audit.

### Identity and authorization

| Area | Verified behaviour |
|---|---|
| **Open redirect** | `RedirectTargets.java:73` — exact match only, explicitly rejecting prefix and host matching, with the reasoning recorded. The highest-stakes surface in the system (a recovery link is an account-takeover primitive), and it is right. |
| **User enumeration** | `IdentityService.java:88` — `email_taken` collapses into the same neutral 202 as a genuine pending confirmation. Upstream provider text never reaches the client; errors normalise to stable codes. |
| **Role resolution** | `RoleAugmentor` loads the role from the `users` table, never from the JWT. On a load failure it returns the identity *without* a role — fails closed against `@RolesAllowed`. |
| **Role integrity** | `V1__init_identity.sql` — `CHECK (role IN ('user','admin','reviewer','b2b_admin'))`. Constrained at the database, not only in Java. |
| **Job trigger secret** | Constant-time `MessageDigest.isEqual`; fails closed when unconfigured. The `%prod` default is empty, so an unconfigured deploy rejects every trigger rather than accepting every trigger. |

### Injection and data handling

- **No SQL/HQL injection.** Admin filters use named Panache parameters, sort is whitelisted through
  `SORTABLE`, and `UserRoleLoader`'s native query takes no user input.
- **`escape '!'` in `UserRetentionService.NOT_ANONYMISED`** — the author caught that `_` is a LIKE
  wildcard and that an unescaped `anon_%` would also exclude live addresses such as
  `anonymous@example.com`.
- **Retention pipeline ordering** — find and stamp are separate operations, and the stamp is written
  only after confirmed delivery, so an undelivered warning leaves the account in the pipeline
  instead of ageing toward erasure. The code documents the prior defect it fixes.

### Infrastructure and client

- **`JobScheduler`'s overlap guard is correct in-process.** The general critique of in-process state
  (F1) does *not* apply here: the flag only matters during a tick, and during a tick the instance is
  alive by definition. `--min-instances=0` does not break it.
- **Secrets via GCP Secret Manager**, not environment literals. The committed dev/test trigger tokens
  are scoped to profiles that never leave the machine.
- **Container** — non-root `USER 1001`, base image pinned by digest.
- **Client token storage** — refresh token in Keychain/Keystore with `first_unlock_this_device`,
  access token in memory only, reasoning recorded against MASVS-STORAGE-1.
- **No TLS bypass on the client** — no `badCertificateCallback`, no `HttpOverrides`.
- **`verify:boundaries` design** — the gate itself is well reasoned; only its language coverage is
  incomplete (F9).

---

## 2. Findings

Ordered by `(active exploitability × impact) / remediation cost`.

| ID | Finding | Location | Severity |
|---|---|---|---|
| **F1** | No rate limiting anywhere in the backend | all of `server/` | **HIGH** |
| **F2** | `--timeout=300s` — 200 slots saturate at **0.67 req/s** | `Taskfile.yml:1459` | **HIGH** |
| **F3** | WebSocket: no auth, no connection cap, no frame-size limit | `DemoWebSocket.java` | **HIGH** |
| **F4** | `logout` never revokes the refresh token upstream; it stays valid 7 days | `AuthResource.java:207` | **HIGH** |
| **F5** | Application connects to Postgres as owner/superuser; RLS bypassed | `application.properties:46`, `V2__row_level_security.sql` | **HIGH** |
| **F6** | Deploy capacity parameters hardcoded in the framework orchestrator | `Taskfile.yml:1457-1459` | MED |
| **F7** | CSRF token issued but never validated | `SessionService.java:63` | MED |
| **F8** | No security headers at all (CSP / HSTS / X-Frame-Options / …) | none configured | MED |
| **F9** | `verify:boundaries` does not cover the TypeScript admin panel | `Taskfile.yml` | MED |
| **F10** | Admin `range` has no upper bound → OOM on 256Mi | `AdminUserResource.java:208` | MED |
| **F11** | `users.email` written only on profile creation, never synced | `UserStore.java:57` | MED |
| **F12** | Email addresses logged at WARN → Cloud Logging | `EmailService.java:76` | MED |
| **F13** | `quarkus.http.idle-timeout` unset → 30-minute Quarkus default | not configured | LOW-MED |
| **F14** | Retention queries load unbounded result sets | `UserRetentionService.java` | LOW-MED |
| **F15** | `/openapi` publicly served in production | `application.properties:108` | LOW |
| **F16** | `to_regclass` probe runs on every authenticated request | `UserRoleLoader.java` | LOW |
| **F17** | CORS `allow-credentials=true` with unvalidated origins from a secret | `application.properties:120` | LOW |
| **F18** | No `UNIQUE` on `users.email`; `pgcrypto` created but unused | `V1__init_identity.sql` | LOW |
| **F19** | react-router GHSA-qwww-vcr4-c8h2 (transitive) | `ra-data-simple-rest > ra-core` | LOW |
| **F20** | Maven dependency CVE scan never run | — | **GAP** |

### The three that need explanation

**F2 is the cheapest high-severity fix in the plan.** At `--timeout=300s`, holding all 200
concurrency slots requires **0.67 requests per second** — one slow mobile connection. No botnet, no
load. Dropping the timeout to roughly 60s raises that to ~3.3 req/s, which is traffic the burst
limiter (F1) can see and act on. Nothing in the application needs 300s: every Supabase call is under
`@Timeout(2000)`, worst case with retries ≈ 7s. The one candidate for a long operation is the
retention job behind `/api/v1/jobs/trigger`, and Cloud Run's timeout is per service rather than per
route — so measure the job first, then set the service timeout from it.

**F5 changes the risk model rather than adding to it.** There is no injection today; that was
verified. But the application connects under a role that can read the entire database, **including
the `auth` schema Supabase owns**. Any future injection, or a leaked `DB_PASSWORD`, is therefore not
"the `users` table leaked" but "`auth.users`, password hashes, and the ability to forge identities".
Separately, RLS is enabled by `V2` while the owner connection bypasses it (`FORCE ROW LEVEL
SECURITY` is not set) — so the migration creates the *appearance* of a second line of defence that
the application path does not actually receive.

**F4 breaks a promise the code makes about itself.** `SessionService` cites the OWASP Session
Management Cheat Sheet for its seven-day rotating refresh token, but `AuthResource.logout()` only
clears browser cookies — there is no GoTrue `/logout` call, and no such method exists on
`SupabaseAuthClient`. Consequences: "sign out everywhere" is impossible, a stolen refresh token
cannot be revoked, and signing out on someone else's device is theatre.

---

## 3. Decisions already taken

Recorded so they are not re-litigated during execution.

| Question | Decision | Reasoning |
|---|---|---|
| Rate-limit storage | **Two tiers: in-memory burst + PostgreSQL for durable counters.** No Redis. | Memory alone is invalid under `--min-instances=0`, but valid for second-scale windows because attack traffic keeps the instance alive. Postgres is already provisioned, already under Flyway, costs $0 incrementally, and absorbs ~20K auth events/month at 2K MAU trivially. |
| Redis / Memorystore | **Rejected.** | Memorystore has no free tier (~$35/mo floor). Upstash adds a vendor, a secret, a network hop and a failure mode for a workload Postgres handles for free. |
| Counter cleanup | **An existing `zen-jobs` ZenJob.** Not `@Scheduled`. | `@Scheduled` provably does not fire under `--min-instances=0` — which is the entire reason `zen-jobs` exists. |
| Security-headers module | **Into `zen-transport`.** No new package. | It already owns the HTTP boundary and already hosts `@Provider` filters. One responsibility, not two. |
| Header filter mechanism | **Vert.x `@RouteFilter`, not JAX-RS.** | The Flutter web app (`/`) and admin panel (`/admin/`) are served by the Vert.x static handler, bypassing JAX-RS entirely — and those are exactly the responses that most need CSP and `X-Frame-Options`. Needs empirical confirmation during implementation. |
| OpenAPI removal | **Do it — for attack surface and cold start, not cost.** | Cloud Run bills CPU and memory during serving, not image size. Dollar impact ≈ $0. |
| Cloud Armor | **Rejected.** | Requires a Global External ALB in front of Cloud Run. Floor ≈ **$25–30/month** before any traffic (ALB ~$18/mo + policy $5/mo + $1/mo per rule). Fails the $0 constraint. |
| Cloudflare free tier | **Deferred; documented as the escalation path.** | Cheap in dollars — a domain is ~$10–15 per *year* at cost, and one is already on the critical path for App Links and email deliverability. Expensive in invariants: **two** written constraints depend on "no edge" — STANDARDS "Deployment model" (cookies) and `WellKnownResource` (`.well-known` paths must not be rewritten or redirected, and a failed App Links verification is cached by both Android and iOS). Free-tier Bot Fight Mode would break API clients outright. |

---

## 4. Execution waves

### Wave 0 — configuration only

Hours of work, near-zero risk, highest leverage in the plan.

| # | Task | Finding |
|---|---|---|
| 0.1 | Lower the Cloud Run `--timeout` (measure the retention job first; target ~60s) | F2 |
| 0.2 | Set `quarkus.http.idle-timeout` | F13 |
| 0.3 | Add a `MAX_PAGE_SIZE` bound to `parseRange` | F10 |
| 0.4 | Promote deploy capacity parameters to `vars`, current values as defaults | F6 |
| 0.5 | Replace logged email addresses with user ids; sweep server code for other PII | F12 |
| 0.6 | Fail fast on `CORS_ORIGINS = *` while `allow-credentials=true` | F17 |

Wave 0 on its own raises the cost of the cheapest denial-of-service by roughly 5× and removes two
data-loss and PII issues.

### Wave 1 — the abuse layer

The main body of work.

| # | Task | Finding |
|---|---|---|
| 1.1 | New `zen-ratelimit` module, two tiers as decided. `jandex-maven-plugin` is mandatory — without it the provider silently does nothing. | F1 |
| 1.2 | Correct client-IP resolution behind Cloud Run's proxy. `X-Forwarded-For` is spoofable without a trusted-proxy chain — the classic limiter bypass. Needs its own test. | F1 |
| 1.3 | Flyway migration for the counters; cleanup registered as a `ZenJob` | F1 |
| 1.4 | WebSocket: frame-size limit, connection cap, authenticated handshake — or drop it from the prod profile if `task test:e2e` does not depend on it | F3 |
| 1.5 | **ADR** superseding `STANDARDS.md:342` (see §5) | — |

**Priority note.** `/api/v1/jobs/trigger` must come first in the persistent limiter's coverage. A
successful call runs retention — email dispatch and **account anonymisation**. It is the
highest-consequence endpoint in the system, and secret guessing against it is currently unbounded.

### Wave 2 — session and identity integrity

| # | Task | Finding |
|---|---|---|
| 2.1 | Add `logout` to `SupabaseAuthClient` (GoTrue `POST /logout`) and call it from `AuthResource.logout()`. A failed upstream call must not block cookie clearing — and must not be swallowed either. | F4 |
| 2.2 | Enforce CSRF on mutating methods. `/auth/login` and `/auth/register` run *before* the cookie exists and must be exempt; justify the exemption list in a comment. Confirm the Flutter client sends the header, or enabling this breaks mobile. | F7 |
| 2.3 | Sync `users.email` from the provider payload on every login, alongside `emailVerified` | F11 |

### Wave 3 — privilege and boundary

Latent-risk reduction: nothing here is actively exploitable today, and all of it shrinks the blast
radius of whatever comes later.

| # | Task | Finding |
|---|---|---|
| 3.1 | A dedicated least-privilege database role for the application (grants on `public` only) and a separate role for Flyway DDL. Coordinate with Supabase project setup. | F5 |
| 3.2 | Decide and document whether RLS is meant to be a real second line (`FORCE ROW LEVEL SECURITY`) or explicitly Supabase-side only. The current migration reads as protection the application path does not receive. | F5 |
| 3.3 | Extend `verify:boundaries` to `*.ts` / `*.tsx` and `package.json` | F9 |
| 3.4 | **ADR** recording the privilege split and the RLS clarification | — |

### Wave 4 — hardening and hygiene

| # | Task | Finding |
|---|---|---|
| 4.1 | Security headers via `@RouteFilter`. Tune CSP against real Flutter web (may need `wasm-unsafe-eval`) and react-admin needs — verify in a browser, not only in tests. | F8 |
| 4.2 | Exclude `quarkus-smallrye-openapi` in the native/prod Maven profile **only**. The default build must keep it: it generates the `openapi.json` that `sync:contracts` feeds to `openapi-typescript`. Confirm `task sync:contracts` stays green. | F15 |
| 4.3 | Maven CVE scan, wired into `Taskfile.yml` as a gate that fails rather than warns | F20 |
| 4.4 | `pnpm.overrides` pin for react-router. Real risk is near zero — the advisory scopes it to unstable RSC APIs, which react-admin does not use. Do not break the panel for a formally clean audit. | F19 |
| 4.5 | Dependency updates. **Not free:** `go_router 14→17` is three majors and carries auth redirects; `react-router 8.x` under `ra-core` may break the panel. `riverpod`, `analyzer`, `intl` are routine. | — |
| 4.6 | Batch limits on retention queries | F14 |
| 4.7 | Cache or drop the per-request `to_regclass` probe | F16 |
| 4.8 | Add `UNIQUE` on `users.email` (after 2.3); drop the unused `pgcrypto` extension | F18 |

### Wave 5 — an open decision, not a task

The 200-slot ceiling is not closable in code. After Waves 0 and 1 the exposure is materially
reduced, and `--max-instances=1` acts as a **cost fuse**: an attack costs availability, not money.
Two options remain, to be decided when real abuse appears rather than pre-emptively.

- **Accept**, with the perimeter documented as a known limit.
- **Cloudflare free tier**, requiring an ADR that amends two written invariants, plus verification
  that cookies and `.well-known` paths pass through untouched and that Bot Fight Mode is off.

---

## 5. Documentation debt this plan creates

`DECISIONS.md` is append-only — new entries, never edits to accepted ones. The repository has an
`add-adr` skill for the format.

| Item | Trigger |
|---|---|
| ADR — rate-limit storage | Wave 1.5. Supersedes the in-process-state claim in `STANDARDS.md:342`. |
| ADR — database privilege split and RLS scope | Wave 3.4 |
| ADR — perimeter | Only if Wave 5 chooses Cloudflare |
| Correction to `STANDARDS.md:342` | **Independent of any code change.** The document attributes the validity of in-process state to `--max-instances=1`; the actual constraint is `--min-instances=0`. STANDARDS states this rule correctly for scheduling and then fails to carry it to counters. |
