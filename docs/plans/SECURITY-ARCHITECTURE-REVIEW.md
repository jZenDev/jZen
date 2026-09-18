# The architectural security review

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative, and ADRs win on conflict.

**Reviewed:** 2026-09-18. **Phase 0 CLOSED** (orientation and scope freeze). **Phase 1 CLOSED**
(assets, trust boundaries, threat model). **Phase 2 CLOSED** (the inheritance audit and
silent-no-op census — see "Phase 2 record" for the closure check against the plan's own deliverable
list). **Phase 3 CLOSED** (identity, session, authorization — see "Phase 3 record"). **Phase 4
CLOSED** (the transport seam and the two parsers — see "Phase 4 record"). Phases 5–9 are not yet
executed. Sections 4–9 below remain placeholders except where Phase 4 populated §3.5.

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
- **Production request ledger:** not yet opened — Phase 7/8 is where the budgeted 12 reads (plan
  §4.3) are spent and logged, one row per request (method, path, purpose, response code, cold/warm).
- **Tools:** none run yet. Phase 8 is the only phase that runs a scanner (an OWASP ZAP baseline
  passive scan against the local container) and it will be recorded here by name, version and
  configuration when it runs.
- **What was NOT assessed (as of Phase 4):** Phases 5–9 have not started. Phase 4, like Phases 1–3,
  ran no `@QuarkusTest` and no `gcloud` or network read against production; it is a static read of
  the transport-seam code cited in §3.5, plus one local, read-only `mvnw dependency:tree` run (both
  with and without `-Dnative`) to confirm the OpenAPI/Jackson dependency questions rather than trust
  a grep of `pom.xml` alone. It did **not** empirically fuzz either codec path with oversized or
  malformed bodies, measure JSON/protobuf recursion-depth behaviour under an actual attack payload,
  or force a `quarkus-rest-jackson` regression to observe the 500 CLAUDE.md describes — those need a
  running server and are named as open items in §3.5 for Phase 8. This line is updated as each phase
  closes; "not assessed" is an honest, acceptable entry per chapter (plan §2.3), an *unmarked* one is
  not.

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
