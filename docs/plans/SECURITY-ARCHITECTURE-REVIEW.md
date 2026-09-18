# The architectural security review

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative, and ADRs win on conflict.

**Reviewed:** 2026-09-18 (Phase 0 — orientation and scope freeze; Phase 1 — assets, trust
boundaries, threat model). Phases 2–9 are not yet executed. Sections 4–9 below remain placeholders.

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
- **What was NOT assessed (as of Phase 1):** Phases 2–9 have not started. Phase 1 itself did not run
  any code or test — it is a static read of the classes and migrations cited in §2, confirming the
  plan's candidate boundary list against what the code actually does rather than diagramming from
  memory. This line is updated as each phase closes; "not assessed" is an honest, acceptable entry
  per chapter (plan §2.3), an *unmarked* one is not.

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

*Not started — Phase 2, the centrepiece.* Will carry the control inventory (where each control's code
and tests live, whether a new app inherits it, and whether it fails open or closed and silently) and
the silent-no-op census, extending the three instances `CLAUDE.md` already names (a library module
missing `jandex-maven-plugin`; a client reaching Supabase directly; `quarkus-rest-jackson` present
server-side).

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

**Explicitly not done in Phase 1** (deferred to their own phases, per the plan): quantifying or
ranking the two findings-in-waiting above (Phase 2/3, and only after the §7 finding template is
filled in with confidence/exploitability/fix cost); verifying B5's lockdown actually holds locally
(Phase 5); verifying B6's App Links/Universal Links are actually configured for zen_demo rather than
merely available in `WellKnownResource` (Phase 7); confirming whether `RoleAugmentor`'s per-request
role read actually bounds the WebSocket's revocation gap in practice, or only in the HTTP surface
(Phase 3). Phases 2–9 entirely.
