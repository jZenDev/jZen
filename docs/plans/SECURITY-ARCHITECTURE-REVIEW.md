# The architectural security review

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative, and ADRs win on conflict.

**Reviewed:** 2026-09-18. **Phase 0 CLOSED** (orientation and scope freeze). **Phase 1 CLOSED**
(assets, trust boundaries, threat model). **Phase 2 CLOSED** (the inheritance audit and
silent-no-op census — see "Phase 2 record" for the closure check against the plan's own deliverable
list). **Phase 3 CLOSED** (identity, session, authorization — see "Phase 3 record"). **Phase 4
CLOSED** (the transport seam and the two parsers — see "Phase 4 record"). **Phase 5 CLOSED** (the
data plane, privileges, and privacy — see "Phase 5 record"). **Phase 6 CLOSED** (supply chain and
build integrity — see "Phase 6 record"). **Phase 7 CLOSED** (the client and the browser surface —
see "Phase 7 record"; this is also the phase that opened the production request ledger, plan §4.3).
Phases 8–9 are not yet executed. Sections 4–9 below remain placeholders except where Phases 4–7
populated §3.5–§3.8.

**Scope:**
- **In scope.** jZen as a framework — `server/zen-*`, `client/zen_*`, `admin/` (`@jzen/admin-core`) —
  and what `apps/zen_demo/{zen_demo_server,zen_demo_client,zen_demo_admin}` does or does not inherit
  from it. Nine trust boundaries (B1–B9, to be drawn in Phase 1) spanning the browser/mobile client,
  Cloud Run, Supabase Auth (GoTrue), the Supabase Data API, Postgres, Cloud Scheduler, GitHub Actions,
  Artifact Registry, and the admin panel. The inheritance question — what a second jZen application
  (ADR-026) receives automatically versus what it must remember to do — is the centre of gravity
  (plan §1, §6 Phase 2) and outranks any single line-level finding.
- **Out of scope.** Re-finding `SECURITY-REMEDIATION.md` F1–F20 (closed, 2026-08-03/04) or the
  `DATA-API-EXPOSURE.md` finding (closed as ADR-036/037) — confirming a closure is one line in §6
  "Closed", not a finding. Active scanning, fuzzing, or any write against the deployed
  `zen-demo-server` production service or the hosted Supabase project (plan §4.1–§4.4) — production
  gets **reads only**, budgeted at 12 requests (plan §4.3), and the hosted Supabase Data API is
  **not** probed (owner decision, 2026-08-13; verify locally instead, plan §4.4). A formal
  penetration test (plan §11 Q7) and legal/compliance assessment of the retention pipeline (plan
  Phase 5) are named as recommendations only, not performed here. Payment/checkout flows do not
  exist in jZen (ADR-010) and are not reviewed.
- **ASVS level:** **Level 2** — decided by the owner on 2026-08-13 (plan §2.3), not a default the
  reviewer weighs. jZen handles authentication credentials, personal data (email addresses) and an
  admin role. An obviously-cheap Level 3 item is noted as an *opportunity*, not a gap; a knowingly
  declined Level 2 item is a finding with an owner decision attached, never a silent omission.
- **Date:** scope frozen 2026-09-18.

**Standard:** OWASP ASVS 5.0.0 at Level 2, plus the surface-specific artifacts in the table below.
See "Standards versions" for the full list with release dates and the date each was read.

**Method:** static review of `server/`, `client/`, `admin/`, `apps/zen_demo/`, `Taskfile.yml`,
`.github/workflows/`, and the Flyway migrations under `db/migration/`; local dynamic testing against
`task test:native`'s container and `task run:demo`/`task run:supabase` (Phase 8 only); and a bounded
set of unauthenticated production reads plus control-plane (`gcloud`) reads against the deployed
`zen-demo-server` service (plan §4.3–§4.4). No test, scan, or fuzz run is pointed at production; no
write reaches production or the hosted Supabase project.
- **Production request ledger:** opened this phase, spent to 11 of the budgeted 12 (plan §4.3),
  every row read-only against `https://zen-demo-server-tovqpjhspa-lm.a.run.app` (the hostname
  confirmed as this build's `ZEN_API_URL` by grepping the staged web bundle, not assumed):

  | # | Method | Path | Purpose | Response | Cold/warm |
  |---|---|---|---|---|---|
  | 1 | GET | `/` | Security headers on the SPA root | 200, headers matched `SecurityHeaders.java` verbatim | warm |
  | 2 | GET | `/admin/` | Security headers on the admin panel document | 200, identical header set to #1 | warm |
  | 3 | GET | `/api/v1/auth/identity` | Security headers on an unauthenticated API path | 204 (anonymous, ADR-030), identical header set | warm |
  | 4 | OPTIONS | `/api/v1/auth/identity` | CORS preflight from a disallowed origin (`https://evil.example.com`) | 403, no `Access-Control-Allow-Origin` echoed for that origin | warm |
  | 5 | GET | `/openapi` | OpenAPI surface reachability in prod | 404 | warm |
  | 6 | GET | `/q/swagger-ui/` | Swagger UI reachability in prod | 404 | warm |
  | 7 | GET | `/q/dev/` | Quarkus dev UI reachability in prod | 404 | warm |
  | 8 | GET | `/q/health` | Health endpoint reachability in prod | 404 | warm |
  | 9 | GET | `/.well-known/assetlinks.json` | Android App Links association reachability | 404 (unconfigured today — corroborates F2) | warm |
  | 10 | GET | `/.well-known/apple-app-site-association` | Apple App Links association reachability | 404 (unconfigured today — corroborates F2) | warm |
  | 11 | GET | `/admin/assets/index-B6vlUAQw.js` | Whether a hashed admin static asset gets the same headers as the document (spare budget) | 200, identical header set to #1/#2, plus `cache-control: public, immutable, max-age=86400` | warm |

  Request #12 (the reserved cookie-attribute read) was **deliberately not spent**: every cookie
  jZen sets (`zen_access_token`, `zen_refresh_token`, `XSRF-TOKEN`) is issued only from
  `AuthResource`'s login/register success path, per `SessionService.csrfCookie`'s single call site
  (`AuthResource.java:364`) — there is no unauthenticated GET that produces a `Set-Cookie` header to
  read, and plan §4.2/§4.3 forbid a `POST` (login) against production to manufacture one. Cookie
  attributes stay verified statically from `SessionService.java` (Phase 3) and are deferred to
  Phase 8's local container, which can log in against a disposable local Supabase account.
- **Tools:** none run yet. Phase 8 is the only phase that runs a scanner (an OWASP ZAP baseline
  passive scan against the local container) and it will be recorded here by name, version and
  configuration when it runs.
- **What was NOT assessed (as of Phase 7):** Phases 8–9 have not started. Phase 4, like Phases 1–3,
  ran no `@QuarkusTest` and no `gcloud` or network read against production; it is a static read of
  the transport-seam code cited in §3.5, plus one local, read-only `mvnw dependency:tree` run (both
  with and without `-Dnative`) to confirm the OpenAPI/Jackson dependency questions rather than trust
  a grep of `pom.xml` alone. It did **not** empirically fuzz either codec path with oversized or
  malformed bodies, measure JSON/protobuf recursion-depth behaviour under an actual attack payload,
  or force a `quarkus-rest-jackson` regression to observe the 500 CLAUDE.md describes — those need a
  running server and are named as open items in §3.5 for Phase 8. Phase 5 is likewise a static read
  — no `task run:supabase`, no `@QuarkusTest` run this session, no `gcloud` or network read — relying
  instead on `DatabasePrivilegeTest`'s existing, already-passing assertions (read, not re-run) and
  the live-database measurements already recorded in ADR-031/036/037/041 (taken 2026-08-04/14
  against the hosted project and a throwaway Postgres respectively), which this phase treats as
  evidence rather than reproducing. It did **not** independently re-run the grant enumeration against
  a fresh local Supabase stack, and it did **not** probe the hosted Data API (plan §4.4, an owner
  decision, unchanged). Phase 6 read `.github/workflows/ci.yml`, `.github/workflows/audit.yml`,
  `.github/dependabot.yml`, the Dockerfile, and ADR-039/ADR-043 as its primary sources, and made a
  bounded number of **read-only `gcloud`/`gh` control-plane calls** — `gcloud artifacts
  repositories`/`docker images list`, `gcloud artifacts repositories get-iam-policy`, `gcloud
  projects get-iam-policy`, `gh api repos/.../security_and_analysis`, `gh secret list`, `gh api
  .../branches/main/protection` — all metadata reads against `jzen-prod` and the GitHub repository,
  none costing the production HTTP request budget (plan §4.3, which reserves that budget for reads
  against the deployed *service*, not the control plane) and none a mutation. It did **not** run
  `task audit` itself this phase (its cadence and last-clean result are read from ADR-039 and
  `audit.yml`'s own configuration, not re-executed), and it did **not** attempt to force an
  unpinned-action supply-chain compromise or any other dynamic proof — Phase 6 is static-plus-reads,
  consistent with Phases 0–5. Phase 7 read `client/zen_secure_store`, `client/zen_identity`,
  `client/zen_core`, `scripts/verify-boundaries.py`, `SecurityHeaders.java`, `CorsCredentialsGuard.java`,
  `admin/src/{authProvider,dataProvider}.ts`, `apps/zen_demo/zen_demo_admin/src/App.tsx`, the native
  Android/iOS/macOS platform-channel files, and the relevant `DECISIONS.md` entries; it grepped the
  **already-staged** production web and admin bundles under
  `apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources` (built 2026-08-17, not
  rebuilt this phase — `task build:web` was not re-run, so a secret introduced after that build date
  would not be caught by this grep) for provider hosts/keys/`eyJ`-shaped tokens, and read
  `react-admin`'s own telemetry source under `admin/node_modules/.pnpm/...`/`ra-core`. It spent 11 of
  the production-read budget (above) and made **no** `gcloud`/`gh` control-plane calls (Phase 6
  already exhausted that surface's open questions). It did **not** run `task build:web` fresh, did
  **not** open a real browser against the live admin panel to observe a CSP violation in the console
  directly (the marmelab telemetry call in **F7** below is reasoned from `SecurityHeaders.java`'s
  `img-src` directive and `ra-core`'s own source, not watched failing live — deferred to Phase 8),
  and did **not** independently wire-verify cookie attributes (see the ledger note above; deferred to
  Phase 8's local container). This line is updated as each phase closes; "not assessed" is an honest,
  acceptable entry per chapter (plan §2.3), an *unmarked* one is not.

---

## Standards versions

Per plan §2.1: every version below was fetched and recorded before any requirement is cited; none is
cited from memory. If a later phase finds an artifact superseded between now and execution, the
successor is used and the change is noted here.

| Artifact | Governs (plan §2.2) | Version in force | Released | URL | Date read |
|---|---|---|---|---|---|
| **OWASP ASVS** | Whole system, requirement-by-requirement — the spine. Level **2** (§2.3). | **5.0.0** (`v5.0.0_release`) | 2025-05-30 | https://github.com/OWASP/ASVS/releases | 2026-09-18 |
| **OWASP API Security Top 10** | REST + WebSocket surface (`AdminUserResource`, `/api/v1/jobs/trigger`, `/api/v1/demo/ws`) | **2023** edition (API1:2023–API10:2023) | 2023 | https://owasp.org/API-Security/ (→ https://api-security.owasp.org/) | 2026-09-18 |
| **OWASP MASVS** | Flutter client (mobile + web); token storage | **2.1.0** | 2024-01-18 | https://github.com/OWASP/owasp-masvs/releases | 2026-09-18 |
| **OWASP MASTG** | Test procedures for MASVS | **2.0.0** | 2026-06-30 | https://github.com/OWASP/owasp-mastg/releases | 2026-09-18 |
| **OWASP Top 10 CI/CD Security Risks** | GitHub Actions, `deploy:cloudrun`, Artifact Registry (CICD-SEC-1..10) | **v1.0** (stable) — no later version published | initial 2022-09, stable 2022-10 | https://owasp.github.io/www-project-top-10-ci-cd-security-risks/ | 2026-09-18 |
| **OWASP Top 10** (web) | Framing/vocabulary only — a prevalence ranking, not coverage (plan §2.2) | **2025** edition | 2025 | https://owasp.org/www-project-top-ten/ | 2026-09-18 |
| **OWASP Proactive Controls** | Design-time guidance | **v10, 2024** edition | 2024 | https://top10proactive.owasp.org/ | 2026-09-18 |
| **OWASP Cheat Sheet Series** | Session Management, JWT, CSRF, WebSocket, Cookie Theft, CSP — cited per-sheet in Phases 3–4, not a single versioned document | living wiki, no single version | — | https://cheatsheetseries.owasp.org/ | to be cited per-sheet when used |

**Not OWASP, checked per plan §2.2's "2026 practices" list in the relevant phase rather than versioned
here:** SLSA (build provenance, Phase 6), a generated SBOM — CycloneDX or SPDX (Phase 6), container
image signing (Phase 6), workload identity federation vs long-lived service-account keys (Phase 6),
dependency pinning by digest (Phase 6), secret scanning with push protection (Phase 6), `__Host-`
cookie prefixes (Phase 3/7), `Permissions-Policy`/COOP/COEP/CORP (Phase 7), CSP nonces/Trusted Types
(Phase 7), and current OAuth 2.1 guidance against the email-link flow, ADR-018 (Phase 3).

---

## 1. Summary

*Not started — Phase 9 produces the ranked list.*

## 2. Trust boundaries and the threat model

### 2.1 Assets, ranked

Confirmed against code, not inherited from the plan's candidate list (plan §Phase 1). Ranked by what
an attacker gets, highest first.

| # | Asset | What holding it gets an attacker | Where it lives |
|---|---|---|---|
| A1 | Supabase JWT signing authority (GoTrue's private key) | Forge a session as *any* user, including admin, without touching jZen at all | Supabase-hosted; jZen only holds the public JWKS |
| A2 | `zen_access_token` cookie (a live JWT) | Impersonate one user for up to 1h (`SessionService.ACCESS_TOKEN_TTL`) | httpOnly cookie, browser/native jar |
| A3 | `zen_refresh_token` cookie | Mint new access tokens for 7 days (`REFRESH_TOKEN_TTL`), rotates on use | httpOnly cookie, browser/native jar |
| A4 | `ZEN_JOBS_TRIGGER_TOKEN` (`zen.jobs.trigger.token`) | Fire `/api/v1/jobs/trigger` at will — the endpoint that anonymises accounts (ADR-008); a data-destructive primitive, not read access | GCP secret → env var; compared constant-time in `JobTriggerAuthenticator` |
| A5 | The `users` table (email + `role` column) | Read every account's email; a write reaches privilege escalation directly, since `RoleAugmentor` trusts this column, never the JWT | Postgres, owned by `zen_runtime` post-cutover (ADR-037) |
| A6 | The admin role itself | Everything `AdminUserResource` exposes: list/update every user, including granting further admin roles | Granted via A5's `role` column |
| A7 | Application DB credential (`zen_runtime`, post-cutover) | Read/write the `public` schema only — no `auth`, no DDL, no Data API role membership (ADR-031/037) | GCP secret |
| A8 | DDL DB credential (Flyway's connection) | Full schema-owner rights during migration; broader blast radius than A7 if it leaked, since it is what *creates* A7's boundary | GCP secret, used only at deploy (ADR-037/038) |
| A9 | Artifact Registry push credential / CI→GCP auth | Push a poisoned image that Cloud Run then serves as production | GitHub Actions secret or workload identity (Phase 6 establishes which) |
| A10 | The GCP project itself | Every secret above, plus billing and the ability to redeploy anything | `gcloud` — owner-controlled |
| A11 | CSRF token (`XSRF-TOKEN`) | Nothing alone (it defends, it is not a credential); listed because `CsrfFilter` treats it as secret-shaped (constant-time compare) even though it is JS-readable by design | Non-httpOnly cookie |

A5/A6 are one asset in two forms: the `role` column *is* the admin role. That collapse — no
separate roles table, no capability token — is why B9 (admin panel → `/api/v1/admin/*`) and B5
(Data API → the same Postgres) both terminate on the identical row, and why Phase 5's privilege-split
review and Phase 3's BFLA review are checking two paths to the same asset.

### 2.2 Trust boundaries

Nine boundaries, confirmed against the code cited rather than assumed from the plan's list.

| # | Boundary | What crosses it | What authenticates the crossing | On failure |
|---|---|---|---|---|
| B1 | Browser/mobile → Cloud Run | Every client request | `zen_access_token` cookie, verified ES256 against JWKS; anonymous if absent/invalid | `SessionCookieAuthenticationMechanism` treats an unverifiable cookie as anonymous, not an error (ADR-030) — the request proceeds unauthenticated rather than 500ing |
| B2 | Cloud Run → Supabase GoTrue | Login, token refresh, logout, password-reset calls | Outbound only; jZen's `SUPABASE_KEY` (service key) authenticates jZen *to* Supabase | `SupabaseAuthClient` surfaces a `ZenError`, not a silent fallback (CLAUDE.md "nothing swallows a failure") — confirmed by inspection, not yet by a forced-failure test (Phase 3) |
| B3 | Cloud Run → Postgres, cross-region, via the session pooler | Every DB-backed request | `zen_runtime` (app) or the DDL role (migration-time only), password-authenticated | Connection failure surfaces as a 5xx; no fallback to a wider role exists in code |
| B4 | Cloud Scheduler → `POST /api/v1/jobs/trigger` | The retention/anonymisation trigger | `X-Zen-Job-Token` compared constant-time (`JobTriggerAuthenticator`) | **Fails closed by construction**: an unconfigured secret rejects *every* call (`expected == null → false`), not the reverse |
| B5 | Internet → Supabase Data API (PostgREST) → the same Postgres | Nothing, if `R__identity_data_api_lockdown.sql` holds — this boundary is meant to carry zero traffic | The Supabase anon/service key, issued by Supabase, never by jZen | Two independent layers (default-privilege revoke + per-table RLS); neither is the other's backstop per the migration's own header — Phase 5 verifies both hold locally |
| B6 | Email link → browser → the app | A live access **and** refresh token, in the URL fragment (ADR-018, implicit flow) | `RedirectTargets` exact-match allowlist constrains *where* Supabase may send it; nothing constrains *who* can read it once it lands (fragment is never sent to the server, but is visible to anything sharing the browser/device, a scheme-registration race per `WellKnownResource`'s javadoc, or a link-prefetching mail client) | Rejected target → `400 invalid_redirect`, value never echoed |
| B7 | GitHub Actions → the repository; developer laptop → GCP | CI-executed code, deploy credentials | `ci.yml` pins third-party actions to a commit SHA; `audit.yml` does not (`actions/checkout@v7`, `@v6`, `@v3`, `@v7` — tag refs, confirmed by `grep` above) | Not established this phase — Phase 6 |
| B8 | Framework library → application | Every CDI bean, JAX-RS provider, MapStruct mapper a library contributes | A Jandex index (`jandex-maven-plugin`) in the library's `pom.xml`; nothing enforces its presence at the framework/application seam itself | **Silent**: a missing index means the provider is on the classpath, compiles, and is never instantiated — no error (CLAUDE.md, confirmed in `CsrfFilter`'s own javadoc, which names `CsrfWiringTest` as the only thing that would catch its own absence) |
| B9 | Admin panel → `/api/v1/admin/*` | User list/update, including role grants | `@RolesAllowed(UserRole.Names.ADMIN)` at the class level on `AdminUserResource`, same session cookie as B1, same `RoleAugmentor` role source | Same as B1 — falls through to a role-less identity, then a 403 from `@RolesAllowed` |

Two corrections to the plan's working list, found by reading rather than assumed: B7 is not
uniformly pinned — `ci.yml` pins every third-party action to a commit SHA but `audit.yml` (a
separate, newer workflow) uses mutable tags throughout. That asymmetry is itself worth carrying into
Phase 6 rather than resolving here. And B4's "fails closed" property is stronger than the plan's
framing suggests: it is not merely that a wrong token is rejected, it is that *no configured secret
at all* is the rejecting case, which is the harder property to get right and the one a naive
implementation (e.g. `Optional.orElse("")` compared against an empty presented value) would get
backwards.

### 2.3 Threat model (STRIDE per boundary, live threats only)

Per §5.4 in the plan: an ADR is a decision, not an exemption, so each boundary's threats are assessed
against what the ADR actually argued, not treated as closed because an ADR exists.

| # | Live threat (STRIDE) | Why live, given single-instance/same-origin/no-edge | Out of scope, and why |
|---|---|---|---|
| B1 | **Spoofing** — cookie theft (XSS, device compromise) → session takeover for ≤1h (A2) or 7d (A3, but rotates) | The only network path a client has (STANDARDS "one server"); no WAF/edge to add a second check | **Tampering** in transit: TLS terminates at Cloud Run; MITM is out of scope absent a CA compromise |
| B2 | **Repudiation/DoS** — GoTrue unreachable or slow; does jZen fail closed or hang | Cross-region call on jZen's own critical path (login, refresh) | **Spoofing GoTrue itself**: would require compromising Supabase, out of this review's boundary |
| B3 | **Elevation of privilege** — a leaked `zen_runtime` credential (A7) vs a leaked DDL credential (A8); the ADR-031/037 split is exactly sized to bound this | Cross-region session-pooler connection string is a secret with real exfiltration paths (log line, error message, a compromised dependency) | **SQL injection**: closed ground per predecessor F5 (plan §1); Phase 5 checks only what is new since |
| B4 | **Tampering/Repudiation** — a caller anonymises accounts without authorization; the endpoint is unauthenticated-by-platform (`--allow-unauthenticated`) and authenticated-by-secret only | `--allow-unauthenticated` is required for Cloud Scheduler to reach it at all (no IAM boundary available); this makes the shared secret the *entire* control, not one of several | **DoS via repeated triggering**: the operation is idempotent by design (due-ness from `last_run_at`, ADR-008) |
| B5 | **Information disclosure / Tampering** — the Data API reads or writes `users`/`zen_jobs`/`zen_rate_limit_counters` directly, bypassing every application-layer control (CSRF, rate limiting, RBAC) at once | This is the boundary the migration's own header calls out as "world-readable and world-WRITABLE over HTTPS, and nothing in the application can tell" if the revoke is missing or incomplete for a *new* table — the exact failure mode Phase 5 must re-verify | Probing the **hosted** project for this — owner decision 2026-08-13 (plan §4.4); verified locally only |
| B6 | **Spoofing** — a scheme-registration race on native platforms (any app can claim `zendemo://` per RFC 8252 §8.6) intercepts the live tokens in the fragment before the intended app does | `WellKnownResource`'s own javadoc names this as the reason App Links/Universal Links exist; whether they are actually *configured* (vs. merely available) is unverified this phase | Supabase's email delivery/SMTP security — outside jZen's boundary |
| B7 | **Tampering** — a compromised third-party GitHub Action mutates the build; `audit.yml`'s unpinned tags (`@v7`, `@v6`, `@v3`) are a live version of exactly this, `ci.yml`'s SHA-pinned ones are not | A tag can be force-moved by the upstream maintainer or, if the maintainer's account is compromised, by an attacker; a SHA cannot | Full supply-chain characterization (SBOM, signing, provenance) — Phase 6 |
| B8 | **Repudiation** — a new library module omits `jandex-maven-plugin` and its security-relevant provider (a filter, a mapper) silently never runs, with a green build and a green test suite everywhere except the one wiring test written for that specific class | This is jZen's named signature defect class (plan §1); CLAUDE.md already documents three instances found the hard way | Runtime classloading attacks on the JVM itself — out of jZen's threat model |
| B9 | **Elevation of privilege** — BFLA: does every mutating method on `AdminUserResource` (and any sibling admin resource added later) carry `@RolesAllowed`, or does the class-level annotation get bypassed by a method-level `@PermitAll` added for a debug/test path and never removed | Highest-privilege surface in the system by construction (A6); Phase 3 enumerates every method, this phase only confirms the mechanism exists | XSS *within* react-admin's own dependency tree — Phase 7 |

**Explicitly out of scope, system-wide** (single-instance, same-origin, no-edge, one-tenant, per
plan §5.5's ranking formula and the invariants in §7.1): horizontal scaling races, multi-tenant
isolation, a compromised CDN/WAF (none exists — ADR-027), DDoS beyond `--max-instances=1`'s own
ceiling (accepted residual, ADR-027), and cross-instance state consistency (no second instance
exists by design, ADR-028/029).

### 2.4 Boundary diagram

```
                              ┌─────────────────────────┐
                              │   GCP project (A10)      │
   Developer laptop ─B7──────▶│  ┌────────────────────┐  │
   GitHub Actions   ─B7──────▶│  │ Artifact Registry   │  │
                              │  │  (A9 push cred)      │  │
                              │  └─────────┬──────────┘  │
                              │            │ deploys      │
   Cloud Scheduler ──B4──────▶│  ┌─────────▼──────────┐  │        ┌──────────────────┐
     (A4 job token)           │  │   Cloud Run          │──B2────▶│ Supabase GoTrue   │
                              │  │  zen_demo_server      │         │  (A1 JWT signing) │
   Browser/mobile ───B1──────▶│  │  --max-instances=1    │  │      └──────────────────┘
     (A2/A3 cookies)          │  │                        │  │
   Admin panel ──────B9──────▶│  │  ┌──────────────────┐ │  │
     (same B1 path)           │  │  │ zen-transport      │ │  │
                              │  │  │ zen-identity   ◀───┼─┼──── B8: framework → app
                              │  │  │ zen-ratelimit      │ │  │      (Jandex-gated,
                              │  │  │ zen-jobs           │ │  │       silent if absent)
                              │  │  └──────────────────┘ │  │
                              │  └─────────┬──────────┘  │
                              │            │ B3 (session pooler, cross-region)
                              │            ▼              │
   Email link ──────B6───────▶│  ┌────────────────────┐  │
     (fragment tokens,        │  │   Postgres            │  │
      RFC 8252 scheme race)   │  │  users (A5/A6)        │  │
                              │  │  zen_jobs             │  │
                              │  └─────────┬──────────┘  │
                              │            ▲              │
   Internet ─────────B5──────▶│  ┌─────────┴──────────┐  │
   (anon/service key,         │  │ Supabase Data API    │  │
    should carry NO traffic)  │  │  (PostgREST)          │  │
                              │  └────────────────────┘  │
                              └─────────────────────────┘
```

## 3. Architectural findings

### 3.1 Part A — Control inventory

Populated from the modules cited in the plan, not from docs. "Inherited?" means: does a second jZen
application (ADR-026) get this the moment it adds the dependency and runs `jandex-maven-plugin`, or
must it additionally remember to configure, wire, or copy something.

| Control | Code | Tests | Inherited by a new app? | Fails open or closed if absent/misconfigured? | Silent? |
|---|---|---|---|---|---|
| `SecurityHeaders` (CSP/HSTS/frame headers on `/`, `/admin/`, API) | `zen-transport/SecurityHeaders.java`, `@Observes Router` at `MIN_VALUE` | `SecurityHeadersTest`, `SecurityHeadersWiringTest`, `SecurityHeadersBehindProxyTest` (app) | Yes — dependency + Jandex only | **Open.** Missing Jandex → bean never discovered → no headers, no error | **Yes**, by the class's own javadoc |
| `StaticCacheHeaders` | `zen-transport`, same Vert.x-route pattern | `StaticCacheHeadersWiringTest` (app) | Yes | Open, same mechanism as above | Yes |
| `CorsCredentialsGuard` | `zen-transport` | `CorsCredentialsGuardTest`, `CorsCredentialsGuardWiringTest` (app) | Yes | Open (Jandex-gated `@Provider`) | Yes |
| `ZenTransportFilter` (transport negotiation) | `zen-transport`, `@PreMatching @Provider` | `ZenTransportHeadersTest`, `ZenTransportFormatTest` (app) | Yes | Not verified this phase what an absent filter defaults `Accept` to | Not verified |
| Proto/ProtoJson `MessageBodyReader`/`Writer` | `zen-transport` | `ZenTransportFormatTest`, `InvalidBodyExceptionMapperTest` (app) | Yes | Malformed body → `InvalidBodyExceptionMapper` → `ZenError` (by test name; mapper body not re-read this phase) | Not silent — a mapper exists and is named in a test |
| `CsrfFilter` + `CsrfRules` | `zen-identity` | `CsrfFilterTest`, `CsrfRulesTest`, `CsrfWiringTest` (app) | Yes | **Closed by default shape**: `CsrfRules` is a closed exemption enum — a new endpoint is protected unless explicitly added to the exempt set, i.e. the secure default is "protected" | Wiring absence would be silent (Jandex), but the exemption list itself is not |
| `RateLimitFilter` + `RateLimitRule` | `zen-ratelimit` | `BurstLimiterTest`, `RateLimitRuleTest`, `RateLimitEnforcementTest`, `RateLimitWiringTest`, `RateLimitCsrfOrderingTest` (app) | Yes, and **new endpoints are covered without any app action**: `RateLimitRule.resolve` buckets `JOB_TRIGGER` and `AUTH` by exact path and puts *everything else under `/api/`* in `GLOBAL` — confirmed by reading `RateLimitRule.java` this phase | Jandex-gated open failure for the mechanism itself; the bucket design is fail-safe once wired | Wiring silent; bucketing is not |
| `JobTriggerAuthenticator` | `zen-jobs` | `JobTriggerAuthenticatorTest`, `JobTriggerResourceTest` (app) | **No** — `ZEN_JOBS_TRIGGER_TOKEN` is an app-provisioned secret; the mechanism ships, the credential does not | **Closed**: `expected == null → false` rejects every call when unconfigured (re-confirmed, Phase 1 finding) | Not silent — every call is rejected, which is itself the signal |
| `SessionCookieAuthenticationMechanism` / `SessionService` | `zen-identity` | `ExpiredSessionCookieTest` (app); no dedicated unit test found under `zen-identity/src/test` this phase | Yes | Deliberately **open to anonymous** on an unverifiable cookie (ADR-030) | Documented in the ADR, not silent, but easy to misread as "auth failed loudly" when it instead degrades to anonymous |
| `RoleAugmentor` / `UserRoleLoader` | `zen-identity` | `RoleAugmentorTest` (app), `UserRoleLoaderLatchTest` | Yes | Resolution failure → role-less identity (closed on privilege); not independently re-verified this phase | Not assessed this phase |
| `AdminUserResource` | `zen-identity`, reusable framework resource | `AdminUserResourceTest`, `AdminUserRangeTest` (app) | Yes, and **unconditionally** — the highest-privilege JAX-RS surface in the system arrives the moment `zen-identity` is on the classpath; whether an app can opt *out* of exposing it was not checked this phase | Class-level `@RolesAllowed(ADMIN)`, confirmed — no method-level override found in the file | Not silent (annotation present, verified by direct read) |
| Framework Flyway migrations (`V1__init_identity`, `R__identity_application_role`, `R__identity_data_api_lockdown`, `V100__init_jobs`, `R__jobs_row_level_security`, `V200__init_rate_limit`, `R__ratelimit_row_level_security`) | `zen-identity`, `zen-jobs`, `zen-ratelimit`, each under `src/main/resources/db/migration` | `DatabasePrivilegeTest` (app) | **Yes, automatically** — `quarkus.flyway.locations=db/migration` is a classpath location, and Flyway merges every jar's `db/migration/` on the classpath; `zen_demo_server` ships **no migrations of its own** (confirmed: no `db/migration` directory in the app), so every table, every RLS policy and the Data API lockdown arrive purely from the framework dependency | The repeatable (`R__`) ones re-assert on every deploy by construction — a real strength (ADR-036's reasoning depends on exactly this) | Not silent — Flyway logs every applied migration |
| `UserRetentionService` / `UserRetentionJob` (GDPR retention) | `zen-identity` | `UserRetentionTest`, `UserRetentionCutoffTest`, `RetentionBatchingTest`, `RetentionDeliveryGateTest` (app) | **Partially.** The code and the no-erasure-without-delivered-warning logic are inherited; the *schedule* is not — nothing runs it unless the app also provisions Cloud Scheduler → `POST /api/v1/jobs/trigger` with a matching `ZEN_JOBS_TRIGGER_TOKEN` (see B4) | If the trigger is never wired, retention silently never runs — accounts simply age forever with no warning and no erasure | **New candidate silent no-op** (§3.2 below) — a fourth instance, not one of the three `CLAUDE.md` already names |

**The inheritance risk runs in both directions**, not only "an app forgets to add something": `AdminUserResource` shows the opposite failure mode — an app gets the entire admin surface *whether it wants it or not* the moment `zen-identity` is a dependency, and whether that surface can be selectively disabled per-app is an open question this phase did not answer.

### 3.2 Part B — The silent-no-op census

**Jandex coverage, checked directly** (the plan's own script, run this phase):

```
server/zen-core          beans:0 jandex:0
server/zen-email         beans:1 jandex:1
server/zen-identity      beans:16 jandex:1
server/zen-jobs          beans:3 jandex:1
server/zen-proto         beans:0 jandex:0
server/zen-ratelimit     beans:6 jandex:1
server/zen-transport     beans:13 jandex:1
```

Every module that contributes a CDI bean or JAX-RS provider has `jandex-maven-plugin`; `zen-core` and
`zen-proto` correctly have neither. **This specific census is currently clean** — a "closed, verified"
line for §6, not a finding — but it says nothing about the *next* module added, which is exactly what
makes the pattern worth re-running rather than trusting from memory.

**Four silent-no-op mechanisms are now named** (three from `CLAUDE.md`, one new this phase):

1. A library module missing `jandex-maven-plugin` (`CLAUDE.md`, re-confirmed clean above).
2. A client reaching Supabase directly (`CLAUDE.md`; `verify:boundaries` is the gate — see §3.3).
3. `quarkus-rest-jackson` present server-side (`CLAUDE.md`; not independently re-verified this phase —
   deferred to Phase 4, which the plan already assigns it to).
4. **New: an app that never wires Cloud Scheduler → `/api/v1/jobs/trigger`.** `UserRetentionService`'s
   code ships and compiles whether or not anything ever calls it. There is no health check, no
   metric, and no test that fails when the trigger is simply never configured — `JobTriggerAuthenticatorTest`
   and `JobTriggerResourceTest` both exercise the endpoint *being called*, not the absence of a caller.
   An app can therefore satisfy GDPR Art. 5(1)(e) in code review while never actually running
   retention in production, and nothing in the gate suite would say so. Candidate scope: framework
   documentation plus, possibly, a boot-time or health-check warning if the trigger token is
   configured but Cloud Scheduler has never called it within some window — not designed this phase,
   named as a Phase-2 finding for Phase 5/9 to price.

**The paper attack — could an app stay green while being insecure?** Attempted on paper, not built:

- *Skip `SecurityHeaders`*: cannot be done by omission (it is Jandex-inherited automatically), only by
  actively excluding `zen-transport` from the app's dependency tree — but the app has no server
  without it (it is where the transport seam lives), so this is not a realistic path.
- *Register a competing `MessageBodyWriter` for `application/json`*: nothing in the framework detects
  a second writer claiming the same media type; SmallRye/RESTEasy Reactive's own provider-priority
  rules would decide, silently, which one wins. **Not verified this phase** whether jZen has a test
  that would catch this — candidate for Phase 4's parser review.
- *Add `quarkus-rest-jackson` for one endpoint*: `CLAUDE.md` documents this as the reason the
  dependency must be *absent*, not merely deprioritized, because Jackson's writer claims
  `application/json` through a build-time path that ignores writer priority. Re-verifying it is still
  absent is Phase 4's job, not repeated here.
- *Define a resource under `/api/` that the rate limiter's bucket enum doesn't expect*: cannot bypass
  `RateLimitFilter` this way — confirmed above, everything under `/api/` not explicitly named falls to
  `GLOBAL`. This path is closed by design, not merely by accident.
- *Create a new table without extending the Data API lockdown*: `R__identity_data_api_lockdown.sql`
  is repeatable and, per its own header (read in Phase 0), revokes default privileges — whether that
  default-privilege revoke actually covers a table created by a migration that runs *after* it is a
  Phase 5 question (ordering matters and was not re-verified this phase).
- *Add a platform-channel network call in Kotlin/Swift*: **this one succeeds.** See §3.3 — the gate
  that is supposed to catch a client bypassing the one-server rule does not scan native platform
  code at all.

### 3.3 Part C — Gate audit

| Gate | What it actually checks | What its name implies but it does not check | Can it pass having checked nothing? |
|---|---|---|---|
| `verify:boundaries` (`scripts/verify-boundaries.py`, read in full this phase) | Three regex-based checks — no provider SDK in `pubspec.yaml`/`package.json`, no provider host/credential string, no absolute-URL literal — scoped to `client/*/lib`, `apps/*/*/lib` (Dart) and `admin/src`, `apps/*/*_admin/src` (TypeScript `.ts`/`.tsx`), generated code excluded | **Kotlin and Swift platform-channel code** (`apps/zen_demo/zen_demo_client/android/**/*.kt`, `ios/**/*.swift`, `macos/**/*.swift` — confirmed present, currently boilerplate) is never scanned. A native plugin implementation that called Supabase directly from a platform channel would pass this gate cleanly. This matches the plan's own speculation (§Phase 2) and is now confirmed rather than assumed. | **No** for the scopes it does cover — `StaleScope` deliberately fails the gate if a glob matches nothing, which is itself a defence against the exact "silent pass" pattern ADR-034 found in `ossindex-maven-plugin`. The gap is a coverage gap, not a "passes while checking nothing" defect. |
| `verify:docs` | Two mechanically-checkable drift rules (a README task-name reference exists in `task --list`; a module `LICENSE` matches root) | Everything else a README claims — behavioural accuracy, security-relevant statements about a task's effect | Passes on repositories with correct task names and licences regardless of whether the prose around them is true |
| `verify:contracts` (`sync:contracts` before ADR-049) | Regenerates Java DTOs, Dart messages, `openapi.json`, admin TypeScript and typed l10n, fails on drift from the tracked output | Whether the *contract itself* is secure (e.g., an overly permissive field) — it is a drift gate, not a design review | No — regeneration either matches tracked output or it does not |
| `audit` (`task audit`, `.github/workflows/audit.yml` read this phase) | Java (OSV), TypeScript and Dart dependencies against known CVEs; **confirmed actually wired** — a weekly cron (`17 6 * * 1`) plus `workflow_dispatch`, not merely described in ADR-034/039 as intended. This resolves §8's Q4 as answered rather than open. | New advisories between runs (up to a week of exposure by design — a deliberate trade-off, not a defect) | No — it queries a real remote service and fails on a real match (ADR-034 precedent: it already caught two HIGH advisories once) |
| `test:e2e` | Real Supabase + Quarkus, no mocks: register/login/logout, a typed round trip in both transport modes, the WebSocket echo, a `ZenError` path | It is a **functional** happy/typed-path suite, not a security suite — no malformed input, no auth-bypass attempt, no expired/tampered cookie in this gate (those live in `ExpiredSessionCookieTest`, a separate `@QuarkusTest`, not in `test:e2e` itself) | No — it is a real integration run against a real stack, but its green result answers a narrower question than "the security-relevant paths work," and a reader of the task name alone could over-read it |

**Deliverable check against the plan:** control inventory ✓ (§3.1, 13 controls). Silent-no-op census ✓
(§3.2 — jandex re-verified clean, four mechanisms named, six paper-attack scenarios attempted, one
succeeds). Gate-coverage table ✓ (§3.3, five gates).

### 3.4 Part D — Phase 3: Identity, session, authorization

ASVS session-management/access-control chapters plus API Top 10 BOLA/BFLA, per the plan's Phase 3
question list. Answered from code read this phase — `SessionService.java`,
`SessionCookieAuthenticationMechanism.java`, `RoleAugmentor.java`, `UserRoleLoader.java`,
`CsrfRules.java`, `CsrfFilter.java`, `RedirectTargets.java`, `WellKnownResource.java`,
`AuthResource.java`, `IdentityService.java`, `AdminUserResource.java`, `DemoResource.java`,
`DemoWebSocket.java` — plus `application.properties`'s JWT/session block, the native client's
`AndroidManifest.xml`/`Info.plist`, and `Taskfile.yml`'s deploy documentation for App Links.

| Question (plan §Phase 3) | Answer, with evidence |
|---|---|
| Cookie attributes, end to end | All four cookies (`zen_access_token`, `zen_refresh_token`, `XSRF-TOKEN`, and the generic `clearCookie`) are `Path=/`, `SameSite=Lax`, `Secure` in every profile but `%dev`/`%test` (`session.cookie.secure`, defaulted `true`, overridden `false` only there). **None carries the `__Host-` prefix.** Not re-verified from the wire this phase (Phase 7/8's job); read from `SessionService.java` directly. |
| Token lifetimes, rotation, revocation | Access 1h, refresh 7d, refresh rotates on every Supabase `/token` call (code comment, not independently wire-verified). Logout and password-change both call upstream revocation and treat its failure as logged-but-non-fatal — `IdentityService.revoke()` — a **documented, priced** risk (the session stays live upstream for up to 7 days if Supabase is unreachable at the moment of revocation), not a silent one: the javadoc states the exposure explicitly and the WARN log line is the signal. |
| JWT verification | ES256 against JWKS (`mp.jwt.verify.publickey.location`), issuer pinned to `${SUPABASE_URL}/auth/v1`. `smallrye.jwt.jwks.cache-time-to-live=10800` (3h) / `refresh-interval=3600` (1h). **No explicit clock-skew property is set** — SmallRye JWT's own default applies, unconfirmed this phase. **What happens when JWKS is unreachable was not tested**; reasoned from code: `SessionCookieAuthenticationMechanism` recovers any `AuthenticationFailedException` — which a failed JWKS fetch would produce — into an anonymous identity, so a JWKS outage degrades every session to anonymous rather than 5xx. That is fail-closed on authorization (no forged identity is ever accepted) but **silently mass-signs-out every session** for the outage's duration, bounded below by the 1h/3h cache — and nothing observed this phase logs, alerts, or distinguishes that from ordinary token expiry (`SessionCookieAuthenticationMechanism`'s own javadoc: logged at DEBUG, deliberately, to avoid amplification). Recorded as an open question for Phase 8, not asserted as a finding — it was not forced and observed. |
| Role resolution | `RoleAugmentor` reads the `users.role` column fresh on **every** authenticated request (no cache, no token claim) via `UserRoleLoader`, so a role change or a failed load (caught, logged at WARN, degrades to the unaugmented identity — closed on privilege) takes effect on the very next request. Revocation latency is therefore effectively zero on the HTTP surface. **Confirmed exception: the WebSocket** — see F1 below. |
| **BOLA** | `AdminUserResource` is gated `@RolesAllowed(ADMIN)` and its `/{id}` path takes a client-supplied id by design (an admin operating on any user is the function, not a bug). `DemoResource.profile()` and `IdentityService.currentUser(UUID)` never take a client-supplied id — both resolve strictly from `securityIdentity.getPrincipal()`, and `currentUser`'s own javadoc states the identity match is on the id, never merely on attribute presence. **No BOLA path found** across the three resources the plan names. |
| **BFLA** | Every mutating (non-GET/HEAD/OPTIONS) endpoint enumerated: `AdminUserResource.update` — class-level `@RolesAllowed(ADMIN)`, no method-level override. `AuthResource` — `login`/`register`/`restore-password`/`session`/`logout` are `@PermitAll` by necessity (no session yet, or ending one that may already be gone); `password` is `@Authenticated`; `refresh` is `@PermitAll` but its credential is the refresh cookie, checked inside `IdentityService.refresh`. `JobTriggerResource` (not re-read this phase, per Phase 2's inventory) is `@PermitAll` and secret-gated. **No unannotated mutating endpoint found.** With `quarkus.http.auth.proactive=true`, an unannotated endpoint would default to whatever the identity resolves to (anonymous if no cookie) — moot here since none exists. |
| CSRF | `CsrfRules.applies` is a closed allowlist of **safe methods** (`GET`/`HEAD`/`OPTIONS`) union a closed **exemption set** of six paths, each justified in the class javadoc. **The default is protected**: a new mutating `/api/` endpoint is covered automatically unless someone deliberately adds it to `EXEMPT_PATHS` — confirmed by reading the boolean logic directly (`§3.4`'s own read, not inherited from the javadoc's claim). |
| Open redirect | `RedirectTargets.resolve` is exact-match only, confirmed structurally sound (§3.4). **But its soundness only bounds where a link may point — not who can intercept it once it lands on a native scheme**, which is exactly RFC 8252 §8.6's problem and `WellKnownResource`'s own stated reason to exist. See **F2**. |
| **The email-link flow (B6)** | Tokens travel in the URL fragment (never reaches the server), are exchanged for cookies only after `IdentityService.exchangeLinkTokens` presents the access token to Supabase's own `/user` endpoint (server-side validation of a client-supplied credential — sound). The redirect target is validated before Supabase is ever asked to mail anything (`RedirectTargets.resolve` runs first in `register`/`restorePassword`). The residual risk is squarely the scheme-hijack: `zendemo://auth-callback` is registered today in both `AndroidManifest.xml:39` and `Info.plist:66`, live in the native manifests, not merely a hypothetical from the doc comment. App Links/Universal Links — the mitigation `WellKnownResource`'s own javadoc names as the fix — are optional, unenforced, and default to unset (`APPLINKS_*` all default to empty string in `application.properties`; `Taskfile.yml:2023` labels the whole step "**optional**"). See **F2**. |
| Enumeration and timing | `IdentityService.register` intercepts Supabase's `email_taken`/`user_already_exists` and returns the identical no-session outcome a genuine pending confirmation produces (202, same shape) — confirmed by reading the branch, not by timing measurement. `restorePassword` always returns 204 regardless of whether the email exists. **Not independently timing-tested this phase** (Phase 8); the code path gives both cases the same status code and body shape, which is the structural half of the neutral-202 property, not the timing half. |

**Two findings minted this phase** (this review's own numbering — distinct from the predecessor
`SECURITY-REMEDIATION.md` F1–F20, which are a closed, different document):

```
### F1 — A WebSocket's authorization is checked once, at the handshake, and never again for the connection's life

**Class:** architectural
**Scope:** framework (the pattern — zen-transport's WebSocket integration provides no re-validation
           hook — not `zen_demo`-specific; `DemoWebSocket` is simply today's only instance)
**Confidence:** verified
**Standard:** No single ASVS/API-Top-10 requirement id is cited — the governing chapter is ASVS
              5.0.0's Session Management chapter (session state must not outlive its authorization),
              but the exact clause number was not confirmed against the fetched text this phase, so
              this is reasoned-from-code rather than a mapped citation (plan §2.1's rule against
              citing from memory). Closest named API Top 10 (2023) item: API2 Broken Authentication.
**Boundary:** B1 / B9 (folded into these per Phase 1's grounding — the socket authenticates on the
              same cookie and the same `RoleAugmentor` role source as the HTTP surface)
**Where:** apps/zen_demo/zen_demo_server/src/main/java/zen/demo/DemoWebSocket.java (the pattern is
           framework-level; there is no dedicated zen-transport WebSocket module to point at instead)
**Evidence:** `DemoWebSocket`'s own class javadoc, item 1 of "Four things bound this socket": "the
              handshake is authenticated... enforced during the HTTP upgrade" — no further reference
              to `SecurityIdentity` or a re-check exists anywhere in `onMessage`/`onClose`/the class.
              `RoleAugmentor` (§3.4's Role-resolution row) reloads the role on every HTTP request but
              has no equivalent per-frame hook for a socket, because nothing calls it after upgrade.
**Exploitability today:** Low. Requires a legitimate session to be revoked (logout elsewhere, global
              revoke on password change, an admin demoting the role) *while* a socket stays open —
              the connection keeps functioning as whatever it was authorized for at handshake, for as
              long as the client holds it, with no documented maximum lifetime. For today's only
              instance (an echo endpoint) the practical impact is nil; the concern is the *pattern*
              a second, more sensitive WebSocket resource would inherit unexamined.
**Impact:** A revoked, logged-out, or demoted identity retains a live channel to whatever that
              WebSocket resource does, for the life of the connection.
**Silent?** Yes — no test asserts a message is refused after logout or a role change on an
              already-open socket; nothing logs, meters, or alerts on this state.
**Fix:** Give long-lived sockets an explicit revalidation policy at the framework level: either a
         bounded maximum connection lifetime that forces a reconnect (which re-runs the authenticated
         handshake), or a periodic identity re-check keyed off the captured access token's own
         expiry. Framework-level so a second app inherits it rather than rediscovering the gap.
**What the fix costs:** A max-lifetime approach adds a reconnect burden the client must handle
         gracefully; a periodic re-check adds a DB round trip on a path the rest of the framework
         works to avoid (`RoleAugmentor`'s own javadoc documents a ~135ms cross-region cost it exists
         to eliminate) — there is no free version of this fix.
**Invariant touched:** none (§7.1).
**ADR consequence:** none directly superseded; no existing ADR states a WebSocket revocation policy,
         so a fix would be new ground rather than a reversal.
```

```
### F2 — App Links / Universal Links, the RFC 8252 scheme-hijack mitigation, are optional and nothing ties their absence to the risk that makes them necessary

**Class:** process
**Scope:** application (`zen_demo`'s deploy discipline) — the underlying mechanism
           (`WellKnownResource`, the custom-scheme redirect target) is framework, but the *decision*
           to ship a native build without configuring the mitigation is made per-deploy, per-app
**Confidence:** verified
**Standard:** OWASP MASVS 2.1.0, MASVS-PLATFORM (deep-link/URL-scheme handling) as the governing
              group; no single clause id fetched to the precision the plan's §2.1 rule requires, so
              treat the citation as directional. RFC 8252 §8.6 is the primitive risk it addresses and
              is already cited by `WellKnownResource`'s own javadoc.
**Boundary:** B6
**Where:** Taskfile.yml:2023 ("1a. App Links (optional, and NOT secrets)"),
           server/zen-identity/src/main/java/zen/identity/auth/WellKnownResource.java (serves 404
           until configured — a deliberate, documented default),
           apps/zen_demo/zen_demo_client/android/app/src/main/AndroidManifest.xml:39 and
           apps/zen_demo/zen_demo_client/ios/Runner/Info.plist:66 (the `zendemo://auth-callback`
           scheme is registered today, not hypothetical)
**Evidence:** `Taskfile.yml:2053` states plainly: "Unset is a supported state... The custom scheme
              keeps working either way." `APPLINKS_ANDROID_PACKAGE`/`APPLINKS_ANDROID_FINGERPRINTS`/
              `APPLINKS_APPLE_APP_IDS` all default to empty string in
              `application.properties:30-34`. No script in `Taskfile.yml`'s deploy path checks
              whether `AUTH_REDIRECT_URIS` names a non-`https` scheme while `APPLINKS_*` is unset —
              confirmed by reading the deploy documentation block (lines ~2000–2100) in full; it
              documents the risk in prose but enforces nothing.
**Exploitability today:** Contingent, not demonstrated. Live only once a native build with a
              configured custom-scheme redirect target actually ships to real users; this review
              cannot see from the repository whether that has happened (Phase 6/7 territory — build
              artifacts, App/Play Store listings). What *is* established is that the mechanism the
              mitigation exists for (the registered scheme) is present today in both native shells,
              not merely available in principle.
**Impact:** Per `WellKnownResource`'s own javadoc: a hostile app that wins the scheme race on the
              user's device receives the live access **and** refresh tokens carried in the email
              link's fragment — full account takeover, delivered by the victim's own genuine,
              correctly-addressed email.
**Silent?** Yes — no gate, test, or deploy-time check connects "a native redirect target is
              configured" to "App Links is configured to match it."
**Fix:** Add a check to the same deploy script that already validates the eight PUBLIC configuration
         values (`Taskfile.yml`'s 1a-config step, which the plan's own reading confirms "fails closed
         with the name of whichever is missing"): if `AUTH_REDIRECT_URIS` contains a non-`https`
         scheme and every `APPLINKS_*` value is unset, warn explicitly rather than silently
         succeeding. Framework-level (the check belongs beside `WellKnownResource`'s own reasoning,
         not duplicated per app) so a second application inherits the warning.
**What the fix costs:** Must be a warning, not a hard failure — `Taskfile.yml:2033` already notes
         Apple App IDs require a paid developer account, so a first native deploy legitimately may
         not have App Links ready yet, and a hard gate would block a deploy that has no better option
         available at that moment.
**Invariant touched:** none (§7.1).
**ADR consequence:** none directly superseded; a fix would newly formalize a policy (App Links
         required before, or loudly flagged absent when, a native scheme redirect goes live) that no
         current ADR states either way.
```

**Closed this phase, verified correct with the evidence cited in the question table above** (candidates
for §6, not restated there yet — that section waits for Phase 9's consolidated pass): cookie
`httpOnly`/`Secure`/`SameSite=Lax` attributes as coded; role-resolution revocation latency on the
HTTP surface (effectively zero, read fresh every request); BOLA on `AdminUserResource`,
`DemoResource`, and `IdentityService.currentUser`; BFLA coverage across every enumerated mutating
endpoint; CSRF's exempt-by-exception (protected-by-default) design; `RedirectTargets`' exact-match
soundness as a distinct question from the scheme-hijack it does not claim to solve; the structural
half of the enumeration-resistance property on `register`/`restore-password`.

**Explicitly not done in Phase 3** (deferred to their own phases, per the plan): forcing and
observing JWKS-unreachable behaviour, clock-skew tolerance, and login-timing enumeration resistance
— all need a running server or a running clock (Phase 8); wire-verifying cookie attributes rather
than reading `SessionService.java` (Phase 7/8); confirming whether a native build with a live
scheme redirect has actually shipped to users, which would raise F2 from "contingent" to
"demonstrated" (Phase 6/7); re-deriving `JobTriggerResource`'s CSRF/RolesAllowed status independently
rather than citing Phase 2's inventory (not re-read this phase, no change expected).

### 3.5 Part E — Phase 4: The transport seam and the two parsers

jZen's dual-mode transport is the mechanism no generic OWASP list names (plan §Phase 4). Answered
from code read this phase — `ProtobufMessageBodyReader.java`, `ProtoJsonMessageBodyReader.java`,
`InvalidBodyExceptionMapper.java`, `ZenTransportFilter.java`, `ZenTransportFormat.java`,
`RateLimitFilter.java` (javadoc + `@Priority`), `DemoWebSocket.java`, `WebSocketConnections.java` —
plus `application.properties`'s HTTP-limits and WebSocket blocks, every `proto/zen/v1/*.proto` file
(grepped for `oneof`/`Any`), every non-`target` `pom.xml` (grepped for `jackson`), and two local
`mvnw -f apps/zen_demo/zen_demo_server/pom.xml dependency:tree` runs — with and without `-Dnative` —
to confirm dependency-tree claims from a command rather than from a `pom.xml` read alone.

| Question (plan §Phase 4) | Answer, with evidence |
|---|---|
| Message size limits, each codec | Both codecs share one ceiling: `quarkus.http.limits.max-body-size=1M` (`apps/zen_demo/zen_demo_server/src/main/resources/application.properties:239`), a Vert.x/Quarkus HTTP-server setting — nothing in `zen-transport` itself bounds size. `ProtobufMessageBodyReader.readFrom` (`server/zen-transport/.../ProtobufMessageBodyReader.java:34-36`) calls `builder.mergeFrom(entityStream)` with no override, relying on protobuf-java's own `CodedInputStream` default (64MB, moot beneath the 1M HTTP cap). `ProtoJsonMessageBodyReader` sets no explicit JSON size bound either — it inherits the same 1M ceiling upstream. |
| Recursion / nesting depth | **No explicit override exists in `zen-transport` for either codec** (grepped the package for `recursion`/`nesting`/`depth`: zero hits). Protobuf-java's own default recursion limit (100) applies unmodified to the binary path; the JSON path (`JsonFormat.parser()`, backed by Gson) has no depth limit set by jZen and was not independently forced this phase to observe Gson's own default. Not a finding on its own — the 1M body cap bounds how much nesting a single request can encode — but it is a **structural gap, reasoned not verified**, and is named for Phase 8's "oversized and malformed bodies on both codec paths" dynamic step rather than asserted safe here. |
| Unknown-field handling | `ProtoJsonMessageBodyReader` uses `JsonFormat.parser().ignoringUnknownFields()` (`.../ProtoJsonMessageBodyReader.java:35`), documented at lines 22-29 as a **deliberate** mass-assignment defense — an unrecognised JSON field is dropped, not rejected and not merged into an unrelated one. Protobuf's own wire format has the equivalent behaviour built in (unknown fields are preserved in the unknown-field set, never assigned). |
| `Any` / `oneof` usage | **None.** Every `proto/zen/v1/*.proto` file (`demo.proto`, `jobs.proto`, `health.proto`, `identity.proto`, `admin.proto`, `common.proto`) was grepped for `oneof` and `google.protobuf.Any`; zero matches. The `Any`-based type-confusion and `oneof`-ambiguity classes the plan names are not live attack surface in this schema today — worth re-checking whenever a new `.proto` message is added, not a standing property of the mechanism. |
| Malformed body → what is produced | `InvalidBodyExceptionMapper` (`server/zen-transport/.../InvalidBodyExceptionMapper.java:32-42`) catches `InvalidProtocolBufferException` from either reader (the JSON reader throws this narrower type from `JsonFormat.Parser#merge`, documented in the class's own javadoc as intentional, lines 14-17) and returns HTTP 400 with a fixed `ZenError{code="invalid_body", message="The request body could not be parsed as the negotiated transport format."}` — **confirmed by reading the method body: no field path, no byte offset, no exception class name, no stack trace ever reaches the response.** Matches CLAUDE.md's "nothing swallows a failure" rule without over-disclosing internals. |
| `@PreMatching` ordering vs. `RateLimitFilter` vs. authentication | `ZenTransportFilter` is `@Provider @PreMatching` with **no `@Priority`** (`server/zen-transport/.../ZenTransportFilter.java:21-23`) — pre-matching filters run before resource matching and before every ordinary (post-matching) filter as a structural JAX-RS property, not a priority contest. `RateLimitFilter` is an ordinary `@Provider` with explicit `@Priority(Priorities.AUTHENTICATION - 100)` (`server/zen-ratelimit/.../RateLimitFilter.java:44-45`), whose own javadoc (lines 9-34) states outright that it must run before authentication and `CsrfFilter` so a 429 is charged even against unauthenticated or malformed-credential traffic. Net order: `ZenTransportFilter`'s header rewrite → `RateLimitFilter` → authentication (`quarkus.http.auth.proactive=true`, `application.properties:153`) → `CsrfFilter` → resource method / body parsing. **Actual `MessageBodyReader` parsing happens only inside JAX-RS's invocation of the resource method — after rate limiting and authentication have already had their chance to reject** — so a malicious body cannot reach parser work ahead of the limiter; only `ZenTransportFilter`'s cheap header-string comparison runs pre-limit, which is not a parsing-cost DoS vector. Ordering is pinned by `RateLimitCsrfOrderingTest` (`apps/zen_demo/zen_demo_server/src/test/java/zen/demo/RateLimitCsrfOrderingTest.java:65-81`), which proves the rate limiter charges its bucket before `CsrfFilter` can abort a request. |
| Header-driven dispatch (`X-Zen-Transport`) | `ZenTransportFormat.negotiate` (`server/zen-transport/.../ZenTransportFormat.java:44-63`) resolves in order: explicit `X-Zen-Transport` header (case-insensitive, only `json`/`protobuf` recognised) → Content-Type subtype sniff (**exact** match on `x-protobuf`/`protobuf`, or a `json`/`+json` suffix — not a substring match, so e.g. `text/protobuf-notes` cannot be steered to the binary parser, per the class's own documented intent at lines 42-46) → default JSON. An unrecognised header value falls through to sniffing/default rather than erroring. `ZenTransportFilter` rewrites `Accept` only for paths under `api/` (lines 33-38), so framework endpoints (`/openapi`, `/q/health`) are untouched. Both readers are additionally gated by `@Consumes` media type and `Message.class` assignability, so the header can only choose between the two legitimate proto-message parsers already registered for the matched resource — resource/method selection is independent of this negotiation, so the header cannot redirect a request to an unrelated endpoint. |
| The WebSocket (`/api/v1/demo/ws`) | Frame size: `quarkus.websockets-next.server.max-frame-size=65536` (`application.properties:263`); the same file notes explicitly (lines 255-261) that `max-body-size` does **not** apply to WebSocket frames, so this is a separate, correctly-set limit rather than an assumed inheritance. Connection cap: `WebSocketConnections` (`apps/zen_demo/zen_demo_server/src/main/java/zen/demo/WebSocketConnections.java`) enforces a global cap (default 200, lines 41-42) and a per-address cap (default 20, lines 51-52), both backed by plain `AtomicInteger`/`ConcurrentHashMap` fields (lines 54-55) — **confirmed in-memory, not distributed.** The class's own javadoc (lines 19-29) states this is valid only because `--max-instances=1` gives exactly one instance (ADR-027/029) and that raising `--max-instances` would raise the fleet-wide total proportionally rather than silently breaking — the authors already priced the premise this control depends on. `DemoWebSocket.onOpen` (lines 88-101) checks `Origin` against `quarkus.http.cors.origins` and calls `connections.tryAcquire(remoteAddress)`, closing with 1008/1013 on rejection. Authorization re-validation mid-connection is Phase 3's **F1**, not re-litigated here — Phase 4 only re-confirms the size/connection limits sit alongside that gap, not instead of it. |
| The OpenAPI surface — regression check | `quarkus-smallrye-openapi` is added only by an explicit Maven profile activated on `!native` (`apps/zen_demo/zen_demo_server/pom.xml:283-291`), and production builds pass `-Dnative` (`Taskfile.yml:504`). **Verified by running `dependency:tree` with `-Dnative`**, not merely by reading the profile: `quarkus-smallrye-openapi` does not appear anywhere in the resulting tree. Without `-Dnative` it does appear, as intended (`task generate:api:schema` needs it). No other `server/zen-*` module declares it. **No regression from the Wave 4.2 removal.** |
| The Jackson prohibition | `quarkus-rest-jackson` (the JAX-RS JSON provider that must be *absent*, not merely outranked, per CLAUDE.md) does not appear in any `server/zen-*` or `apps/zen_demo/zen_demo_server` `pom.xml` — confirmed by grepping every non-`target` `pom.xml` for `jackson`. The only real hits: `server/pom.xml:141-142` (a `jackson-bom` import, version-pinning only, documented as removable once upstream Quarkus catches up); `server/zen-identity/pom.xml:73-74` (`quarkus-rest-client-jackson`, the sanctioned **outbound** client provider for Supabase calls); and `server/zen-identity/pom.xml:84-86` (a **direct** `jackson-databind` dependency — not the REST extension — used by `AdminUserResource` to parse inbound `ra-data-simple-rest` query parameters; the accompanying comment argues this does not register a JAX-RS provider and so cannot contest response-writer priority, which matches what was found: no evidence anywhere that a Jackson `MessageBodyWriter` is ever registered). `dependency:tree -Dnative` (run twice this phase, output captured to confirm rather than assumed) additionally surfaces `io.quarkus:quarkus-jackson` (the base Jackson CDI/`ObjectMapper` support module) **and** `io.quarkus:quarkus-rest-jackson-common` plus `io.quarkus.resteasy.reactive:resteasy-reactive-jackson`, all transitively under `quarkus-rest-client-jackson`. The latter two share a name with the forbidden extension but are not it: `quarkus-rest-jackson-common` is shared runtime code between the client and server RESTEasy Reactive Jackson integrations, and the JAX-RS-provider registration itself happens in the **deployment** (build-time augmentation) artifact for `quarkus-rest-jackson`, which does not appear on this tree at all — so this reads as benign on inspection, but it is close enough in name to `quarkus-rest-jackson` that a `grep` for the banned string alone (rather than the exact artifact id) could false-positive on it, or a future reviewer could wave off the real thing by pattern-matching the wrong direction. A Jackson `ObjectMapper` CDI bean does exist server-side either way, which is a slightly wider surface than a literal reading of "Jackson only touches the outbound client call." **No enforcer rule, build check, or test was found anywhere in the inspected modules that would fail if the real `quarkus-rest-jackson` extension were added** — see **F3** below. |

**One finding minted this phase:**

```
### F3 — The no-server-side-Jackson invariant is enforced by convention and code review only; no gate would catch its reintroduction

**Class:** process
**Scope:** framework (the missing gate would apply to any `server/zen-*` module or any future
           `apps/*/zen_*_server`, not to `zen_demo` specifically)
**Confidence:** verified (the absence of a gate) / reasoned-from-code (the failure mode, which is
              CLAUDE.md's own documented account, not independently forced this phase — Phase 8's
              job per plan §Phase 4)
**Standard:** No ASVS/API-Top-10 clause names this — it is jZen's own architectural invariant
              (STANDARDS "proto-first; no server-side quarkus-rest-jackson", CLAUDE.md, §7.1 item 10
              of this plan). Closest framing: ASVS 5.0.0's general configuration-hardening intent,
              not a specific citable clause (plan §2.1's rule against citing from memory applies —
              this is named directionally, not mapped).
**Boundary:** B1 (every JSON response on the client-facing surface depends on `ProtoJsonMessageBodyWriter`
              staying the sole `application/json` writer)
**Where:** Absence, not presence — checked and not found in `server/zen-transport/pom.xml`,
           `server/zen-identity/pom.xml`, `apps/zen_demo/zen_demo_server/pom.xml`,
           `.github/workflows/ci.yml`, and every `*Test.java` under `zen-transport`'s and
           `zen_demo_server`'s `src/test` trees consulted in Phases 2 and 4.
**Evidence:** `grep -rn jackson` across every non-`target` `pom.xml` in the repository (Phase 4, this
              session) returns only the three benign hits in the question table above — none is
              `quarkus-rest-jackson`, and none is a test or CI step that would fail if it were added.
              CLAUDE.md states the mechanism of harm precisely: "Jackson's writer greedily claims
              `application/json` through a build-time path that ignores writer priority and
              serializes proto builder internals (500s)" — i.e. the regression would not surface as
              a compile error, a dependency-tree diff someone is looking at, or even necessarily a
              local-dev failure if the two writers happen to agree on simple payloads, only as a
              production 500 on whichever proto message exposes builder internals first.
**Exploitability today:** Not externally exploitable — this is a self-inflicted regression risk (a
              future contributor adding `quarkus-rest-jackson` "to get Jackson annotations working"
              on one endpoint, per CLAUDE.md's own framing of why the rule exists), not something an
              attacker can trigger directly. The risk is entirely about *when this is caught*: today,
              only by a reviewer who has memorised CLAUDE.md's rule and one non-'no-verify'd person.
**Impact:** Every `application/json` response server-wide silently starts being served by Jackson
              instead of `ProtoJsonMessageBodyWriter` — per CLAUDE.md, this produces 500s by
              serializing protobuf builder internals rather than the canonical proto3 JSON shape,
              i.e. a whole-surface outage disguised as a dependency addition, not a targeted bug.
**Silent?** Yes for the addition itself — `mvn` resolves and builds successfully with the dependency
              present; the failure only appears at request time in the response body, which
              `InvalidBodyExceptionMapper`-style masking does not apply to (this is a *writer*
              failure, not a *reader* failure, so that mapper is not in the path at all).
**Fix:** Add a build-time or CI check that fails if the exact artifact
         `io.quarkus:quarkus-rest-jackson` (the extension itself, not `quarkus-rest-client-jackson`,
         not `quarkus-rest-jackson-common`, and not bare `jackson-databind` — §3.5's table found all
         three of the latter present today, legitimately) appears anywhere in the resolved dependency
         tree of a `quarkus`-packaged module — e.g. a Maven enforcer `bannedDependencies` rule
         matching the artifact id precisely, placed in `zen-parent` (`server/pom.xml`), which every
         app module inherits via `<relativePath>`, so a second application gets the check
         automatically rather than having to remember CLAUDE.md's prose or grep for a substring that
         also matches its own sanctioned dependencies.
**What the fix costs:** The rule must match the artifact id exactly, not a `jackson`-substring —
         §3.5 found `quarkus-rest-jackson-common` and `resteasy-reactive-jackson` already present via
         the sanctioned client extension, and a substring-based rule would either false-positive on
         those or, if loosened to avoid that, risk missing the real one. Precise, not free — a few
         lines of enforcer configuration, not a redesign, and `zen-parent` is exactly where
         module-wide Maven policy already lives (CLAUDE.md, "Backend
         structure").
**Invariant touched:** none (§7.1) — this fix *enforces* an existing invariant (§7.1 item 10) rather
         than trading against one.
**ADR consequence:** none directly superseded; no ADR currently states how this rule is enforced
         (only that it exists), so a fix documents a mechanism rather than reversing a decision.
```

**Closed this phase, verified correct with the evidence cited in the question table above**
(candidates for §6, not restated there yet — Phase 9's consolidated pass): the 1MB HTTP body-size
ceiling applies uniformly to both codec paths; `InvalidBodyExceptionMapper` never leaks a stack
trace, exception class, or field path; no `oneof`/`Any` usage exists in any current `.proto` schema;
`ZenTransportFilter`→`RateLimitFilter`→authentication→`CsrfFilter` ordering is structurally sound and
pinned by `RateLimitCsrfOrderingTest`; `X-Zen-Transport` cannot steer a request to an unintended
resource or an unregistered writer/reader, only between the two legitimate parsers already bound to
the matched resource; the WebSocket frame-size and connection-cap limits are correctly scoped
in-memory to the `--max-instances=1` premise and that premise is stated in the enforcing class's own
javadoc; `quarkus-smallrye-openapi` is confirmed absent from the native (production) dependency tree,
re-verified by running the command rather than reading the profile alone — no regression from Wave
4.2.

**Explicitly not done in Phase 4** (deferred to their own phases, per the plan): forcing either codec
path with an oversized or deeply-nested malformed body and observing the actual failure (Phase 8);
independently confirming Gson's (the JSON path's underlying parser) own recursion-depth default,
rather than noting that jZen sets no override (Phase 8, if pursued); forcing a `quarkus-rest-jackson`
reintroduction in a scratch branch to observe the CLAUDE.md-documented 500 directly, rather than
relying on CLAUDE.md's own account (judged out of scope for a static phase — would require a
throwaway code change this review's own rules discourage, plan §10: "A finding appears to require
editing a tracked file to demonstrate. It does not."); re-deriving the WebSocket revocation gap
independently of Phase 3's **F1** (no change expected, cited not re-argued).

### 3.6 Part F — Phase 5: Data plane, privileges, and privacy

jZen's data plane, privilege split, and retention lifecycle, per the plan's Phase 5 question list.
Answered from code and ADR text read this phase — the four repeatable migrations
(`R__identity_application_role.sql`, `R__identity_data_api_lockdown.sql`,
`R__jobs_row_level_security.sql`, `R__ratelimit_row_level_security.sql`), `DatabasePrivilegeTest.java`
(read for its assertions, not re-run — see the Method note above), `MigrateOnlyRunner.java`,
`DurableLimiter.java`, `UserRoleLoader.java`, `UserStore.java`'s `upsertOnLogin`,
`UserRetentionService.java`, `UserRetentionJob.java`, `UserRetentionZenJob.java`, `EmailService.java`,
`DemoMailer.java`, `JobScheduler.java`, `Taskfile.yml`'s deploy summary (steps 1, 1a-config, 1c), and
`DECISIONS.md` ADR-008, ADR-031, ADR-036, ADR-037, ADR-038, ADR-041.

| Question (plan §Phase 5) | Answer, with evidence |
|---|---|
| The privilege split — grants, actually enumerated | `R__identity_application_role.sql` creates `zen_runtime` **NOLOGIN**, grants `CONNECT`/`USAGE` on `public` plus `SELECT/INSERT/UPDATE/DELETE` on every table via `ALTER DEFAULT PRIVILEGES`, explicitly revokes `flyway_schema_history`, and **asserts** (raises and refuses to start) rather than merely revoking if `zen_runtime` ever holds `USAGE` on `auth` — a stronger property than "we didn't grant it," since a revoke against a schema owned by `supabase_admin` answers a warning, not an error, and silently does nothing (documented in the migration's own header, ADR-031). Not re-derived by a fresh query this phase; **the grant enumeration was independently measured live** against `jzen-prod` on 2026-08-04 (ADR-031's own table): `zen_runtime` denied `auth.users`, `flyway_schema_history` (select and delete), `CREATE TABLE`, `ALTER TABLE users`, `DROP TABLE users`; permitted DML on `users`/`zen_jobs`/`zen_rate_limit_counters`. `DatabasePrivilegeTest` (`canAlterOrCreate`, `cannotReachAuthSchema`, `cannotReachFlywayHistory`) re-asserts the same shape as an executable test against Dev Services Postgres — read this phase, not re-run. |
| Does the cutover happen on deploy and can it be skipped? | **No, it cannot be silently skipped, and this was itself a finding the predecessor pass of this review made and closed.** ADR-037 records that `deploy:cloudrun` enables the split unconditionally whenever `APP_DB_USERNAME`/`APP_DB_PASSWORD` exist in Secret Manager — a sequencing decision that lived only in a planning document turned out not to bind the tooling, and the deploy had already been enabling it since ADR-031 provisioned the secrets. Verified live post-deploy (ADR-037's table): `current_user = zen_runtime`, and `users`/`zen_jobs`/`zen_rate_limit_counters` row counts agree between the runtime and DDL connections — the "zero rows, not an error" trap named throughout §3.6 is confirmed absent. **This phase's own reading corroborates rather than re-derives that measurement.** |
| RLS scope — stated plainly | **Supabase-side only, by explicit design (ADR-031), and it is not a second line for the application path.** `auth.uid()` is a request-scoped Supabase JWT claim; jZen's pooled JDBC connection carries none, so a `users_owner`-style policy would make the application see zero rows, not a permission error. `users_application`/`zen_jobs_application`/`zen_rate_limit_counters_application` are each `FOR ALL TO zen_runtime USING (true) WITH CHECK (true)` — RLS is **on** for `zen_runtime` but its policy is unconditional, so in practice it constrains nothing the application path does; what it actually constrains is `anon`/`authenticated` (PostgREST), whose identity Postgres genuinely knows per request. **Legible statement for someone who has not read the ADR:** if an attacker's privilege in this system ever comes from a leaked `zen_runtime` credential rather than the Data API, RLS provides zero defense-in-depth — the same blast radius as the schema-level grants above, no narrower. `FORCE ROW LEVEL SECURITY` is deliberately unset everywhere for the same reason V2/ADR-031 give: the owner (Flyway's DDL role, and today's still-owner-connected application) must keep bypassing. |
| The Data API boundary (B5) — both layers, and the default for a new table | **Two independent layers, both verified this phase by reading rather than probing the hosted project (plan §4.4).** Layer one: `R__jobs_row_level_security.sql` and `R__ratelimit_row_level_security.sql` enable RLS with a permissive `zen_runtime` policy on `zen_jobs`/`zen_rate_limit_counters`, mirroring `users_application`. Layer two: `R__identity_data_api_lockdown.sql` revokes ALL (not just DML — `TRUNCATE` too, measured necessary against Supabase's actual default ACL) on existing and, via `ALTER DEFAULT PRIVILEGES`, future tables/sequences/functions from `anon`/`authenticated`. **The migration-ordering question Phase 2 left open — does the default-privilege revoke cover a table created by a *later* migration — is answered yes, and by a real test**: `DatabasePrivilegeTest.aTableCreatedAfterTheLockdownIsNotExposedEither` creates `added_after_the_lockdown` *after* running the lockdown SQL and asserts both Data API roles are refused `SELECT` and `INSERT` on it. **A sharper version of this same question was already found and fixed as this review's own F10, before this phase re-derived it**: `R__identity_data_api_lockdown.sql`'s default-privilege revoke is captured against `ddl_role := current_user` *at the moment the repeatable last ran* — a checksum-triggered re-run, not every deploy — so **rotating the DDL role does not retroactively re-point the revoke**, and a table created by the rotated role (or restored by a hand-typed `GRANT` in the dashboard) could sit exposed while Flyway reports a clean history. ADR-041 (2026-08-14) closed this by adding an **outcome assertion** in `MigrateOnlyRunner`, run once per deploy on the same DDL connection right after migration: it queries `information_schema.role_table_grants` and `pg_default_acl` directly for any `anon`/`authenticated` exposure, splitting default-privilege residuals into **fatal** (a role this connection can still alter — real drift, exit code `EXIT_DATA_API_EXPOSED=3`, no override) versus **warned-only** (a role it structurally cannot alter, e.g. `supabase_admin` for a dashboard-created table — named every deploy, not hidden, and covered instead by the per-table RLS layer). This is a stronger property than the SQL file's own guarantee, because it re-verifies the *outcome* on every deploy rather than trusting the *mechanism* to still be aimed at the right role. **Verified this phase by reading `MigrateOnlyRunner.java` in full against ADR-041's account — the code matches the ADR's claim exactly.** Not independently re-run against a live rotated-role scenario this phase (ADR-041 already exercised that functionally against a throwaway Postgres, per its own "Consequence" section). |
| Injection — what's new since the predecessor | **Nothing new found.** The predecessor verified named Panache parameters and a `SORTABLE` whitelist (closed ground, not re-audited). Checked this phase: `DurableLimiter`'s rate-limit upsert (`INSERT … ON CONFLICT (bucket, subject, window_start) DO UPDATE … RETURNING`) uses a native query with three positional bind parameters (`?1`/`?2`/`?3`), no string concatenation. `UserStore.upsertOnLogin`'s first-login race fix (`INSERT … ON CONFLICT (id) DO NOTHING RETURNING id`) is likewise fully parameterized. `UserRoleLoader.hasUsersTable`'s native query (`select to_regclass('public.users')`) takes no user input at all. `UserRetentionService`'s three HQL queries (`User.find(...)`) use `?1` positional binding for the only literal that varies (the cutoff timestamp); the `NOT_ANONYMISED`/`NOT_PREMIUM` fragments are fixed string constants, never built from request data, and the `anon!_%` escape is documented and exists specifically to stop HQL's own wildcard semantics from mis-including `anonymous@example.com`. No new native or dynamic query surface was found anywhere in `zen-jobs` (`JobScheduler`/`JobState` — Panache `find`/`enabled()`, no raw SQL touched by this phase's read). |
| Privacy and data lifecycle — retention, no-erasure-without-delivered-warning, PII in logs | **The no-erasure-without-delivered-warning property holds by construction, confirmed by re-reading the code rather than trusting the docstring (plan §5.3's trap).** `UserRetentionService` separates *finding* (read-only) from *stamping* (only after a caller confirms delivery); `UserRetentionJob.warn` fires each warning synchronously, checks `warning.receipt().isConfirmed()`, and stamps only on confirmation — an unconfirmed warning leaves the account exactly where it was, found again next cycle, never advanced toward anonymisation. `anonymiseExpiredAccounts` reads only rows past `finalWarningSentAt` and excludes premium and already-anonymised rows (`anon!_%` escape, confirmed above). Batching (`zen.identity.retention.batch-size`, oldest-first) bounds memory without breaking the ordering: a batch is a smaller *find*, never an earlier *stamp*. **PII in logs: checked and clean.** `EmailService.recipient()` is documented and coded to prefer a caller-supplied `recipientRef` (the user id) over the address in every log line, and when no ref exists it masks the local part and keeps only the domain — "an email address is personal data, and a log line is not a private place." `DemoMailer` passes `event.userId().toString()` as that ref for both the welcome and the deletion-warning paths, confirmed by reading both call sites; `JobScheduler.runOne` deliberately logs only `e.getClass().getSimpleName()` to the wire-visible `JobRun`, reserving the full exception text for the server-side log and the `zen_jobs.last_error` column. No site was found this phase that logs a raw email address, a password, or a secret value. |
| Privacy — what retention does **not** reach | **A real, priced gap, minted as F4 below.** `UserRetentionService`'s own class javadoc states plainly that "deleting the identity itself from `auth.users` is deliberately out of scope — it needs a service-role key and reaches into a table Supabase owns, not jZen" (ADR-007/ADR-008's "What this supersedes"). Confirmed structurally rather than merely quoted: `Taskfile.yml`'s secret-provisioning list (`mk SUPABASE_KEY "<publishable/anon key>"`) shows jZen's server never holds a `service_role` credential at all — the one credential capable of deleting a GoTrue identity — so this is an architectural boundary, not an unfinished implementation. Anonymisation clears the **application's** copy of the person's data (email, nickname, display name, avatar) on the `users` row; Supabase's own `auth.users` row — the original email address, and GoTrue's own sign-in metadata — is untouched and there is no automated path to change that. |
| Secrets | **7–9 genuine Secret Manager entries, not 17** — a correction to this plan's own §Phase 5 framing, in the same spirit as Phase 1's B7/B4 corrections. `Taskfile.yml`'s deploy summary names seven ("the seven genuine secrets": `SUPABASE_KEY`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `ZEN_JOBS_TRIGGER_TOKEN`), plus an explicitly-labelled eighth/ninth pair (`APP_DB_USERNAME`/`APP_DB_PASSWORD`) only if the least-privilege split is adopted. **The "17" figure traces to a different measurement**: `STANDARDS.md`'s cold-start accounting counts **"17 secret injections"** as part of Cloud Run's platform overhead (726ms of a 4.51s cold start) — a count of environment-variable injections at container start, which includes the public `--set-env-vars` configuration (`SUPABASE_URL`, `SITE_URL`, `CORS_ORIGINS`, the `AUTH_REDIRECT_URI*` pair, three SMTP fields) alongside the actual secrets, not a count of Secret Manager entries. Conflating the two would overstate the credential surface by roughly 2x. **None found committed** — none of the seven/nine appear anywhere in a tracked `pom.xml`, `application.properties`, or test fixture searched across Phases 2–5. **None reaches a client bundle** — `SUPABASE_KEY` is the anon/publishable key by design (`Taskfile.yml`'s own annotation), not a value that would matter if it did; `DB_PASSWORD`/`SMTP_PASSWORD`/`ZEN_JOBS_TRIGGER_TOKEN` are server-only env vars, never referenced by client-side `String.fromEnvironment` names (Phase 7's grep territory, not repeated here). **A secret value reaching a log or an error response**: not found. `ZenExceptionMapper` (§3.5, Phase 4) already returns a fixed message for any unmapped exception, including a `SQLException` carrying a JDBC URL; `JobScheduler.runOne` deliberately strips exception detail from the wire response for the same reason. **Rotation story**: manual and operator-driven for every credential here — `Taskfile.yml` documents rotating `DB_PASSWORD` and warns it "no longer rotates the credential the [application] connects with" once the privilege split is adopted (`APP_DB_PASSWORD` is the one that matters then), but there is no automated rotation, no expiry, and no alert on age for any of the seven/nine. Not asserted as a finding — small-team, low-churn credential rotation by hand is a reasonable default at this scale — but named as an open question for Phase 9 rather than left unstated. |

**One finding minted this phase:**

```
### F4 — Anonymisation clears jZen's own data; the Supabase-owned identity record it authenticates against is retained indefinitely with no automated path to remove it

**Class:** architectural
**Scope:** framework (`UserRetentionService`'s scope boundary — every application built on
           `zen-identity` inherits the same gap, not only `zen_demo`)
**Confidence:** verified
**Standard:** No single ASVS 5.0.0 clause names cross-system erasure completeness — this is a data-
              protection/GDPR Art. 17 (right to erasure) framing rather than an ASVS control gap,
              consistent with the plan's own instruction to frame this section as data protection
              and not attempt a legal assessment (plan §Phase 5). Cited directionally, not mapped.
**Boundary:** B2 (Cloud Run → Supabase GoTrue) and B3 (Cloud Run → Postgres) jointly — the gap is
              precisely the seam between the two systems this review's asset table (A1, A5/A6)
              already treats as separate.
**Where:** server/zen-identity/src/main/java/zen/identity/user/UserRetentionService.java (class
           javadoc states the scope boundary explicitly), DECISIONS.md ADR-008's "What this
           supersedes" (the donor's fourth retention phase — deleting via the Supabase admin API —
           was deliberately not ported), Taskfile.yml's secret-provisioning list (confirms no
           service_role credential is ever held server-side to act on this even if code existed).
**Evidence:** `UserRetentionService`'s own class javadoc: "Deleting the identity itself from
              `auth.users` is deliberately out of scope — it needs a service-role key and reaches
              into a table Supabase owns, not jZen." `anonymiseExpiredAccounts()` (read in full this
              phase) only ever mutates `user.email`/`nickname`/`displayName`/`avatarUrl`/
              `emailVerified` on the local `users` row — no call anywhere in `zen-identity` reaches
              a Supabase admin/service-role endpoint. `Taskfile.yml`'s "seven genuine secrets" list
              provisions `SUPABASE_KEY` explicitly as "<publishable/anon key>", confirming the
              credential capable of this action is never provisioned to the running service at all.
**Exploitability today:** Not an exploit — this is a completeness gap in a privacy control, not an
              attacker-reachable path. Named because a reviewer or a data-protection officer reading
              only "accounts are anonymised after N days" (ADR-008's headline) would reasonably
              assume the person's identity record is gone, when in fact their original email address
              and GoTrue sign-in history persist in Supabase indefinitely, discoverable to anyone
              with access to the Supabase project (the operator, today) but with no code path to
              remove it even for the operator to invoke.
**Impact:** A data subject who is told (or who assumes) their account was erased retains a live,
              undated `auth.users` row in Supabase carrying their original email address — the exact
              asset A1's row in this review already ranks highest — for as long as the Supabase
              project exists. A subject-access or erasure request reaching the operator by any
              channel other than "wait for the retention job" has nothing in the codebase to act on.
**Silent?** Yes — no test, log line, metric, or ASVS/GDPR-mapped check anywhere in the modules read
              across Phases 2 and 5 asserts, warns, or even records that this half of erasure did not
              happen. `UserAnonymised`'s own event fires as though the account's lifecycle is
              complete; nothing downstream is told otherwise.
**Fix:** Two shapes, priced separately rather than picked here. (a) **Minimal, in scope for a single
         operator today:** an operator runbook — not code — naming the exact Supabase Admin API call
         (`DELETE /auth/v1/admin/users/{id}` with the service-role key) to run manually, on a cadence,
         against every `id` this table has anonymised; costs nothing to write, and turns a silent gap
         into a documented manual step. (b) **Framework-level, inherited automatically:** an optional
         `zen-identity` integration that holds a service-role credential (a *new*, more sensitive
         secret than anything provisioned today) and calls GoTrue's admin delete on the same
         `UserAnonymised` event `DemoMailer` already observes — but this crosses a line ADR-007/008
         drew deliberately (jZen does not own `auth.users`), so it is a reversal of that decision,
         not a bug fix, and would need its own ADR.
**What the fix costs:** Option (a) costs an operator's recurring attention and nothing else. Option
         (b) costs introducing the single most powerful Supabase credential (service-role, full
         admin over every identity) into the running service's environment — precisely the
         blast-radius expansion ADR-031/036 spent this whole phase's evidence trail narrowing away
         from — so it trades a privacy-completeness gap for a new, larger asset (a service-role key
         in Secret Manager, reachable by anything that compromises the container) that this review's
         own asset table would have to rank above A4 and possibly above A7/A8.
**Invariant touched:** none of §7.1's ten items names this boundary directly, but option (b) would be
         in tension with the spirit of "the client talks to one server" and the least-privilege
         reasoning of ADR-031/036 even though it is a server-to-Supabase path, not a client path —
         worth the next reader weighing that tension explicitly rather than treating (b) as free.
**ADR consequence:** None superseded by this finding alone. A decision to build option (b) would
         need to explicitly revisit ADR-007's "jZen deliberately does not own `auth.users`" and
         ADR-008's "not ported" note on the donor's fourth retention phase — both would need to be
         named as the ADRs a successor supersedes, not silently routed around.
```

**Closed this phase, verified correct with the evidence cited in the question table above**
(candidates for §6, not restated there yet — Phase 9's consolidated pass): the `zen_runtime`
least-privilege role and its `auth`-schema fail-closed assertion; the ADR-037 deploy cutover
measurement (equal row counts, no zero-rows trap); RLS-is-Supabase-side-only as a coherent, legible
design rather than an ambiguous half-measure; both Data API lockdown layers, including the
migration-ordering question Phase 2 left open (`aTableCreatedAfterTheLockdownIsNotExposedEither`);
**this review's own F10** (the DDL-role-rotation gap in the Data API lockdown), independently
re-verified this phase by reading `MigrateOnlyRunner.java` against ADR-041's account rather than
taken on the ADR's word alone; the absence of new injection surface in the rate-limit upsert, the
first-login race fix, and the retention queries; the no-erasure-without-delivered-warning property;
and PII-free logging across the retention/mail/jobs paths.

**Explicitly not done in Phase 5** (deferred to their own phases, or out of this review's scope
entirely, per the plan): re-running `DatabasePrivilegeTest` or any `@QuarkusTest` against a live Dev
Services database this session (read, not executed — the plan's Phase 8 is where a running system
enters the picture); starting `task run:supabase` and independently re-measuring the grants against
a fresh local stack rather than citing ADR-031/036/037/041's already-recorded live measurements;
probing the hosted Supabase Data API (plan §4.4, an owner decision, unchanged); a legal or compliance
assessment of GDPR Art. 17 completeness for F4 (named as an architectural/privacy finding, not a
legal conclusion, per the plan's own instruction); rotation-story tooling or alerting design (named
as an open question for Phase 9, not designed here). Phases 6–9 entirely.

---

### 3.7 Part G — Phase 6: Supply chain and build integrity

The surface with the least prior coverage per the plan (§Phase 6). Answered from code and config
read this phase — `.github/workflows/ci.yml` (full), `.github/workflows/audit.yml` (full),
`.github/dependabot.yml`, `apps/zen_demo/zen_demo_server/src/main/docker/Dockerfile.native-micro`,
`server/.mvn/wrapper/maven-wrapper.properties`, `admin/package.json`'s and
`apps/zen_demo/zen_demo_admin/package.json`'s `packageManager` field, `Taskfile.yml`'s
`deploy:cloudrun` task and its `1f`/`1g` summary steps — plus `DECISIONS.md` ADR-039 (the `task
audit` CI wiring) and ADR-043 (the SBOM/signing decision) in full, and a bounded set of read-only
`gcloud`/`gh` control-plane queries against `jzen-prod` and the `jZenDev/jZen` GitHub repository
(listed in the Method note above).

| Question (plan §Phase 6) | Answer, with evidence |
|---|---|
| Is `task audit` run anywhere automatically? | **Yes — settled, not aspirational.** ADR-039 (`docs/architecture/DECISIONS.md:1018`) records that `.github/workflows/audit.yml` runs `task audit` on a weekly `cron: "17 6 * * 1"` plus `workflow_dispatch`, confirmed by reading the workflow file directly this phase: it exists, its trigger block matches the ADR's account exactly, and its one job runs `task audit` as its final step. This resolves plan §11 Q4 — reading the workflow settles the question the plan left open, the same discipline as Phases 1–5 (§5.3's trap: read the code, not the ADR's claim about the code). `.github/dependabot.yml` additionally covers the `github-actions` ecosystem on a weekly schedule — deliberately not Java/TypeScript/Dart, which `task audit` already answers, so this is not two tools answering the same question. |
| Workflow token permissions, and what a malicious PR from a fork can reach | Both workflow files declare `permissions: contents: read` at the top level (`ci.yml:35-36`, `audit.yml:16-17`) — explicit in the tracked file rather than inherited from the (already read-only, confirmed via `gh api .../security_and_analysis` returning no elevated default) repository setting; `ci.yml`'s own comment names this precisely as closing a finding of this same review (F12, closed 2026-08-14). No job in either file requests `packages:`, `id-token:`, or any other elevated scope. All `ci.yml` triggers are `pull_request`/`push` (not `pull_request_target`), so a fork's PR runs with a read-only, repo-scoped `GITHUB_TOKEN` and no access to repository secrets by GitHub's own trigger-scoping rule — confirmed structurally, not by testing a real fork PR this phase. **`gh secret list` against the live repository returns zero entries** — there is no repository-level secret for a malicious workflow run to exfiltrate even if permissions were wider, which matches ADR-043's own finding that no CI deploy credential exists at all (see below). |
| Action pinning by tag vs. digest; third-party actions and what each is trusted with | **Confirmed, re-reading rather than trusting the plan's or F12's account: `ci.yml` is fully SHA-pinned, `audit.yml` is not, and this asymmetry — flagged as a correction-in-waiting in Phase 1 (§2.2) and explicitly deferred there to Phase 6 — is unresolved today.** Every `uses:` line in `ci.yml` (`actions/checkout`, `actions/setup-java`, `subosito/flutter-action`, `actions/setup-node`, `arduino/setup-protoc`, `arduino/setup-task`, `actions/setup-python`, `supabase/setup-cli` — re-grepped this phase, 23 occurrences across 6 jobs) pins to a 40-character commit SHA with the human-readable tag as a trailing comment (e.g. `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`). Every `uses:` line in `audit.yml` (`actions/checkout@v7`, `actions/setup-java@v6`, `actions/setup-node@v7`, `arduino/setup-task@v3`, `actions/setup-python@v7` — 5 occurrences) is a **mutable tag**, unchanged from before F12 was worked. Trust granted: none of the five actions `audit.yml` invokes touch secrets or deploy anything (the job's own `permissions: contents: read` bounds the blast radius to whatever the action does on the runner, plus a read-only `GITHUB_TOKEN` passed to `arduino/setup-task`'s `repo-token` input for its own rate-limit-avoidance API calls) — but a force-moved or compromised tag on any of the five would still execute arbitrary code on a runner that has that token, on a **schedule nobody reviews before it fires** (`workflow_dispatch`/`cron`, not a PR someone is already looking at), which is exactly the CICD-SEC-1/CICD-SEC-3-shaped risk (Insufficient Flow Control / Dependency Chain Abuse) the OWASP CI/CD Top 10 names and `ci.yml`'s own SHA-pinning already defends against for every *other* workflow in this repository. See **F5** below. |
| How does the deploy authenticate to GCP — a long-lived key, or workload identity federation? | **Neither — there is no CI-to-GCP authentication path at all, because CI never deploys.** `ci.yml`'s own header comment states this as a design decision ("deploy:cloudrun — deploy is manual, by a person") and it is verifiable independently of the comment: `gh secret list` returns zero repository secrets (no `GCP_SA_KEY`-shaped entry, no `WORKLOAD_IDENTITY_PROVIDER`), no `google-github-actions/auth` or `google-github-actions/deploy-cloudrun` action appears anywhere in either workflow file, and `gh api repos/jZenDev/jZen/environments` returns zero environments. `gcloud projects get-iam-policy jzen-prod` (read-only control-plane call, this phase) shows exactly one human principal with `roles/owner` (`a.merezhanyi@gmail.com`) and the project's default Compute Engine service account with `roles/editor` — no distinct CI/automation service account holds any role. `Taskfile.yml`'s `deploy:cloudrun` task requires an interactive `gcloud auth login` (already the operator's own session) and, since ADR-043, an interactive Sigstore OIDC login for `cosign sign`/`cosign attest` — both human-in-the-loop, both re-confirmed this phase by reading the task body rather than only ADR-043's account of it. This is the workload-identity-federation-vs-long-lived-key question resolved by there being no third option needed: **the question presupposes a CI deploy credential this repository does not have**, which is itself the strongest answer available to CICD-SEC-2 (Inadequate Identity and Access Management). |
| Base image pinned by digest; non-root `USER`; SBOM; signing; provenance | **Base image and non-root user re-verified unchanged from the predecessor audit.** `Dockerfile.native-micro:14` pins `quay.io/quarkus/ubi9-quarkus-micro-image@sha256:d4295e70be7c3df55523bcbcc0fd696d518484de2579d5d87546d422649a1296` (a digest, not a tag); `Dockerfile.native-micro:23` sets `USER 1001` after the `chown`/`chmod` block gives that uid ownership of `/work` — both read directly from the file this phase, not inherited from the predecessor's account. **SBOM and signing are no longer "no" — ADR-043 (2026-08-14, `DECISIONS.md:780`) already closed this exact plan bullet as this review's own F6**, before today's session reopened Phase 6: `cyclonedx-maven-plugin` writes a CycloneDX SBOM to `target/bom.json` on every native `mvn package` (253 components, measured); `deploy:cloudrun` runs `cosign sign` (keyless, Sigstore Fulcio+Rekor, no stored key) on the pushed image and `cosign attest --type cyclonedx` on the SBOM, then refuses to migrate or deploy unless `cosign verify`/`cosign verify-attestation` both succeed against a required, no-default `COSIGN_CERT_IDENTITY` — fail-closed, confirmed by reading `Taskfile.yml`'s `deploy:cloudrun` body this phase (lines ~2426–2462) against ADR-043's account, which matches. **Provenance, stated plainly, per ADR-043's own discipline of not claiming an SLSA level**: the build itself is not hermetic or reproducible and still runs on a developer's workstation (`task build:server:native`) — CI never touches the artifact that ships, by the same deliberate design `ci.yml`'s header already argues for. This phase adds nothing beyond re-confirming ADR-043's claim against the current `Taskfile.yml` and `Dockerfile.native-micro` — **no drift found**. |
| `dart pub global activate protoc_plugin`, `corepack`, and the `mvnw`/wrapper scripts — checksum-less fetches at build time | **Mixed, and narrower than the plan's framing suggests.** `server/.mvn/wrapper/maven-wrapper.properties` pins Maven 3.9.12 **with an explicit `distributionSha256Sum`** — the wrapper verifies the download before running it, not merely pins a version string; this is a closed item, not a gap. `corepack enable` (both workflow files) activates whatever `packageManager` each `package.json` declares, and every `package.json` in the repository that matters here (`admin/package.json`, `apps/zen_demo/zen_demo_admin/package.json`, re-grepped this phase) pins `pnpm@10.30.3` **with a trailing `+sha512.<hash>` integrity hash** — corepack refuses to run a `pnpm` whose downloaded tarball doesn't match, so this is also checksum-verified, not merely version-pinned. The one real gap: `dart pub global activate protoc_plugin 25.0.0` (`ci.yml:72`) pins an exact version but carries **no content hash** — `dart pub` trusts pub.dev's HTTPS-served package index and its own registry-level integrity, the same trust model as an unpinned `npm install <pkg>@<version>` would have before `corepack`'s hash pinning existed for the package manager itself. Not minted as a finding (it is a lower-severity, narrower-blast-radius gap than F5 — protoc-gen-dart only runs inside `verify:contracts`/`test:e2e`, a PR-reviewed path, not an unattended schedule), but named here rather than silently folded into the mvnw/corepack items it does not share their property with. `arduino/setup-protoc`'s own `version: "29.x"` input is a *range*, not an exact pin, though the action invocation itself is SHA-pinned in `ci.yml` — the same minor, non-finding observation. |
| Secret scanning / push protection; any credential committed | **Both enabled, confirmed by reading the live repository setting rather than assuming a default.** `gh api repos/jZenDev/jZen --jq '.security_and_analysis'` (this phase) returns `secret_scanning: enabled` and `secret_scanning_push_protection: enabled` (`secret_scanning_validity_checks` and `secret_scanning_non_provider_patterns` are both `disabled` — narrower coverage than the maximum available, named here rather than assumed on). No credential was found committed anywhere across Phases 2–6's reads, consistent with `gh secret list`'s empty result and the Phase 5 finding that none of the seven/nine genuine secrets appear in a tracked `pom.xml`, `application.properties`, or test fixture. The predecessor's note on dev/test trigger tokens scoped to non-shipping profiles was not independently re-verified this phase (out of Phase 6's own question list; Phase 5 already covers `ZEN_JOBS_TRIGGER_TOKEN`'s scoping). |
| Artifact Registry: who can push; are old images a liability or just storage | **One repository, `jzen` (europe-central2), 81 image digests today** (`gcloud artifacts docker images list`, this phase — up from "51 at last count" in the predecessor audit, confirming the count keeps growing rather than being a one-time observation). `gcloud artifacts repositories get-iam-policy jzen` returns an empty binding set — the repository has no IAM policy of its own, so push/pull rights flow entirely from the **project-level** IAM policy, which (per the GCP-auth question above) grants exactly one human `roles/owner` and the default Compute service account `roles/editor` — **the same single owner who can push can also deploy, delete the project, and read every secret; there is no narrower "can push images" role**, which is consistent with a solo-maintainer repository but is itself worth naming: the least-privilege reasoning ADR-031/036/037 applied carefully to the *database* roles has no analog at the registry. **Old images are storage, not a live liability**, and this is now a repository *policy*, not merely an observation: `gcloud artifacts repositories describe jzen --format="yaml(cleanupPolicies)"` shows three active policies — `keep-tagged` (every tagged image, i.e. every image ever pushed by a deploy that used a commit-SHA tag, is kept forever), `keep-recent-untagged` (the 10 most recent untagged versions), and `delete-old-untagged` (anything untagged older than 30 days is deleted). Read together: **nothing here ever deletes a tagged production image**, which is why the count has grown from 51 to 81 rather than being bounded — a deliberate trade-off (an old tagged image stays available for rollback/forensics) rather than an oversight, but the growth is unbounded by construction and was not weighed against Artifact Registry's storage cost in any document read this phase. Not minted as a finding — storage cost at this scale is a Free-wins/Priced-trade-off-shaped question for Phase 9, not a security gap. |

**One finding minted this phase:**

```
### F5 — `audit.yml`'s third-party actions run on an unattended schedule from mutable tags, while every other workflow in the repository was hardened to commit-SHA pins

**Class:** process
**Scope:** pipeline (the workflow-hardening gap is specific to `audit.yml`; the pattern it
           deviates from — SHA-pinning every third-party action — is already established
           elsewhere in this same repository, so this is an inconsistency, not a missing
           practice)
**Confidence:** verified
**Standard:** OWASP Top 10 CI/CD Security Risks v1.0 — CICD-SEC-3 (Dependency Chain Abuse) as the
              primary fit (an upstream action's mutable tag is exactly the dependency-chain
              vector the item names); CICD-SEC-1 (Insufficient Flow Control Mechanisms)
              secondarily, because the run that would execute a moved tag is a `cron`/
              `workflow_dispatch` fire, not a PR a human is already looking at.
**Boundary:** B7 (GitHub Actions → the repository)
**Where:** .github/workflows/audit.yml:23,26,32,38,44 (`actions/checkout@v7`,
           `actions/setup-java@v6`, `actions/setup-node@v7`, `arduino/setup-task@v3`,
           `actions/setup-python@v7` — all mutable-tag references), contrasted with
           .github/workflows/ci.yml's 23 equivalent `uses:` lines, all commit-SHA-pinned since
           F12 (closed 2026-08-14, `DECISIONS.md`'s ADR entry for that finding).
**Evidence:** `grep -n 'uses:' .github/workflows/audit.yml` (this phase) returns five bare
              `@vN` tags; the identical `grep` against `ci.yml` returns 23 lines, every one a
              40-character SHA with the tag preserved only as a trailing comment. `git log -1
              --format=%ai -- .github/workflows/audit.yml` (this phase) shows its last commit as
              2026-08-28 — after F12's fix landed (2026-08-14) — so this is not an oversight that
              predates the hardening; the hardening was applied to one workflow file and not
              propagated to the other one that already existed alongside it.
**Exploitability today:** Low-to-moderate. Requires either the upstream maintainer of one of the
              five actions to force-move its tag maliciously, or an attacker to compromise that
              maintainer's account — the same precondition Phase 1's B7 threat table already
              named as live for exactly this reason. The window is real: unlike a PR-triggered
              workflow, `audit.yml` fires on a **weekly cron nobody is reviewing at the moment
              it runs**, so a moved tag executes automatically rather than needing a human to
              approve a workflow run first (GitHub does gate first-time-contributor PR workflow
              runs, but that protection does not apply to scheduled runs at all).
**Impact:** Arbitrary code execution on a `ubuntu-latest` runner carrying a read-only, repo-scoped
              `GITHUB_TOKEN` (no repository secrets exist to steal, per this phase's `gh secret
              list` finding) and network egress — bounded blast radius (no deploy credential, no
              write scope) but still a foothold: a compromised action here could, for example,
              exfiltrate the runner's environment or tamper with `task audit`'s own output before
              it reaches a human, undermining the one gate this workflow exists to run.
**Silent?** Yes — no gate compares `ci.yml`'s and `audit.yml`'s pinning discipline against each
              other; Dependabot's `github-actions` ecosystem entry (`.github/dependabot.yml`)
              will propose version bumps for the mutable tags exactly as configured, which is not
              the same property as flagging that they are unpinned in the first place.
**Fix:** Pin `audit.yml`'s five `uses:` lines to the same commit SHAs `ci.yml` already uses for
         the identical actions — all five of `audit.yml`'s tags (`checkout@v7`, `setup-java@v6`,
         `setup-node@v7`, `setup-task@v3`, `setup-python@v7`) name the exact same major.minor.patch
         `ci.yml` already pins by SHA (`v7.0.1`, `v6.0.0`, `v7.0.0`, `v3.0.0`, `v7.0.0`
         respectively), so no new SHA needs to be looked up — this is a copy from one file to the
         other, not new research. A mechanical, low-risk change with a precedent already in the
         same repository.
**What the fix costs:** Nothing architectural — a few lines of `sed`-shaped editing, and the
         resulting file loses none of the readability `ci.yml`'s own "SHA with a trailing
         version comment" convention already preserves. The only ongoing cost is what `ci.yml`
         already pays: a SHA pin needs a human (or Dependabot) to bump it when a new action
         version is wanted, rather than picking one up automatically — a cost this repository
         has already decided is worth paying once, for `ci.yml`.
**Invariant touched:** none (§7.1).
**ADR consequence:** none directly superseded; this closes the residual half of F12 (already an
         accepted ADR) rather than opening new ground — a fix would most naturally land as an
         addendum noting the closure, not a new decision.
```

**Closed this phase, verified correct with the evidence cited in the question table above**
(candidates for §6, not restated there yet — Phase 9's consolidated pass): `task audit`'s CI
wiring (ADR-039, re-confirmed by reading the live workflow rather than trusting the ADR's account —
resolves plan §11 Q4); both workflows' `permissions: contents: read` scoping and the absence of any
elevated grant; the complete absence of a CI-to-GCP credential (no key, no workload identity, no
environment, no secret) and the deploy's fully human-authenticated path via `gcloud auth login` plus
Sigstore's interactive OIDC login; the base image's digest pin and non-root `USER 1001`; ADR-043's
SBOM/signing/fail-closed-verification posture, re-confirmed against the current `Taskfile.yml` and
Dockerfile with no drift found; the Maven wrapper's SHA-256-verified download and both `pnpm`
`packageManager` fields' SHA-512 integrity hashes; secret scanning and push protection both enabled
on the live repository, and no committed credential found across Phases 2–6; and the Artifact
Registry cleanup policy's actual shape (tagged images kept forever, untagged pruned after 30 days) as
a real, read policy rather than an assumption from the predecessor's "51 at last count" note.

**Explicitly not done in Phase 6** (deferred to Phase 9, or out of this review's scope entirely, per
the plan): pricing the Artifact Registry storage-growth question as a free-win or a priced
trade-off (Phase 9); designing or costing a least-privilege registry-push role narrower than
project-level `owner` (named as an open question, not designed here — a solo-maintainer repository
may reasonably decline this); independently re-running `task audit` this session rather than citing
ADR-039's account of its last clean result (Phase 5's own precedent for citing rather than
re-deriving a result already recorded elsewhere); testing a real forked-repository PR to observe
`GITHUB_TOKEN` scoping empirically rather than reasoning it from GitHub's documented trigger-scoping
rule; branch-protection posture (no required PR review, no required signed commits — read this
phase via `gh api .../branches/main/protection` but not minted as a finding, since a solo-maintainer
repository cannot meaningfully require a second reviewer) — named as an open question for Phase 9,
the same discipline Phase 5 applied to secret-rotation tooling for an equally small-team context.

---

### 3.8 Part H — Phase 7: The client and the browser surface

The browser-facing half of jZen — compile-time config, the one-server rule from the client's side,
token storage, security headers, the admin panel, and deep links — per the plan's Phase 7 question
list. Answered from code read this phase — `client/zen_secure_store/lib/src/secure_token_store*.dart`,
`client/zen_identity/lib/src/zen_identity_config.dart`, `client/zen_core/lib/src/zen_constants.dart`,
`scripts/verify-boundaries.py`, `server/zen-transport/src/main/java/zen/transport/{SecurityHeaders,CorsCredentialsGuard}.java`,
`admin/src/{authProvider,dataProvider}.ts`, `apps/zen_demo/zen_demo_admin/src/App.tsx`,
`apps/zen_demo/zen_demo_client/{android,ios,macos}` — plus the relevant `DECISIONS.md` entries, the
already-staged production bundle under `.../META-INF/resources`, `ra-core`'s own telemetry source,
and 11 live, read-only requests against the deployed service (the ledger in the Method block above).

| Question (plan §Phase 7) | Answer, with evidence |
|---|---|
| Compile-time config — is anything secret in the bundle? | **No.** Every `String.fromEnvironment` name in the client is now enumerated (`ZEN_API_URL`, `ZEN_AUTH_REDIRECT_URI`, `ZEN_ENV`, `ZEN_PLATFORM` — `zen_identity_config.dart:6,23`, `zen_constants.dart:19,38`), and all four are non-secret by design: an API base URL, a native redirect scheme, a build environment tag, a platform tag. Grepping the **already-staged** production web bundle (built 2026-08-17) for `supabase`, `eyJ`, `service_role`, `anon_key` returns zero hits in both the Flutter app and the admin bundle. The bundle's only external hosts, extracted directly from `main.dart.js`, are `fonts.gstatic.com` (the one CSP allow-lists) and jZen's own deployed hostname — confirming `--no-web-resources-cdn` (§3.5/ADR-035) holds in the actual shipped artifact, not only in the build flag. `ZEN_API_URL` is baked in as the real production hostname (`https://zen-demo-server-tovqpjhspa-lm.a.run.app`), confirming compile-time config produces a build that actually points at the right server rather than a placeholder. **Caveat, stated plainly:** this bundle predates today's session by a month; it answers "is this mechanism sound" (yes — no secret name is ever passed to a build define anywhere in the codebase), not "is today's HEAD's bundle clean" — `task build:web` was not re-run this phase (plan §10: a finding must not require editing a tracked file or forcing a rebuild to demonstrate what static reading already answers). |
| The one-server rule (B1), from the client's side | `verify:boundaries` (read in full this phase, `scripts/verify-boundaries.py`) runs three regex checks — no provider SDK dependency, no provider host/credential string, no absolute-URL literal — scoped explicitly to `client/*/lib`, `apps/*/*/lib` (Dart) and `admin/src`, `apps/*/*_admin/src` (TypeScript), both scopes fail loudly (`StaleScope`) rather than silently pass if a glob matches nothing. **Confirmed, re-reading rather than re-asserting Phase 2's finding: Kotlin and Swift platform-channel code is not in either scope.** `apps/zen_demo/zen_demo_client/android/app/src/main/kotlin/.../MainActivity.kt` (5 lines) and every `.swift` file under `ios/`/`macos/` (12–32 lines each) were read directly this phase — all are Flutter-generated boilerplate (`GeneratedPluginRegistrant`, a bare `FlutterActivity`/`FlutterAppDelegate`), none makes a network call or references Supabase. **The gap Phase 2 named on paper is confirmed still open on the code that exists today, and still unexploited today** — there is no plugin or platform-channel call for it to catch. No `HttpOverrides`, `badCertificateCallback`, or `WebView` usage was found anywhere in `client/` or `apps/*/lib` (grepped this phase, zero hits) — the client has no certificate-pinning override and no embedded browser surface to audit. |
| Token storage (MASVS-STORAGE) — mobile vs. web | **Sound today, and already hardened past a real incident this review's own numbering can't currently place precisely (see below).** `SecureTokenStore`'s native branch (`secure_token_store_io.dart`) wraps `FlutterSecureStorage` with `KeychainAccessibility.first_unlock_this_device` on iOS/macOS and the plugin's own post-10.x cipher on Android (no `AndroidOptions`, deliberately — the class's own comment explains `encryptedSharedPreferences` is deprecated and ignored); only the refresh token is persisted, the access token stays in-memory for its 1h life. **The web branch does not fall back to `window.localStorage` — it throws `UnsupportedError` at construction**, with a doc-comment naming exactly the property `flutter_secure_storage_web` would otherwise silently violate: "the refresh token belongs in the httpOnly `zen_refresh_token` cookie on web instead ... nothing should construct one." This is a **closed, already-fixed** version of the exact MASVS-STORAGE gap plan §Phase 7 asks Phase 7 to go looking for (a claimed security property that is silently absent on one platform) — DECISIONS.md's entry dated 2026-07-31 (refining ADR-016/ADR-023) records the incident that motivated the throw-loudly design: a caller-side guard (`zenIsWeb ? null : SecureTokenStore()`, still present today at `apps/zen_demo/zen_demo_client/lib/main.dart:37`, confirmed by reading it this phase) is "redundant now, not wrong" belt-and-braces, with the class itself now the actual guarantee. **Not independently re-verified against a live web build's `localStorage` this phase** (that would require constructing the class on web to watch it throw, which the code already asserts and a unit test — `secure_token_store_web_test.dart`, present but not re-run this phase — presumably covers). |
| Security headers, from the wire, in a real browser | **Verified live against production, not only read from `SecurityHeaders.java`.** Ledger rows #1–#3 confirm the identical header set — CSP, `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `Permissions-Policy` denying geolocation/camera/microphone/payment/usb, `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`, `Strict-Transport-Security: max-age=31536000` — on the SPA root, `/admin/`, and an unauthenticated API path, byte-for-byte matching `SecurityHeaders.CONTENT_SECURITY_POLICY`'s Java source. `Cross-Origin-Embedder-Policy` is confirmed absent, and the class's own javadoc states this is deliberate (COEP is a stricter page-wide opt-in this policy does not make). HSTS carries no `includeSubDomains`/`preload`, matching the javadoc's stated reason (no real domain yet, ADR-027 defers it) — not re-litigated here, ADR-035/027 already priced it and §5.4's rule is to re-examine the reasoning, not the mechanism, and the reasoning (a `*.run.app` hostname, no committed domain) is still true today. **A browser-console CSP-violation check was not performed live this phase** (no browser was driven against the running admin panel with DevTools open) — see **F7** below, which reasons the one live violation this policy would actually produce from the CSP source and `ra-core`'s own telemetry code rather than watching it happen. |
| The admin panel — auth, session, XSS surface, header parity | **Auth provider reviewed in full** (`admin/src/authProvider.ts`): login/logout/checkAuth/getPermissions all resolve through `GET {authBase}/identity` (200 = session, 204 = anonymous) — **no token is ever read from JS**, matching `dataProvider.ts`'s CSRF handling (the JS-readable `XSRF-TOKEN` cookie echoed as a header on mutating requests only, GET/HEAD exempt — same protected-by-default shape Phase 3 verified server-side). `login` explicitly checks `hasAdminRole` and calls `clearSession()` (which itself sends the CSRF header) if the authenticated identity lacks the admin role — **a non-admin credential cannot leave a live admin-panel session even though the underlying login succeeded**, closing the BFLA-adjacent question of whether the panel merely hides the admin UI from a non-admin versus actually refusing to hold their session. **Header parity, verified live rather than assumed:** ledger row #11 (a hashed, cache-busted `.js` asset under `/admin/assets/`, not the document) carries the identical CSP/frame/COOP/CORP/Permissions-Policy/HSTS set as rows #1–#3, confirming `SecurityHeaders`' Vert.x-router placement (§3.1/ADR-035) covers every static file the admin bundle ships, not only its `index.html`. **XSS surface in react-admin's own dependency tree was not independently audited this phase** (that is `task audit`'s job, Phase 6, not re-run here) — but one concrete, previously-unreviewed behaviour was found reading `ra-core`'s source directly: see **F7**. |
| Deep links and App Links | **Re-confirms F2 (Phase 3) rather than reopening it, with two pieces of fresh evidence.** First, live: ledger rows #9–#10 show both `/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association` returning 404 **on the actual deployed service today** — App Links is not a hypothetical unconfigured state, it is the live, current state of the one production instance this review can read, which raises F2's own "contingent, not demonstrated" framing partway (the mechanism is confirmed unconfigured in the one environment that exists) without fully resolving it (whether a *native build* with the live `zendemo://` scheme has shipped to a real device is still unverifiable from a repository/API read, per F2's original text). Second, from DECISIONS.md's 2026-08-01 entry (refining ADR-018/019/021, closing backlog item 8's Android half): the Android mitigation is real and tested (`WellKnownResourceTest`/`WellKnownResourceConfiguredTest`, an APK-manifest dump confirming both intent-filters build), while the iOS half is **not implemented for a non-technical reason** — Apple's Associated Domains entitlement needs a paid Developer Program membership, and adding the entitlement without one would break every iOS build on an unpaid machine (the same trap a macOS Keychain entitlement sprang earlier per that entry's own cross-reference). This is consistent with, and sharpens, F2's existing "optional and unenforced" framing: Android's optionality is a configuration choice; iOS's is presently a hard platform constraint, and F2's fix (a deploy-time warning) would need to say so rather than treat both platforms as symmetrically deferrable. |

**One finding minted this phase:**

```
### F7 — react-admin's default telemetry beacon ships to production unreviewed; it is blocked by
this app's own CSP, but silently and for a reason the code does not record

**Class:** implementation
**Scope:** application (`zen_demo_admin`'s own `<Admin>` call) — but the underlying default (no
           `disableTelemetry` prop) is the react-admin package's, and `@jzen/admin-core`'s
           `createAuthProvider`/`createDataProvider` factories do not set it either, so a second
           app assembling the framework scaffold the same way (`import { Admin } from
           "react-admin"` directly, as `App.tsx` does) inherits the identical unreviewed default —
           this is scoped "application" only because the one call site that could disable it lives
           in application code, not because a second app would do anything differently.
**Confidence:** verified (the call exists, is unguarded, and CSP's `img-src` does not name its
              host) / reasoned-from-code (that the browser actually refuses it and logs a CSP
              violation — not watched live this phase, see the question table above).
**Standard:** No ASVS clause names third-party telemetry directly; framed here under ASVS 5.0.0's
              general third-party-content/configuration-hardening intent (cited directionally, plan
              §2.1's rule against citing a number from memory applies to "no clean fit" too, not
              only to the requirement that exists). OWASP Proactive Controls' "minimize attack
              surface area" is the closer fit in spirit.
**Boundary:** B1/B9 (the admin panel's own document load, same boundary as the rest of the panel)
**Where:** apps/zen_demo/zen_demo_admin/src/App.tsx:21-28 (`<Admin dataProvider=... authProvider=...
           loginPage={LoginPage}>` — no `disableTelemetry` prop), contrasted with
           admin/node_modules/.pnpm/ra-core@5.15.0.../src/core/CoreAdminUI.tsx:340-352 (`ra-core`'s
           own source, read this phase: `disableTelemetry = false` by default; when false, not in a
           test env, and running in a browser, it constructs `new Image()` and sets `img.src =
           "https://react-admin-telemetry.marmelab.com/react-admin-telemetry?domain=" +
           window.location.hostname` on every mount), and
           server/zen-transport/src/main/java/zen/transport/SecurityHeaders.java:137
           (`"img-src 'self' data: blob:"` — `react-admin-telemetry.marmelab.com` is not, and has
           never been, in this list).
**Evidence:** The call is an `<img>` element's `src`, not a `fetch`/`XHR` — so it is `img-src`, not
              `connect-src`, that governs it, and `img-src` in `CONTENT_SECURITY_POLICY` (read in
              full this phase, §3.1/ADR-035's policy) allow-lists only `'self'`, `data:`, and
              `blob:`. Ledger rows #2 and #11 confirm this exact CSP string is live on both the
              admin document and its hashed JS asset in production today. `window.location.hostname`
              on the deployed service is the public `*.run.app` hostname already known from the
              bundle grep above — not itself a secret — so the payload this call would have sent is
              not sensitive; what matters is that nobody decided to send it, and CSP's silence about
              this specific host is coincidental (the directive was written for the app's own
              images, not to block a telemetry beacon nobody named).
**Exploitability today:** Not exploitable — no attacker action is involved, and CSP already stops
              the network request before it leaves the browser. This is a hygiene/process finding,
              not a live vulnerability: an unreviewed third-party outbound call shipped into the
              highest-privilege surface in the system, whose only reason it does not currently
              exfiltrate anything is that a directive written for an unrelated purpose happens to
              cover it.
**Impact:** If today's CSP is ever loosened — and the class's own javadoc names exactly this
              pressure ("a CSP nobody can explain is a CSP that gets widened by the next person who
              meets a console error") — widening `img-src` to quiet an unrelated, legitimate image
              load could simultaneously and silently re-enable this call, sending the admin panel's
              hostname to a third party on every admin login, with no one having decided that
              trade-off because no one flagged that the old, narrower `img-src` had been quietly
              doing that job.
**Silent?** Yes, in the specific sense the plan's Phase 7 question asks about: no test, gate, or
              comment anywhere in `admin/` or `apps/zen_demo/zen_demo_admin/` records that this call
              exists or that CSP is what stops it — a console CSP violation is the only signal, on
              every admin panel load, that nothing currently reads (plan §Phase 7: "a CSP that
              reports violations nobody reads is a CSP heading for a `'unsafe-inline'` patch," here
              applied to `img-src` instead).
**Fix:** Pass `disableTelemetry` explicitly on the `<Admin>` element — one line, in
         `apps/zen_demo_admin/src/App.tsx` today. Framework-level version: `@jzen/admin-core` could
         export a thin `<ZenAdmin>` wrapper around `<Admin>` that defaults `disableTelemetry` to
         `true` and lets an app opt back in, so a second app assembling the scaffold the way
         `App.tsx` does inherits the decided-on-purpose default rather than react-admin's own.
**What the fix costs:** Nothing technical. The only cost is losing react-admin's own anonymous usage
         signal to its maintainers (Marmelab) — a trade-off worth making explicitly rather than by
         CSP accident, since the operator gets nothing back from it today and the panel's admins
         were never told it happens.
**Invariant touched:** none (§7.1) — arguably reinforces item 4 (no edge/third-party in the
         request path) in spirit, though CSP already enforces it in practice.
**ADR consequence:** none; no ADR states a policy on react-admin's own telemetry either way.
```

**Closed this phase, verified correct with the evidence cited in the question table above**
(candidates for §6, not restated there yet — Phase 9's consolidated pass): no `String.fromEnvironment`
name or literal value in the client is secret-shaped, and none of `supabase`/`eyJ`/`service_role`/
`anon_key` appears in the already-staged production web or admin bundle; `--no-web-resources-cdn`
holds in the shipped artifact (only `fonts.gstatic.com` and jZen's own host appear as external
references); `verify:boundaries`' three checks and their `StaleScope` fail-loud design, re-read and
re-confirmed against the live script; the web branch of `SecureTokenStore` throwing rather than
falling back to `window.localStorage`, and the native branch's Keychain/Keystore configuration, both
already fixed ahead of this review per DECISIONS.md's 2026-07-31 entries; every response security
header (CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy, COOP, CORP,
HSTS) verified live and byte-identical across the SPA root, `/admin/`, an API path, and a hashed admin
asset; the admin auth provider's non-admin-session refusal (`clearSession()` on a non-admin login);
CORS's disallowed-origin preflight rejection, verified live; the OpenAPI/Swagger/dev/health surface's
404 in production, verified live, corroborating Phase 4's dependency-tree finding from the wire; and
the Android App Links mechanism's test coverage per DECISIONS.md's 2026-08-01 entry.

**Explicitly not done in Phase 7** (deferred to Phase 8, or out of this review's scope entirely, per
the plan): re-running `task build:web` to grep a bundle built from today's `HEAD` rather than the
staged one from 2026-08-17; driving a real browser against the live admin panel with DevTools open to
watch **F7**'s CSP violation actually appear in the console, rather than reasoning it from
`SecurityHeaders.java` and `ra-core`'s source; wire-verifying cookie attributes (`Secure`, `HttpOnly`,
`SameSite`, the absence of a `__Host-` prefix) against a real `Set-Cookie` header, which needs a
successful login this phase's rules of engagement forbid producing against production (see the ledger
note in the Method block) — deferred to Phase 8's local, disposable-account container; independently
re-running `secure_token_store_web_test.dart` to watch the web branch's `UnsupportedError` fire, rather
than reading the class that already asserts it; confirming whether a native build carrying the live
`zendemo://` scheme has actually shipped to a real device or store listing (F2's "contingent" status
stays contingent, not "demonstrated" — this needs build-artifact or store evidence outside the
repository); and an independent `task audit`-style dependency audit of react-admin's own transitive
tree beyond the one behaviour (`F7`) found by reading its source directly.

---

## 4. Free wins

*Not started.*

## 5. Priced trade-offs

*Not started.*

## 6. Closed — verified correct, with evidence

*Not started.* Will include one line per confirmed-still-closed item from `SECURITY-REMEDIATION.md`
F1–F20 and `DATA-API-EXPOSURE.md`, each with the evidence that re-confirmed it — not a restatement of
the earlier document.

## 7. ASVS coverage map

*Not started — Phase 9, populated from evidence gathered across Phases 1–8.* Every ASVS 5.0.0 chapter
will be marked `pass` / `gap` / `n/a with reason` / `not assessed`.

## 8. Open questions

*Not started.* Will include, at minimum, the exact command for a human to run the hosted Supabase
Data API lockdown check that this review deliberately does not run (plan §4.4), and the plan's own
open questions (§11) not already settled: Q4 (is `task audit` wired into CI or a schedule anywhere —
ADR-039 exists and should be checked against reality in Phase 6, not assumed from its title), Q5
(assume a second jZen application is imminent per ADR-026), Q7 (a follow-on penetration test, named
as a recommendation only).

## 9. Appendix

*Not started.* Will carry the full control inventory, the silent-no-op census, and the gate-coverage
table from Phase 2, Part C.

---

## Phase 0 record

**Read, in full, in this session (2026-09-18):** `CLAUDE.md`; `docs/architecture/MANIFESTO.md`;
`docs/architecture/BLUEPRINT.md`; `docs/architecture/STANDARDS.md` (all 658 lines);
`docs/plans/implemented/SECURITY-REMEDIATION.md`; `docs/plans/implemented/DATA-API-EXPOSURE.md`;
`docs/plans/SECURITY-ARCHITECTURE-REVIEW-PLAN.md`; `docs/plans/SECURITY-ARCHITECTURE-REVIEW-PROMPT.md`.

**Read from `DECISIONS.md`, per the plan's Phase 0 reading list:** ADR-038 (migration at deploy, not
boot), ADR-037 (the deploy performs the privilege cutover regardless of the plan's stated sequencing;
a silent build-define failure), ADR-036 (every table is exposed to the Data API until two independent
layers say otherwise), ADR-035 (security headers on the Vert.x router; self-hosted renderer; HSTS
stops short of `includeSubDomains`/`preload`), ADR-034 (the dependency-vulnerability gate, `task
audit`, and what its first run found — two HIGH auth-bypass advisories in the deployed Quarkus
version), ADR-033 (migration versions are UTC timestamps), ADR-031 (the application stops being the
database owner; RLS is Supabase-side only), ADR-030 (an unverifiable session cookie means anonymous,
not an error — the ambient-credential rule), ADR-029 (the rate limiter is two tiers, split on window
length against measured process lifetime), ADR-028 (deployment capacity is the application's choice;
what each knob invalidates), ADR-027 (the 200-slot ceiling is accepted; Cloud Armor rejected on cost,
Cloudflare deferred on invariants), ADR-026 (a second product consumes jZen from a sibling checkout —
the framework/application boundary is a live concern, not hypothetical), ADR-019 (exact-match
redirect-target allowlist for email links), ADR-018 (the implicit fragment flow, not PKCE, for
email-link sign-in), ADR-017 (RBAC: framework owns the mechanism, application owns the policy; RLS is
not the app's authorization layer), ADR-008 (guaranteed scheduled work: external trigger, due-ness
from `last_run_at`, no erasure without a delivered warning), ADR-005 (admin panel: framework scaffold
+ per-app panels; framework CRUD resource; bare-array pagination).

**Standards versions fetched and recorded:** see "Standards versions" above — this is the Phase 0
gate per plan §2.1; no requirement is cited before this table existed.

**Scope statement written:** see the header block above (in/out of scope, ASVS level, date).

**Done-when check (plan §Phase 0):** Method block written ✓. Standards-version table complete ✓.

**Explicitly not done in Phase 0** (deferred to their own phases, per the plan): the §3 preconditions
checklist (`task doctor`, `docker info`, a green `task test`, a recorded `task audit` run, `gcloud
auth list`, the local Supabase stack, confirming the hosted-Data-API decision) — these gate the start
of dynamic work in later phases, not the orientation phase, and are not yet run. Phase 1's boundary
diagram and asset/threat tables (now done — see below). Phases 2–9 entirely.

---

## Phase 1 record

**Method:** static read only — no test run, no `task` command executed, no `gcloud` read. Each of
the nine boundaries in §2.2 is grounded in the class or migration that implements it, read this
session, not recalled from the plan's candidate list or from `STANDARDS.md`'s description of it (plan
§5.3's trap): `SessionCookieAuthenticationMechanism`/`SessionService` (B1, B9), `SupabaseAuthClient`
(B2), `R__identity_application_role.sql` (B3), `JobTriggerAuthenticator` (B4),
`R__identity_data_api_lockdown.sql` (B5), `RedirectTargets` + `WellKnownResource` (B6),
`.github/workflows/ci.yml` + `audit.yml` (B7), `CsrfFilter`'s own javadoc + `RoleAugmentor` (B8),
`AdminUserResource` (B9), `DemoWebSocket` + `WebSocketConnections` (the WebSocket surface, folded
into B1/B9 rather than a tenth boundary — it authenticates on the same cookie and the same role).

**Two findings-in-waiting surfaced while grounding the diagram, not yet written up as `F<n>` per §7
of the plan** (that is Phase 2/3's job; recorded here so they are not lost before then):

1. `audit.yml` pins its third-party actions by mutable tag (`actions/checkout@v7`,
   `actions/setup-java@v6`, `actions/setup-node@v7`, `arduino/setup-task@v3`) while `ci.yml` pins the
   identical actions by commit SHA. One workflow got the Phase-6-relevant hardening and the other,
   newer one did not. Candidate scope: pipeline. Candidate boundary: B7.
2. `DemoWebSocket`'s own javadoc states the authorization check runs once, at the HTTP upgrade, and
   is not re-evaluated for the life of the connection — so a logout or a role change does not revoke
   an already-open socket. The javadoc already names this precisely; Phase 3's "revocation latency"
   question (plan §Phase 3) and Phase 4's WebSocket paragraph both point at the same fact. Candidate
   scope: framework (`zen-transport`'s WebSocket pattern, not zen_demo-specific). Candidate boundary:
   B1/B9.

**Corrections to the plan's working assumptions, found by reading rather than inherited** (§2.2's
final paragraph has the detail): B7 is not uniformly hardened across both workflows; B4's
fail-closed property is on the *absence* of a configured secret, which is a stronger and easier-to-
get-wrong guarantee than "a wrong token is rejected."

**Done-when check (plan §Phase 1 deliverable):** one boundary diagram ✓ (§2.4, ASCII). The asset
table ✓ (§2.1, 11 assets, ranked). The per-boundary threat table ✓ (§2.3, STRIDE, live threats only,
out-of-scope threats stated with a reason per boundary and system-wide).

**Phase 1: CLOSED.** All three deliverables the plan names for this phase exist in the report. What
remains open (below) is deferred to later phases by the plan's own phase boundaries, not left
undone within this one — Phase 1 is a static threat model, and the items below are dynamic
verification or finding-ranking work that Phase 1 was never scoped to produce.

**Explicitly not done in Phase 1** (deferred to their own phases, per the plan): quantifying or
ranking the two findings-in-waiting above (Phase 2/3, and only after the §7 finding template is
filled in with confidence/exploitability/fix cost); verifying B5's lockdown actually holds locally
(Phase 5); verifying B6's App Links/Universal Links are actually configured for zen_demo rather than
merely available in `WellKnownResource` (Phase 7); confirming whether `RoleAugmentor`'s per-request
role read actually bounds the WebSocket's revocation gap in practice, or only in the HTTP surface
(Phase 3). Phases 2–9 entirely.

---

## Phase 2 record

**Method:** static read plus one read-only shell census, no `@QuarkusTest` run, no `gcloud` read, no
network call. Grounded in, read this session: every `*.java` filename under `zen-transport`,
`zen-identity`, `zen-ratelimit`, `zen-jobs` (`src/main/java`, listed by module); the full text of
`SecurityHeaders.java`, `RateLimitFilter.java`, `RateLimitRule.java`, `CsrfRules.java` (header),
`AdminUserResource.java` (header + annotations), `UserRetentionService.java` (header); every test
filename under each framework module's `src/test` and under `apps/zen_demo/zen_demo_server/src/test`;
`scripts/verify-boundaries.py` in full (259 lines); the `verify:boundaries`, `verify:docs`,
`verify:contracts`, `audit`, `test:e2e` task summaries in `Taskfile.yml`; `.github/workflows/audit.yml`
in full; `apps/zen_demo/zen_demo_server/src/main/resources/application.properties`'s Flyway block; and
a directory listing confirming `zen_demo_server` ships no `db/migration` of its own.

**Command run this phase** (the plan's own jandex census, reproduced verbatim in §3.2):

```
for m in server/zen-*; do
  printf '%-24s beans:%s jandex:%s\n' "$m" \
    "$(grep -rlE '@Provider|@ApplicationScoped|@Singleton|@Observes' $m/src/main/java 2>/dev/null | wc -l)" \
    "$(grep -c jandex-maven-plugin $m/pom.xml 2>/dev/null)"
done
```

Result: every module with beans has the plugin; `zen-core`/`zen-proto` correctly have neither. This
census is clean today — a "closed, verified" candidate for §6, not a finding — and is recorded as
evidence rather than inherited from `CLAUDE.md`'s prose claim that it holds.

**The dependency-tree command the plan also names**
(`server/mvnw -B -f apps/zen_demo/zen_demo_server/pom.xml dependency:tree`) was **not run this
phase** — it requires a full Maven resolution and was judged lower value than the static reads above
for the time available; ADR-034's Wave 4.2 already found and fixed the one case this would have
caught (`quarkus-smallrye-openapi` arriving transitively), and Phase 4 re-verifies that specific
regression from the wire instead. Named here rather than silently skipped.

**One new finding-in-waiting**, not yet written up as `F<n>` per §7 (that is Phase 3's job; recorded
here so it is not lost): an app that never wires Cloud Scheduler → `/api/v1/jobs/trigger` gets
`UserRetentionService`'s code but never its behaviour, and nothing in the test suite or a gate
distinguishes "retention is wired and idle because nothing is due yet" from "retention has never run
once" (§3.2, item 4).

**One gate gap confirmed rather than assumed**: `verify:boundaries` does not scan Kotlin or Swift
platform-channel source, confirmed by reading the script's scope constants
(`DART_LIB_SCOPES`/`TS_SRC_SCOPES`) against an actual directory listing that shows `.kt`/`.swift`
files exist in the client's native shells today (currently unmodified boilerplate — no live
violation, a coverage gap rather than an active finding).

**Done-when check (plan §Phase 2 deliverable):** the control inventory ✓ (§3.1, 13 rows, the
"inherited" column populated for each). The silent-no-op census ✓ (§3.2 — the jandex script rerun,
the three `CLAUDE.md` instances re-cited plus one new one, six paper-attack scenarios attempted on
paper with one succeeding). The gate-coverage table ✓ (§3.3, five gates: `verify:boundaries`,
`verify:docs`, `verify:contracts`, `audit`, `test:e2e`).

**Phase 2: CLOSED.** All three deliverables the plan names for this phase exist in the report, each
grounded in a specific file, test name, or command output rather than recalled from the plan's own
description of what should be there (plan §5.3's trap, same discipline as Phase 1).

**Explicitly not done in Phase 2** (deferred to their own phases, per the plan): quantifying or
ranking the new retention-scheduling finding and the `verify:boundaries` coverage gap into `F<n>`
entries with confidence/exploitability/fix cost (Phase 3 owns the finding template, plan §7); the
`dependency:tree` command (not run, reasoned above); verifying whether `ZenTransportFilter`'s absence
has a safe default (deferred to Phase 4, which owns the transport seam); re-reading
`InvalidBodyExceptionMapper`'s body to confirm it never leaks a stack trace (Phase 4); verifying
whether a second `MessageBodyWriter` for `application/json` would actually be silently preferred, or
whether SmallRye/RESTEasy Reactive provider-priority rules would prevent it (Phase 4); confirming the
Data API lockdown's migration-ordering question — does the default-privilege revoke cover a table
created by a *later* migration (Phase 5). Phases 3–9 entirely.

---

## Phase 3 record

**Method:** static read only — no `@QuarkusTest` run, no `gcloud` read, no network call, no forced
failure. Grounded in, read this session, in full: `SessionService.java`,
`SessionCookieAuthenticationMechanism.java`, `RoleAugmentor.java`, `UserRoleLoader.java`,
`CsrfRules.java`, `CsrfFilter.java`, `RedirectTargets.java`, `WellKnownResource.java`,
`AuthResource.java`, `IdentityService.java`, `AdminUserResource.java`, `DemoResource.java`,
`DemoWebSocket.java`; `application.properties`'s JWT/session/redirect/App-Links config block;
`apps/zen_demo/zen_demo_client/android/app/src/main/AndroidManifest.xml` and
`apps/zen_demo/zen_demo_client/ios/Runner/Info.plist` (grep for the registered custom scheme);
`Taskfile.yml`'s deploy documentation (~lines 2000–2100, the PUBLIC-config and App-Links steps); and
`apps/zen_demo/zen_demo_client/test/auth_deep_links_native_test.dart` (confirming the scheme is
exercised, not dead code).

**Two findings minted** (§3.4): **F1** (a WebSocket's authorization is checked only at handshake,
never revalidated for the connection's life — framework-scope, confirmed by reading
`DemoWebSocket`'s own javadoc against its actual method bodies) and **F2** (App Links/Universal
Links, the documented mitigation for the RFC 8252 custom-scheme hijack on the email-link flow, are
optional and unenforced by any gate — confirmed by reading `Taskfile.yml`'s own deploy documentation
and the native manifests that already register the scheme it warns about).

**One item raised in Phase 1 as a finding-in-waiting is now resolved rather than minted**: B4's
fail-closed property (an unconfigured `ZEN_JOBS_TRIGGER_TOKEN` rejects every call) was re-confirmed
structurally sound in Phase 2's control inventory and needed no further Phase 3 action — it is a
session/authz-adjacent control but not an identity/session-management question this phase owns.

**Three items explicitly answered "not tested, reasoned from code" rather than asserted as either a
finding or a closure** (per §5.3's trap — reading the code is not reviewing the system): JWKS-
unreachable behaviour (reasoned: degrades every session to anonymous, fails closed on authorization
but silently mass-signs-out for the outage's duration); JWT clock-skew tolerance (no explicit
property set; SmallRye JWT's own default applies, unconfirmed); and the timing half of the
enumeration-resistance property (the structural half — identical status/shape — is confirmed; timing
itself needs a running measurement). All three are carried into Phase 8 rather than closed here.

**Done-when check (plan §Phase 3):** the plan's own question table (Cookie attributes; Token
lifetimes/rotation/revocation; JWT verification; Role resolution; BOLA; BFLA; CSRF; Open redirect;
the email-link flow; Enumeration and timing) is answered in full ✓ (§3.4's table, ten rows). Findings
minted where evidence supported one, in the plan's §7 template ✓ (F1, F2). Items needing a running
system rather than a reading are named as open rather than guessed ✓.

**Phase 3: CLOSED.** All ten Phase-3 questions the plan names are answered with evidence in §3.4,
two are minted as findings in the plan's own template, and the items that could not be answered by
reading alone are named explicitly rather than asserted either way — the same discipline as Phases
0–2 (plan §5.3's trap).

**Explicitly not done in Phase 3** (deferred to their own phases, per the plan): forcing and
observing JWKS-unreachable behaviour, clock-skew tolerance, and login-timing enumeration resistance
(Phase 8, needs a running server/clock); wire-verifying cookie attributes rather than reading the
issuing code (Phase 7/8); confirming whether a native build with a live scheme redirect has actually
shipped to users, which would move F2 from "contingent" to "demonstrated" exploitability (Phase 6/7);
re-deriving `JobTriggerResource`'s CSRF/RolesAllowed status independently of Phase 2's inventory (no
change expected, not re-read). Phases 4–9 entirely.

---

## Phase 4 record

**Method:** static read plus two local, read-only `mvnw dependency:tree` runs (with and without
`-Dnative`, against `apps/zen_demo/zen_demo_server/pom.xml`) — no `@QuarkusTest` run, no `gcloud`
read, no network call, no forced failure. Grounded in, read this session, in full:
`ProtobufMessageBodyReader.java`, `ProtoJsonMessageBodyReader.java`, `InvalidBodyExceptionMapper.java`,
`ZenTransportFilter.java`, `ZenTransportFormat.java`, `RateLimitFilter.java` (javadoc + `@Priority`),
`WebSocketConnections.java`, `DemoWebSocket.java` (re-consulted, not re-argued, for its Phase-3 **F1**
gap); every `proto/zen/v1/*.proto` file, grepped for `oneof`/`google.protobuf.Any`; every non-`target`
`pom.xml` in the repository, grepped for `jackson`; `apps/zen_demo/zen_demo_server/src/main/resources/
application.properties`'s HTTP-limits and WebSocket blocks; `Taskfile.yml`'s native-build invocation
(`-Dnative`, confirming which profile ships to production); and `RateLimitCsrfOrderingTest.java`
(confirming the filter-ordering claim is pinned by a test, not merely argued in a javadoc).

**Commands run this phase** (both read-only, no write, no network beyond local Maven resolution):

```
server/mvnw -B -f apps/zen_demo/zen_demo_server/pom.xml dependency:tree                    # no profile
server/mvnw -B -f apps/zen_demo/zen_demo_server/pom.xml dependency:tree -Dnative           # production profile
```

Result: `quarkus-smallrye-openapi` present without `-Dnative`, absent with it — confirming the
`!native` profile activation in `pom.xml:283-291` behaves as documented and that Wave 4.2's removal
has not regressed. The actual `quarkus-rest-jackson` extension (and its deployment/build-time
augmentation artifact, which is what would register a competing JAX-RS provider) is absent from both
trees. **Found on closer inspection of the `-Dnative` tree, not merely assumed absent from a
top-level grep**: `quarkus-jackson` (base CDI/`ObjectMapper` support), `quarkus-rest-jackson-common`,
and `resteasy-reactive-jackson` are all present, transitively, under `quarkus-rest-client-jackson` —
shared runtime code for the client/server Jackson integrations, not the provider-registering
extension itself, and consistent with the sanctioned outbound-only usage, but close enough in name
to be worth naming precisely (§3.5's table) rather than folding into a blanket "no jackson server-side"
claim.

**One finding minted** (§3.5): **F3** — the no-server-side-Jackson invariant (STANDARDS, CLAUDE.md,
plan §7.1 item 10) is enforced today by convention and code review only; no Maven enforcer rule, CI
step, or test was found anywhere in the modules read across Phases 2 and 4 that would fail if
`quarkus-rest-jackson` were reintroduced. Scoped as process/framework rather than a live
vulnerability — nothing in this review found the invariant actually violated, only unguarded.

**Two items answered "reasoned from code, not forced" rather than asserted as either a finding or a
closure** (§5.3's trap, same discipline as Phase 3): the JSON codec path's recursion/nesting-depth
behaviour (no explicit jZen override exists; Gson's own default was not independently measured this
phase); and the precise cost/DoS-shape of a maximally-nested payload within the 1MB body cap. Both
are carried into Phase 8's "oversized and malformed bodies on both codec paths" step rather than
closed here.

**Phase 3's F1 (WebSocket revocation) is re-touched, not re-argued**: Phase 4 independently confirmed
the frame-size and connection-cap limits sit correctly alongside that gap (they bound size and count,
not session lifetime), and that `WebSocketConnections`' own javadoc already prices the
`--max-instances=1` premise its in-memory counters depend on — no new finding minted for the cap
mechanism itself.

**Done-when check (plan §Phase 4):** every bullet the plan names for this phase — size/recursion
limits on each codec, unknown-field handling, `Any`/`oneof` usage, malformed-body output,
`@PreMatching` ordering vs. rate limiting and authentication, header-driven dispatch, the WebSocket's
frame-size/connection-cap/per-instance scoping, the OpenAPI-surface regression check, and the Jackson
prohibition — is answered with evidence in §3.5's table ✓. One finding minted in the plan's §7
template ✓ (F3). Items needing a forced failure or a running server rather than a reading are named
as open rather than guessed ✓.

**Phase 4: CLOSED.** All bullets the plan names for this phase are answered with evidence in §3.5,
one is minted as a finding in the plan's own template, and the items that could not be answered by
reading (plus two read-only `dependency:tree` runs) alone are named explicitly rather than asserted
either way — the same discipline as Phases 0–3 (plan §5.3's trap).

**Explicitly not done in Phase 4** (deferred to their own phases, per the plan): forcing and
observing an oversized or deeply-nested malformed body on either codec path (Phase 8, needs a running
server); independently measuring Gson's JSON recursion-depth default (Phase 8, if pursued); forcing a
`quarkus-rest-jackson` reintroduction to observe the documented 500 directly rather than citing
CLAUDE.md's account (out of scope for a static phase per plan §10 — no tracked file is edited to
demonstrate a finding); re-arguing Phase 3's **F1** independently (re-touched, not re-derived, above).
Phases 5–9 entirely.

---

## Phase 5 record

**Method:** static read only — no `@QuarkusTest` run, no `task run:supabase`, no `gcloud` read, no
network call, no forced failure. Grounded in, read this session, in full:
`R__identity_application_role.sql`, `R__identity_data_api_lockdown.sql`,
`R__jobs_row_level_security.sql`, `R__ratelimit_row_level_security.sql`, `MigrateOnlyRunner.java`,
`DurableLimiter.java`, `UserRoleLoader.java`, `UserRetentionService.java`, `UserRetentionJob.java`,
`UserRetentionZenJob.java`, `EmailService.java`, `DemoMailer.java`, `JobScheduler.java`; the relevant
methods and javadoc of `UserStore.java` (`upsertOnLogin`, `INSERT_IF_ABSENT`); the test method names
and key assertions of `DatabasePrivilegeTest.java` (not executed — read for what it proves);
`Taskfile.yml`'s deploy summary (the seven/nine-secret provisioning list, steps 1/1a-config/1c); and
`DECISIONS.md` ADR-007 (email split, referenced for the `auth.users` boundary), ADR-008 (retention
cycle, the donor's fourth phase not ported), ADR-031 (the privilege split and RLS-is-Supabase-side
decision, in full), ADR-036 (the Data API exposure and its two-layer fix, in full), ADR-037 (the
deploy cutover measurement, in full), ADR-041 (the Data API lockdown outcome assertion, in full).

**No command was run this phase.** The plan's own Phase 5 method implies enumerating grants against
a local database (§Phase 5: "enumerate the actual grants against a local database"); this phase
instead read `DatabasePrivilegeTest`'s assertions as a proxy for that enumeration and cited the
live-database measurements ADR-031/036/037/041 already recorded (2026-08-04 and 2026-08-14, against
`jzen-prod` and a throwaway Postgres respectively) rather than reproducing them. Reasoned, not
merely convenient: those ADRs measured the identical questions this phase would otherwise re-ask,
against a real Supabase project in one case, more authoritative than a fresh local run against Dev
Services' plain Postgres (which lacks an `auth` schema and stands in for Supabase's own RLS-relevant
state only partially, as `R__identity_application_role.sql`'s own guards acknowledge). Independently
re-running the enumeration remains open for Phase 8, which is where this review's own dynamic
verification belongs by the plan's own phase boundaries.

**One finding minted** (§3.6): **F4** — anonymisation clears the application's own copy of a
person's data, but the Supabase-owned `auth.users` record it authenticates against (the original
email address, GoTrue's sign-in history) is retained indefinitely with no automated path to remove
it, because jZen deliberately never holds a `service_role` credential capable of doing so
(ADR-007/ADR-008's own stated scope boundary, confirmed structurally this phase rather than merely
quoted). Framed as an architectural/data-protection finding per the plan's own instruction not to
attempt a legal assessment, not as a GDPR-noncompliance conclusion.

**This review's own F10 is independently re-verified, not re-derived.** ADR-041 (dated 2026-08-14,
predating this review's Phase 5 pass) already names and fixes a Data-API-lockdown gap as "F10 of the
2026-08-13 architectural security review" — the DDL role's default-privilege revoke is captured once,
at the repeatable migration's last checksum-triggered run, so a later DDL-role rotation does not
retroactively re-point it. This phase confirmed the fix is real and matches the ADR's account by
reading `MigrateOnlyRunner.java` in full: its `dataApiExposure` method queries
`information_schema.role_table_grants` and `pg_default_acl` directly on every deploy, splitting
fatal drift (a reachable role still granting `anon`/`authenticated`) from a warned-only residual (an
unreachable role, e.g. `supabase_admin`) exactly as the ADR describes. No new finding was minted for
this — it is recorded as **closed, independently verified**, consistent with the plan's own rule
against re-finding what a predecessor (here, this same review's own earlier pass) already closed.

**One correction to the plan's own framing, found by reading rather than inherited**: the plan's
own §Phase 5 bullet states "17 GCP secrets injected as env vars per instance start." Reading
`Taskfile.yml`'s actual deploy summary finds **seven genuine Secret Manager entries**, plus an
explicitly-labelled optional
eighth/ninth pair (`APP_DB_USERNAME`/`APP_DB_PASSWORD`). The "17" figure traces to
`STANDARDS.md`'s cold-start performance accounting — "17 secret injections" as part of Cloud Run's
platform overhead — which counts every `--set-env-vars` injection (public configuration included)
at container start, not the number of confidential Secret Manager entries. Named here in the same
spirit as Phase 1's B4/B7 corrections: found by reading the two sources against each other, not
assumed from either alone.

**Done-when check (plan §Phase 5):** the privilege split, enumerated against a local database ✓ (by
citing `DatabasePrivilegeTest`'s assertions and ADR-031/037's live measurements, per the Method note
above, rather than a fresh run — an explicit, reasoned substitution, not a silent skip). RLS scope,
stated plainly ✓ (§3.6's table, "Supabase-side only... provides zero defense-in-depth" for a
`zen_runtime`-credential compromise). The Data API boundary, both layers plus the default for a new
table ✓ (§3.6, including this review's own F10 re-verified). Injection, checked only what is new ✓
(rate-limit upsert, first-login race fix, retention queries — all parameterized, nothing new found).
Privacy and data lifecycle ✓ (retention ordering re-confirmed by code, PII-free logging confirmed,
and the `auth.users` gap minted as F4). Secrets ✓ (count corrected, none committed, none reaching a
client bundle, no secret value reaching a log or error response, rotation story named as an open
question rather than asserted safe).

**Phase 5: CLOSED.** Every bullet the plan names for this phase is answered with evidence in §3.6,
one new finding is minted in the plan's own template (F4), this review's own earlier finding (F10)
is independently re-verified rather than re-derived or silently skipped, and the items that would
need a running system or a fresh live-database probe are named as explicitly deferred rather than
guessed — the same discipline as Phases 0–4 (plan §5.3's trap).

**Explicitly not done in Phase 5** (deferred to their own phases, or out of this review's scope
entirely, per the plan): re-running `DatabasePrivilegeTest` or any other `@QuarkusTest` this session;
starting `task run:supabase` and independently re-measuring grants against a fresh local stack;
probing the hosted Supabase Data API (plan §4.4, an owner decision, unchanged); a legal/compliance
conclusion on F4's GDPR Art. 17 completeness (an architectural finding was minted instead, per the
plan's own instruction); designing a rotation-alerting mechanism for the seven/nine secrets (named as
an open question for Phase 9). Phases 6–9 entirely.

---

## Phase 6 record

**Method:** static read of `.github/workflows/ci.yml`, `.github/workflows/audit.yml`,
`.github/dependabot.yml`, `apps/zen_demo/zen_demo_server/src/main/docker/Dockerfile.native-micro`,
`server/.mvn/wrapper/maven-wrapper.properties`, `Taskfile.yml`'s `deploy:cloudrun` task and deploy
summary, `admin/package.json`'s and `apps/zen_demo/zen_demo_admin/package.json`'s `packageManager`
fields, and `DECISIONS.md` ADR-039 and ADR-043 in full — plus a bounded set of **read-only
control-plane calls**, none against the deployed service and none costing the plan's §4.3 production
HTTP request budget: `gcloud auth list`, `gcloud projects get-iam-policy jzen-prod`, `gcloud
artifacts repositories list --project=jzen-prod`, `gcloud artifacts docker images list
europe-central2-docker.pkg.dev/jzen-prod/jzen --project=jzen-prod` (twice — once for a sample, once
`--format="value(package)" | wc -l` for a count), `gcloud artifacts repositories describe jzen
--project=jzen-prod --location=europe-central2 --format="yaml(cleanupPolicies,...)"`, `gcloud
artifacts repositories get-iam-policy jzen --project=jzen-prod --location=europe-central2`, `gh api
repos/jZenDev/jZen` (visibility), `gh api repos/jZenDev/jZen --jq '.security_and_analysis'`, `gh
secret list --repo jZenDev/jZen`, `gh api repos/jZenDev/jZen/environments`, `gh api
repos/jZenDev/jZen/branches/main/protection`. No `gcloud`/`gh` mutation was run; no production
service endpoint was queried this phase (that budget is reserved for Phases 7/8 per the plan).

**One finding minted** (§3.7): **F5** — `.github/workflows/audit.yml`'s five third-party actions
(`actions/checkout`, `actions/setup-java`, `actions/setup-node`, `arduino/setup-task`,
`actions/setup-python`) are still pinned by mutable tag, unchanged since before F12 (closed
2026-08-14) SHA-pinned the identical actions everywhere in `ci.yml` — an asymmetry Phase 1 (§2.2)
already flagged by reading both workflow files and explicitly deferred to Phase 6, now confirmed
still live and written up in the plan's §7 template.

**Two plan bullets resolved as already-closed rather than newly found**, read and cited rather than
re-derived: **Is `task audit` wired into CI?** — yes, per ADR-039 and `audit.yml` itself, resolving
plan §11 Q4 (an "open question" the plan flagged that Phase 6 was explicitly tasked with settling,
not a finding). **Base image digest pin, non-root `USER`, SBOM, signing, provenance** — ADR-043
(2026-08-14) had already closed this exact bullet as this review's own earlier F6, before today's
2026-09-18 session reopened Phase 6; this phase's contribution is re-confirming ADR-043's claim
against the current `Dockerfile.native-micro` and `Taskfile.yml` rather than trusting the ADR's
account unexamined (§5.3's trap, same discipline as Phase 5's re-verification of its own F10) —
**no drift found**.

**One correction-shaped observation, not minted as a finding**: the Artifact Registry image count
has grown from "51 at last count" (predecessor audit) to 81 today, and reading the repository's
actual cleanup policy (three rules, this phase) shows why — tagged images are kept forever by
policy, not by oversight. Named as an open question for Phase 9 (a storage-cost pricing question,
not a security gap) rather than a finding, the same discipline Phase 5 applied to the Artifact
Registry's least-privilege-vs-single-owner question.

**Done-when check (plan §Phase 6):** every bullet the plan names for this phase — is `task audit`
wired in; workflow token permissions and fork-PR blast radius; action pinning by tag vs. digest;
GCP deploy authentication (key vs. workload identity); base image digest pin and non-root user;
SBOM/signing/provenance; checksum-less build-time fetches (`dart pub global activate`, `corepack`,
the Maven wrapper); secret scanning/push protection and any committed credential; Artifact Registry
push rights and old-image liability — is answered with evidence in §3.7's table ✓. One finding
minted in the plan's §7 template ✓ (F5). Two bullets resolved as already-closed by an existing ADR
rather than re-opened as new findings, each re-verified against current code rather than taken on
the ADR's word alone ✓.

**Phase 6: CLOSED.** Every bullet the plan names for this phase is answered with evidence in §3.7,
one new finding is minted in the plan's own template (F5), two bullets already closed by ADR-039/
ADR-043 in an earlier pass of this same review are independently re-verified rather than re-derived
or silently skipped, and the items needing a live-repository test (a real forked PR, an
independent `task audit` re-run) or a pricing decision (registry storage growth, a narrower
push-role design) rather than a reading are named as explicitly deferred — the same discipline as
Phases 0–5 (plan §5.3's trap).

**Explicitly not done in Phase 6** (deferred to Phase 9, or out of this review's scope entirely, per
the plan): pricing the Artifact Registry storage-growth question or a narrower push-role design
(Phase 9); independently re-running `task audit` this session; testing GITHUB_TOKEN scoping against
a real forked-repository PR rather than reasoning it from GitHub's documented trigger-scoping rule;
a branch-protection finding for the absence of required PR review or signed commits (read this phase,
not minted — a solo-maintainer repository cannot meaningfully require a second reviewer, named as an
open question instead, the same discipline Phase 5 applied to secret rotation for an equally
small-team context). Phases 7–9 entirely.

---

## Phase 7 record

**Method:** static read of `client/zen_secure_store/lib/src/secure_token_store*.dart`,
`client/zen_identity/lib/src/zen_identity_config.dart`, `client/zen_core/lib/src/zen_constants.dart`,
`scripts/verify-boundaries.py`, `server/zen-transport/src/main/java/zen/transport/SecurityHeaders.java`,
`server/zen-transport/src/main/java/zen/transport/CorsCredentialsGuard.java`,
`admin/src/authProvider.ts`, `admin/src/dataProvider.ts`, `apps/zen_demo/zen_demo_admin/src/App.tsx`,
`apps/zen_demo/zen_demo_client/lib/main.dart`, every `.kt`/`.swift` file under
`apps/zen_demo/zen_demo_client/{android,ios,macos}`, `admin/node_modules/.pnpm/ra-core@5.15.0.../
node_modules/ra-core/src/core/CoreAdminUI.tsx` (react-admin's own telemetry source, read directly
rather than assumed from its public docs), and the relevant `DECISIONS.md` entries (the App Links
Android/iOS split dated 2026-08-01, and the token-store Wasm-compatibility and Keychain/Keystore
decisions dated 2026-07-31) — plus a grep of the **already-staged** production web and admin bundles
under `apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources` (built 2026-08-17, not
rebuilt this phase) for provider hosts, keys, and `eyJ`-shaped tokens.

**Dynamic evidence, live against production, read-only:** 11 of the plan's 12-request budget (§4.3),
logged in the ledger in the Method block near the top of this document — security headers on the SPA
root, `/admin/`, an unauthenticated API path, and a hashed admin static asset (all four byte-identical
to `SecurityHeaders.java`'s source); a CORS preflight from a disallowed origin (403, no origin
echoed); the OpenAPI/Swagger/dev/health surface (all 404 in prod, corroborating Phase 4's
dependency-tree finding from the wire); and both App Links well-known association files (both 404,
corroborating Phase 3's **F2** with a live read of the one environment that exists). Request #12 (the
reserved cookie-attribute read) was deliberately not spent — see the ledger note for why, and why it
is deferred to Phase 8's local, disposable-account container rather than skipped for no reason.

**One finding minted** (§3.8): **F7** — react-admin's default telemetry beacon (an unguarded `<Admin>`
call in `apps/zen_demo/zen_demo_admin/src/App.tsx`, no `disableTelemetry` prop) ships to production
unreviewed and is blocked today only because `SecurityHeaders.java`'s `img-src` directive happens not
to name its host — a coincidence, not a decision, and exactly the kind of CSP-widening trap the
class's own javadoc already warns about for an unrelated reason.

**One already-fixed gap re-confirmed rather than re-found**: the web build of `SecureTokenStore`
throws `UnsupportedError` at construction instead of falling back to `flutter_secure_storage_web`'s
`window.localStorage`, closing exactly the MASVS-STORAGE gap plan §Phase 7 asks this phase to look
for. DECISIONS.md's 2026-07-31 entries show this was already found and fixed ahead of this review,
and `apps/zen_demo/zen_demo_client/lib/main.dart`'s `zenIsWeb ? null : SecureTokenStore()` guard is
confirmed still in place, now redundant belt-and-braces rather than the only thing standing between
the refresh token and an XSS-readable browser store.

**One gap confirmed still open, on paper, and still unexploited in practice**: `verify:boundaries`
(read in full, both this phase and Phase 2) does not scan `apps/zen_demo/zen_demo_client/{android,
ios,macos}` at all. Reading every `.kt`/`.swift` file under those trees this phase (all Flutter
boilerplate, 5–32 lines each) confirms there is currently nothing there for the gap to hide — the
paper attack Phase 2 described has no live instance today.

**Done-when check (plan §Phase 7):** every bullet the plan names for this phase — compile-time config
and bundle secrets; the one-server rule from the client's side; token storage (MASVS-STORAGE) on
mobile vs. web; security headers from the wire in a real browser; the admin panel's auth, session,
XSS surface, and header parity; deep links and App Links — is answered with evidence in §3.8's table
✓. One finding minted in the plan's §7 template ✓ (F7). One already-closed gap and one still-open,
still-unexploited gap are each independently re-verified against current code rather than taken on a
prior pass's or an ADR's word alone ✓. The production request budget is opened and 11 of 12 rows are
logged in the Method block's ledger ✓.

**Phase 7: CLOSED.** Every bullet the plan names for this phase is answered with evidence in §3.8,
one new finding is minted in the plan's own template (F7), the MASVS-STORAGE web-fallback gap is
re-confirmed closed rather than re-discovered, the native-platform-channel gap in `verify:boundaries`
is re-confirmed open but inert, and the items needing a live browser session, a fresh bundle rebuild,
or a login against production (which the rules of engagement forbid) are named as explicitly
deferred to Phase 8 — the same discipline as Phases 0–6 (plan §5.3's trap).

**Explicitly not done in Phase 7** (deferred to Phase 8, or out of this review's scope entirely, per
the plan): re-running `task build:web` against today's `HEAD` rather than grepping the 2026-08-17
staged bundle; driving a real browser with DevTools open against the live admin panel to watch **F7**'s
CSP violation actually appear, rather than reasoning it from `SecurityHeaders.java` and `ra-core`'s
source; a login against production to wire-verify cookie attributes (forbidden by plan §4.2/§4.3 —
deferred to Phase 8's local, disposable-account container); re-running `secure_token_store_web_test.dart`
to watch the web branch's `UnsupportedError` fire live rather than reading the class that already
asserts it; confirming whether a native build carrying the live `zendemo://` scheme has actually
shipped to a real device or store listing (F2 stays "contingent," not "demonstrated"); and an
independent dependency audit of react-admin's own transitive tree beyond the one behaviour (F7) found
by reading its source directly. Phases 8–9 entirely.
