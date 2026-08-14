# Execution plan: the architectural security review (OWASP-framed)

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative, and ADRs win on conflict.

**Written:** 2026-08-13
**Produces:** `docs/plans/SECURITY-ARCHITECTURE-REVIEW.md` and nothing else. No code change, no
ADR, no migration, no deploy.
**Predecessor:** [`implemented/SECURITY-REMEDIATION.md`](implemented/SECURITY-REMEDIATION.md)
(audited 2026-08-03, all four waves implemented). This review is **not** a re-run of it. §1 states
the difference, and it is the whole reason this plan exists.

**§1 and §2 are the parts to read first.** §1 says what would make this review redundant; §2 says
which OWASP artifacts form its spine and — importantly — that their versions must be *established*,
not recalled.

---

## 1. Why a second review, and how it differs from the first

`SECURITY-REMEDIATION.md` was an **implementation audit**: it read every security-relevant path and
produced twenty findings, each anchored to a file and a line (`AuthResource.java:207`,
`Taskfile.yml:1459`, `application.properties:120`). That was the right instrument at the time, and
it worked — F1–F19 are closed and F20 became a standing gate (ADR-034) whose first run caught two
HIGH authentication-bypass advisories in the deployed Quarkus version.

**This review asks a different question.** Not *"is this line wrong"* but *"is this the right shape,
and does the shape hold when nobody is watching"*. Three properties distinguish it:

| | The 2026-08-03 audit | This review |
|---|---|---|
| Unit of finding | a line of code | a boundary, a control's *location*, or a property that can silently stop holding |
| Subject | `zen_demo` as deployed | **jZen as a framework** — what a second application inherits, and what it must remember to do |
| Standard | none named; the auditor's judgement | OWASP ASVS as the spine, with the surface-specific lists layered on (§2) |

**The framework question is the centre of gravity, and it is the one no generic checklist asks.**
jZen is a platform: `server/zen-*` and `client/zen_*` are libraries, `apps/<app>/` assembles them,
and ADR-026 already contemplates a second product consuming jZen from a sibling checkout. So every
control in the system has an architectural property that a line-level audit cannot see:

1. **Where does it live** — in a framework library (inherited by every app) or in `apps/zen_demo`
   (inherited by nobody)?
2. **Can an application silently fail to receive it?**
3. **If it is missing, does anything fail closed — or does the app just quietly become insecure?**

Question 2 is jZen's signature defect class, and the repository already names three instances of it
in `CLAUDE.md` without generalising the pattern:

- a library module that omits `jandex-maven-plugin` has its filters, writers, mappers and augmentors
  **silently do nothing — no error**;
- a client package that reaches Supabase directly "fails *silently* if broken — the app would
  authenticate and every suite would still pass";
- `quarkus-rest-jackson` on the server must be *absent*, not out-prioritised, because it wins
  through a build-time path that ignores writer priority.

Each was found the hard way and fixed in place. **Nobody has yet asked how many more there are**, or
whether the countermeasures (`verify:boundaries`, the Jandex rule in STANDARDS) are enforcement or
folklore. That census is Phase 2 and it is the highest-value deliverable in this plan.

**Explicitly out of scope: re-finding F1–F20.** Confirming a closed finding is still closed is one
line in a table (§7's "Closed" group), not a finding. A review that rediscovers rate limiting or
CSRF has failed.

---

## 2. The standards spine — and the rule about versions

### 2.1 Establish every version; recall none

The house rule from `PERFORMANCE-AUDIT-PLAN.md` §7 — *record each rate and its source, pricing page
URL plus date read* — applies here with more force, because a security standard that has moved is
worse than no standard: it produces confident findings against retired requirements.

**Before Phase 1, fetch and record**, for each artifact below: the exact version, its release date,
and the URL and date read. If an artifact turns out to have been superseded, use the successor and
say so in the report. **Do not cite a requirement number from memory** — ASVS renumbered wholesale
between 4.0 and 5.0, and a wrong "V4.1.3" is indistinguishable from a fabricated one.

### 2.2 Which artifact governs which surface

| Surface | Primary artifact | Why this one |
|---|---|---|
| Whole system, requirement-by-requirement | **OWASP ASVS** (current major) | The only OWASP artifact that is a *checklist* rather than a ranking. It is the spine; everything else layers on. Choose a level and justify it (§2.3). |
| REST + WebSocket surface | **OWASP API Security Top 10** | jZen is API-first. BOLA/BFLA and "unrestricted resource consumption" are the classes that matter for `AdminUserResource`, `/api/v1/jobs/trigger` and `/api/v1/demo/ws`. |
| Flutter client (mobile + web) | **OWASP MASVS**, with **MASTG** for test procedures | The client stores a refresh token in Keychain/Keystore; MASVS-STORAGE is already cited in the code. |
| GitHub Actions, `deploy:cloudrun`, Artifact Registry | **OWASP CI/CD Security Top 10** | The build path has never been reviewed at all (§6, Phase 6). |
| Framing and the report's vocabulary | **OWASP Top 10** (web) | For communication only. It is a ranking of prevalence, not a checklist — do not use it as coverage. |
| Design-time guidance | **OWASP Proactive Controls**; the relevant **Cheat Sheets** | `SessionService` already cites the Session Management cheat sheet; JWT, CSRF, WebSocket, Cookie-theft and Content-Security-Policy sheets are all directly on jZen's path. |

**Beyond OWASP — the 2026 practices to check explicitly**, because ASVS covers the application and
not the pipeline that produces it: build provenance (**SLSA**), a generated **SBOM** (CycloneDX or
SPDX) and whether one is produced at all, container image signing, keyless CI→cloud authentication
(workload identity federation vs a long-lived service-account key), dependency pinning by digest,
secret scanning with push protection, cookie prefixes (`__Host-`), `Permissions-Policy` / COOP /
COEP / CORP, CSP with nonces or Trusted Types rather than a source allowlist, and whether the
email-link authentication flow (ADR-018) is defensible under current OAuth 2.1 guidance.

### 2.3 The level is set: ASVS **Level 2**

ASVS levels exist so that a review states its bar rather than implying one. jZen handles
authentication credentials, personal data (email addresses) and an admin role, so **the bar for this
review is Level 2** — decided by the owner on 2026-08-13, not a default for the reviewer to weigh.
The report states it in its Method block.

Two consequences follow. Where a Level 3 requirement is obviously cheap, note it as an *opportunity*
and rank it as such — it is not a gap. Where a **Level 2** requirement is knowingly declined, that is
a finding with an owner decision attached, never a silent omission.

**Coverage is a deliverable.** The report carries an ASVS mapping table — every chapter, marked
`pass` / `gap` / `n/a with reason` / `not assessed`. "Not assessed" is an honest and acceptable
entry; an unmarked chapter is not.

---

## 3. Preconditions

| # | Precondition | Check | If absent |
|---|---|---|---|
| 3.1 | Toolchain at the pinned versions | `task doctor` | Do not proceed on a red doctor. A different Flutter produces a different web bundle, and the bundle is Phase 7's subject. |
| 3.2 | Docker running | `docker info` | Phases 4, 5 and 8 all need `@QuarkusTest` Dev Services and the local smoke container. |
| 3.3 | The repository is green *before* the review | `task test` once, recorded | A pre-existing red suite makes every later "this test proves the control" claim unusable. |
| 3.4 | `task audit` runs and its result is recorded | `task audit` | Needs network. Its output is a **Phase 6 input**, not a finding of this review — ADR-034 already owns that gate. |
| 3.5 | `gcloud` authenticated, read-only discipline understood | `gcloud auth list` | Credentials are full read/write (see the performance plan §1.1); the ROE in §4 is discipline, not a permission boundary. |
| 3.6 | Local Supabase stack can start and stop | `task run:supabase` / `task stop:supabase` | Phase 5 needs GoTrue and the Data API locally. |
| 3.7 | Supabase Data API probe — **settled: do not probe the hosted project** (§4.4) | — | Verify ADR-036's lockdown locally. No owner round-trip needed; the decision is made. |

Nothing outside the repository is modified (CLAUDE.md "Working discipline"). Scratch output —
request logs, header dumps, scanner reports — goes to the session scratchpad; only
`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md` is created.

---

## 4. Rules of engagement

### 4.1 Forbidden, without exception

```
task destroy:cloudrun          # deletes the GCP project AND the Supabase project
task deploy:cloudrun           # deploy is a manual human act in this repository
gcloud run services update / deploy / gcloud secrets *   # any mutation of the live service
zap / nuclei / nikto / sqlmap / ffuf / gobuster          # against production, at any intensity
hydra / patator / any credential or token guessing       # against production or the hosted Supabase
```

### 4.2 Active scanning of production is indistinguishable from the attack the system defends against

This is the rule most likely to be broken by habit, so it gets its own paragraph. The deployed
service runs at `--max-instances=1` with 200 concurrency slots (ADR-027, ADR-028). A directory
brute-forcer or an ASVS-driven fuzz run against it is **a denial of service**, not a test — that
residual risk is *accepted in writing* precisely because nobody is supposed to spend it. Worse, it
would be laundered through the exact machinery under review: `RateLimitFilter` would rate-limit the
reviewer, `DurableLimiter` would write thousands of rows to `zen_rate_limit_counters`, and the
resulting production data would then be indistinguishable from a real attack in any later
investigation.

**All dynamic testing happens against a local container** (Phase 8). Production gets reads only.

### 4.3 The production request budget: **12**

| Reserved for | Requests |
|---|---|
| Response security headers on an API path, the SPA root `/`, and `/admin/` (§7 Phase 7) | 3 |
| Cookie attributes on an unauthenticated response — `Secure`, `HttpOnly`, `SameSite`, prefix | 1 |
| CORS preflight behaviour from a disallowed origin (one `OPTIONS`) | 1 |
| `/openapi`, `/q/swagger-ui/`, `/q/dev/`, `/q/health` reachability in prod | 4 |
| `/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association` | 2 |
| Spare | 1 |

**Every request goes in a ledger table in the report** — method, path, purpose, response code, and
whether the container was cold. No `POST` to production. Note that `verify:deploy` includes a
`POST /api/v1/auth/restore-password`, which writes a rate-limit row; the performance plan's §3.3
analysis applies unchanged, and the default is the same: **skip it**.

Control-plane reads (`gcloud run services describe`, `gcloud secrets list` — names and metadata
only, never `versions access`, `gcloud logging read`, IAM policy reads) cost **no** request budget
and wake no container. Prefer them for everything they can answer.

### 4.4 The hosted Supabase project

ADR-036 records that every table jZen creates is exposed to the Supabase Data API until two
independent layers say otherwise, and `R__identity_data_api_lockdown.sql` is the response. Verifying
that lockdown *on the hosted project* means presenting the anon key to a third-party endpoint and
reading the result — defensible, but it is a probe of live infrastructure with a credential. **The
owner decided on 2026-08-13 that it does not happen.** The hosted project is not probed, with the
anon key or any other.

**Verify locally instead**, against `task run:supabase` — it runs the same PostgREST against the same
migrations, so it answers the architectural question (does the lockdown cover *every* table, and what
is the default for a new one?) without touching live infrastructure. Then write the hosted check into
the report's "Open questions" as the exact command a human should run, and stop there. If the local
verification finds the lockdown incomplete, that raises the value of the hosted check but does not
authorise it — report it and let the owner decide.

### 4.5 Locally, anything goes

Build it, boot it, scan it, fuzz it, drop the database. The local stack is the instrument.

---

## 5. Method traps

Five ways this review produces confident, wrong output.

### 5.1 A control that is present in `zen_demo` is not thereby present in jZen

The single easiest mistake available here. `SecurityHeadersTest`, `CsrfWiringTest`,
`RateLimitWiringTest`, `DatabasePrivilegeTest` and friends all live in
`apps/zen_demo/zen_demo_server` — necessarily, since a `@QuarkusTest` needs an assembled app
(CLAUDE.md). A green test therefore proves *this application* receives the control. It proves
nothing about the **next** application, and the difference is exactly the review's subject.

For every control, answer three questions and put all three in the table: **where the code lives**,
**where the test lives**, and **what a new app must do to receive it**. If the answer to the third
is "add a dependency and remember a Maven plugin", that is a finding regardless of how green the
suite is.

### 5.2 A passing test can be a test of the wrong layer

`@QuarkusTest` runs in JVM mode against an in-process server. Several of jZen's security properties
live *below* JAX-RS and are environment-sensitive:

- security headers are on the **Vert.x router**, not a JAX-RS filter (ADR-035) — so they cover the
  static handler serving `/` and `/admin/`, which is the part that most needs them, and a JAX-RS-level
  test would not notice if that stopped being true;
- `ZenTransportFilter` is `@PreMatching`, so it runs **before** resource matching and, with
  `quarkus.http.auth.proactive=true`, in a defined order relative to authentication that a unit test
  does not pin;
- native-image behaviour differs from JVM behaviour in ways that are silent (the performance plan's
  §4.4 documents `quarkus.log.min-level` being build-time fixed as one example).

**Confirm the layer, not only the outcome**: for headers and cookies, read the wire (`curl -sI`)
against `task test:native`'s container, not only the assertion.

### 5.3 Reading STANDARDS is not reviewing the system

`STANDARDS.md` is 616 lines of well-argued rules and it is genuinely good. It is also the *claim*
under review. Every architectural invariant this review relies on gets verified against code or
against a run — and where a document and the system disagree, **that is the finding**, and it is
usually a better one than either half alone. The precedent is in the predecessor's §6: STANDARDS
attributed the validity of in-process state to `--max-instances=1` when the actual constraint is
`--min-instances=0`, and that correction was worth more than several code changes.

### 5.4 An ADR is a decision, not an exemption

ADR-018 (implicit fragment flow, explicitly not PKCE), ADR-031 (RLS is Supabase-side only),
ADR-035 (HSTS stops short of `includeSubDomains` and `preload`), ADR-027 (the 200-slot residual is
accepted) and ADR-030 (an unverifiable session cookie means anonymous) are all *reasoned* positions
with the reasoning written down. That does not make them correct in 2026, and it does not exempt
them from review.

The rule: **re-examine the decision against its own stated reasoning and against current guidance,
then either confirm it with a number or challenge the premise explicitly.** What is not acceptable
is either extreme — treating an ADR as settled and skipping it, or "finding" it as though the
reasoning did not exist. If a decision should change, the review says so and names the ADR that a
successor would have to supersede. `DECISIONS.md` is append-only (ADR-011); this review writes no
entry to it.

### 5.5 Severity inflation destroys the report

Twenty MEDIUMs is a report nobody acts on. Keep the predecessor's ranking —
`(active exploitability × impact) / remediation cost` — and rank hard. CVSS 4.0 vectors are
*optional* and, if used, sit alongside that ranking rather than replacing it: a CVSS base score
knows nothing about `--max-instances=1`, about a single-tenant deployment, or about which control
is inherited by future apps, and those are the facts that actually order this list.

---

## 6. The phases

Ten phases. Phase 2 is the centrepiece; if time runs short, cut breadth elsewhere and not there.

### Phase 0 — Orientation and scope freeze (~2 h)

1. Read, in order: `CLAUDE.md`; `MANIFESTO.md`; `BLUEPRINT.md`; `STANDARDS.md` whole (it is 616
   lines and every section has a security consequence); then `DECISIONS.md` ADR-038, 037, 036, 035,
   034, 033, 031, 030, 029, 028, 027, 026, 019, 018, 017, 008, 005.
2. Read `implemented/SECURITY-REMEDIATION.md` and `implemented/DATA-API-EXPOSURE.md` in full — to
   know what **not** to re-find, and to inherit the closed list.
3. Fetch and record the standards versions (§2.1). This is a gate: no requirement is cited before
   its document version is in the report.
4. Write the scope statement: in-scope surfaces, out-of-scope surfaces, ASVS level, and the date.

**Done when** the report's Method block is written and the standards-version table is complete.

---

### Phase 1 — Assets, trust boundaries, and a threat model (~3 h)

No tool. One diagram and two tables, and everything after this hangs off them.

**Assets, ranked.** Candidates, to be confirmed rather than inherited: Supabase JWT signing
authority; the `zen_access_token` cookie; the refresh token (server-held and client-held); the
`ZEN_JOBS_TRIGGER_TOKEN`; the application and DDL database credentials; the `users` table (email +
role); the admin role itself; the Artifact Registry push credential; the GCP project.

**Trust boundaries.** At minimum these nine, each with what crosses it, what authenticates the
crossing, and what happens when authentication fails:

| # | Boundary | Note |
|---|---|---|
| B1 | Browser / mobile app → Cloud Run | The only boundary a client is permitted to cross (STANDARDS "The client talks to one server") |
| B2 | Cloud Run → Supabase GoTrue | Outbound, over `quarkus-rest-client-jackson`; the one sanctioned Jackson usage |
| B3 | Cloud Run → Postgres, via the session pooler, **cross-region** | Application role since ADR-031; DDL role separate |
| B4 | Cloud Scheduler → `POST /api/v1/jobs/trigger` | Constant-time secret; the highest-consequence endpoint (it anonymises accounts) |
| B5 | **Internet → Supabase Data API → the same Postgres** | The boundary that bypasses the application entirely — ADR-036 |
| B6 | Email link → browser → the app | ADR-018/019: an account-takeover primitive by construction |
| B7 | GitHub Actions → the repository, and the developer laptop → GCP | Never reviewed |
| B8 | Framework library → application | jZen's own, and the one no OWASP document names (§1) |
| B9 | Admin panel → `/api/v1/admin/*` | Same origin, JSON-only, `Content-Range` pagination |

**Threat model.** STRIDE per boundary is enough structure; do not over-formalise. For each boundary,
name the one or two threats that are *live* given the deployment (single instance, no edge,
same-origin SPA, one tenant) and mark the rest out of scope with a reason. **A threat model that
lists everything ranks nothing.**

**Deliverable:** one boundary diagram (ASCII or Mermaid, in the report), the asset table, and the
per-boundary threat table.

---

### Phase 2 — The inheritance audit and the silent-no-op census (~4 h) ⟵ *the centrepiece*

**Part A — the control inventory.** Every security control in the system, one row each:

| Control | Where the code lives | Where the test lives | Inherited by a new app? | Fails open or closed if absent? | Silent? |
|---|---|---|---|---|---|

Populate it from the modules, not from the docs: `zen-transport` (`SecurityHeaders`,
`ZenTransportFilter`, `CorsCredentialsGuard`, `StaticCacheHeaders`, both proto and proto-JSON
readers/writers), `zen-identity` (`CsrfFilter`, `CsrfRules`, `RedirectTargets`, `RoleAugmentor`,
`SessionCookieAuthenticationMechanism`, `UserRoleLoader`, `SessionService`, `AuthResource`,
`AdminUserResource`, `UserRetentionService`), `zen-ratelimit` (all of it), `zen-jobs`
(`JobTriggerAuthenticator`), the Flyway migrations, and the `apps/zen_demo` side that has no
framework home.

**The column that matters is "inherited".** Anything a new application must *remember* to do is a
framework defect expressed as documentation. Rank those by what happens if it is forgotten.

**Part B — the silent-no-op census.** Enumerate every mechanism in jZen where a missing or wrong
declaration produces **no error and no signal**. Three are known (§1). Find the rest. Concretely:

```
# Does every library module that contributes CDI beans or JAX-RS providers run jandex?
for m in server/zen-*; do
  printf '%-24s beans:%s jandex:%s\n' "$m" \
    "$(grep -rlE '@Provider|@ApplicationScoped|@Singleton|@Observes' $m/src/main/java 2>/dev/null | wc -l)" \
    "$(grep -c jandex-maven-plugin $m/pom.xml 2>/dev/null)"
done

# What does a library drag in transitively that an app never asked for?
# (ADR-034's Wave 4.2 found libraries handing every app quarkus-smallrye-openapi this way.)
server/mvnw -B -f apps/zen_demo/zen_demo_server/pom.xml dependency:tree
```

Then the harder question, which no command answers: **what would it take to write a jZen application
that is insecure while every gate stays green?** Attempt it on paper. An app that skips
`SecurityHeaders`, or registers its own `MessageBodyWriter`, or adds `quarkus-rest-jackson` for one
endpoint, or defines a resource that bypasses `RateLimitFilter`, or creates a table without the Data
API lockdown. For each: does anything stop it, and does anything *tell* anyone?

**Part C — audit the gates themselves.** `verify:boundaries`, `verify:docs`, `sync:contracts`,
`audit`, `test:e2e`. For each: what exactly does it check, what does it *not* check that its name
implies, and can it be made to pass without checking anything? The precedent is in ADR-034 —
`ossindex-maven-plugin` reported BUILD SUCCESS having checked nothing, and that was found by
someone deliberately looking. `scripts/verify-boundaries.py` gained `.ts`/`.tsx` coverage in Wave
3.3; verify it also covers Kotlin/Swift platform channels, `pubspec.yaml` dependency declarations,
and generated code.

**Deliverable:** the control inventory, the silent-no-op census, and a gate-coverage table.

---

### Phase 3 — Identity, session, authorization (~4 h)

ASVS authentication / session-management / access-control chapters, plus API Top 10 BOLA and BFLA.

| Question | Where to look |
|---|---|
| Cookie attributes, end to end | `SessionService`, and the wire. `__Host-` prefix considered? `SameSite` value and its consequence for the email-link return (B6)? |
| Token lifetimes, rotation, revocation | Refresh-token rotation and the upstream `logout` added in Wave 2.1 — confirm revocation actually reaches GoTrue and that a failure surfaces (STANDARDS "Failures surface") |
| JWT verification | ES256 against JWKS; algorithm confusion, `none`, key-ID substitution, JWKS fetch failure mode, cache poisoning, clock skew. **What happens when JWKS is unreachable — does it fail closed?** |
| Role resolution | `RoleAugmentor` + `UserRoleLoader`: role from the `users` table, never the JWT. Confirm the failure path still returns an identity *without* a role. What about a role changed mid-session — is there any revocation latency, and is it bounded? |
| **BOLA** | Every endpoint taking an identifier from the client. `AdminUserResource` first, then `DemoResource`, then the WebSocket. Does authorization compare against the *authenticated subject* or against a client-supplied id? |
| **BFLA** | `@RolesAllowed` coverage: is any mutating endpoint unannotated? With `proactive=true`, what does an unannotated endpoint actually permit? Enumerate, don't sample. |
| CSRF | `CsrfRules`' exemption list. Login/register are exempt by necessity — is the list closed, and does a new endpoint default to protected or to exempt? *Defaults are the architectural question.* |
| Open redirect | `RedirectTargets` (exact match only) — re-verify against the current allowlist source, since Wave-era reasoning assumed a fixed set |
| **The email-link flow (B6)** | ADR-018/019 under §5.4's rule. Fragment-borne tokens, referrer leakage, link reuse, expiry, single-use enforcement, and what an email-forwarding or link-prefetching intermediary sees. This is the account-takeover primitive; it deserves the most time in this phase. |
| Enumeration and timing | The neutral-202 property is closed (F-era). Check it still holds on the *new* paths added since — password set, admin user create. |

---

### Phase 4 — The transport seam and the two parsers (~3 h)

jZen's core mechanism is also its most unusual attack surface, and no OWASP list covers it directly.

- **Two codecs mean two parsers.** Protobuf and canonical proto3 JSON, both reachable from an
  unauthenticated request via a client-controlled header. Establish: message size limits on each
  path, recursion/nesting depth, unknown-field handling, `Any`/`oneof` usage, and what a malformed
  body produces (a `ZenError`, per CLAUDE.md — verify it is not a stack trace).
- **`@PreMatching` ordering.** `ZenTransportFilter` rewrites `Accept`/`Content-Type` before
  matching. Establish its order relative to authentication and to `RateLimitFilter`, and whether a
  request can be made to do parser work before any limit applies.
- **Header-driven dispatch.** Can `X-Zen-Transport` reach a code path the resource did not intend?
  Can content-type sniffing be steered into it?
- **The WebSocket** (`/api/v1/demo/ws`). Wave 1.4 added a frame-size limit, connection cap and
  authenticated handshake. Review it as an architecture: origin checking on the handshake,
  authorization *after* upgrade (the cookie is checked once — what happens on logout or role change
  mid-connection?), per-connection rate limiting, and whether the cap is per-instance (it is —
  `--max-instances=1` makes that valid *today*, per ADR-027/029; say what breaks if that changes).
- **The OpenAPI surface.** Wave 4.2 removed it from prod at the library level. Verify from the wire
  (§4.3's budget) and confirm no library reintroduced `quarkus-smallrye-openapi` transitively — that
  is a regression one `pom.xml` edit away, and the last one was invisible.
- **The Jackson prohibition.** Confirm `quarkus-rest-jackson` is still absent server-side and that
  the only Jackson is the outbound client in `zen-identity`. Note whether anything *detects* its
  reintroduction, or whether it is a rule held by memory.

---

### Phase 5 — Data plane, privileges, and privacy (~3 h)

- **The privilege split** (ADR-031, ADR-037, ADR-038). Application role vs DDL role: enumerate the
  actual grants against a local database and confirm the application role cannot read `auth`, cannot
  DDL, and cannot escalate via a `SECURITY DEFINER` function or a default-privileges quirk. Confirm
  the cutover happens on deploy (ADR-037) and cannot be skipped.
- **RLS scope** (ADR-031: Supabase-side only). Re-read the decision under §5.4. State plainly, in
  the report, which queries RLS does and does not protect — the predecessor's F5 found the migration
  created the *appearance* of a second line the application path did not receive, and the current
  answer should be legible to someone who did not read the ADR.
- **The Data API boundary (B5)** — ADR-036 and `R__identity_data_api_lockdown.sql`. Two independent
  layers, per the ADR: verify both, locally, and verify the **default for a new table**. A repeatable
  migration is a good mechanism precisely because it re-asserts on every deploy; confirm it actually
  covers tables added later (`zen_rate_limit_counters`, `zen_jobs`) and not only `users`.
- **Injection**, briefly. The predecessor verified named parameters and a `SORTABLE` whitelist. Check
  only what is *new* since: the rate-limit `INSERT … ON CONFLICT`, the jobs tables, retention
  batching. Do not re-audit closed ground.
- **Privacy and data lifecycle.** Retention and anonymisation (`UserRetentionService`, ADR-008), the
  no-erasure-without-delivered-warning property, PII in logs (Wave 0.5 replaced emails with ids —
  verify no new site reintroduced them, including exception messages and the Vert.x access log), and
  data in Artifact Registry images or in `openapi.json`. Frame as a data-protection section; do not
  attempt a legal assessment.
- **Secrets.** 17 GCP secrets injected as env vars per instance start. Check: none committed, none
  in the client bundle (Phase 7), rotation story, whether a secret's *value* ever reaches a log or an
  error response, and what a compromised Artifact Registry or GitHub Actions token would reach.

---

### Phase 6 — Supply chain and build integrity (~3 h)

The surface with the least prior coverage. OWASP CI/CD Top 10 as the checklist.

```
# Are actions pinned to a commit SHA, or to a mutable tag?
grep -n 'uses:' .github/workflows/ci.yml

# Does the workflow declare least-privilege token permissions at all?
grep -n 'permissions:' .github/workflows/ci.yml

# What is in the shipped image, and what runs as what?
cat apps/zen_demo/zen_demo_server/src/main/docker/Dockerfile.native-micro
```

Questions to answer, each with evidence:

- **Is `task audit` run anywhere automatically?** ADR-034 says it "is run in CI on a schedule and
  before a release" — establish whether that is implemented or aspirational. A gate that exists and
  is never triggered is the same as no gate, and this one has already caught a HIGH once.
- **Workflow token permissions**, and what a malicious PR from a fork can reach.
- **Action pinning** by tag vs digest; third-party actions (`subosito/flutter-action`,
  `arduino/setup-*`) and what each is trusted with.
- **How does the deploy authenticate to GCP** — a long-lived service-account key, or workload
  identity federation? If a key exists, where does it live and who can read it?
- **Base image pinned by digest** (the predecessor confirmed this; re-verify) and non-root `USER
  1001` (same). **New:** is there an SBOM? Is the image signed? Is there any provenance attestation?
  Answer "no" plainly if it is no — SLSA level 0 stated honestly is a useful finding.
- **`dart pub global activate protoc_plugin`, `corepack`, and the `mvnw`/wrapper scripts** — every
  point where CI executes code fetched at build time without a checksum.
- **Secret scanning / push protection** on the repository, and whether any credential is committed
  (the predecessor noted dev/test trigger tokens scoped to non-shipping profiles — confirm the
  scoping still holds).
- **Artifact Registry**: who can push, and are old images (51 at last count) a liability or just
  storage?

---

### Phase 7 — The client and the browser surface (~3 h)

- **Compile-time config is load-bearing** (STANDARDS, non-negotiable) and it means **anything
  configured is in the bundle**. Grep the built web bundle for every `String.fromEnvironment` name
  and for anything resembling a key. `SUPABASE_KEY` must not be there — verify, do not assume:

```
task build:web
R=apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources
grep -rIl --binary-files=text -e 'supabase' -e 'eyJ' -e 'service_role' $R | head
```

- **The one-server rule (B1)** from the client's side: confirm `verify:boundaries` catches what it
  claims, then look for what it cannot — a platform channel, a plugin with its own network stack, a
  WebView, an `HttpOverrides`, a `badCertificateCallback`.
- **Token storage** against MASVS-STORAGE: refresh token in Keychain/Keystore with
  `first_unlock_this_device`, access token in memory. **On web there is no Keychain** — establish
  what `zen_secure_store` does on the web target and whether the security property claimed for
  mobile is silently absent there (a §5.1-shaped question, on the client side).
- **Security headers, from the wire, in a real browser.** CSP (ADR-035 self-hosts the renderer so
  `script-src` stays `'self'` — verify, including for `/admin/`, which react-admin may have
  loosened), HSTS and the two additions ADR-035 deliberately stopped short of, plus
  `Permissions-Policy`, COOP/COEP/CORP, `X-Content-Type-Options`, `Referrer-Policy`. Check the
  browser console for CSP violations on a real page load — a CSP that reports violations nobody
  reads is a CSP heading for a `'unsafe-inline'` patch.
- **The admin panel.** It always speaks `X-Zen-Transport: json` and holds the highest privilege in
  the system. Auth provider, where its session lives, XSS surface in react-admin, and whether its
  bundle is served with the same headers as the app's.
- **Deep links and App Links** (`WellKnownResource`, ADR-019). Link hijacking by another installed
  app, and what a failed verification means — both platforms cache it.

---

### Phase 8 — Local dynamic verification (~3 h)

The only phase that runs a scanner, and it never points at production (§4.2).

```
task test:native          # builds the shipping image and boots it in Docker
```

Against that container, and against `task run:demo`:

- an **OWASP ZAP baseline scan** (passive) for header and cookie findings, as a *cross-check* on
  Phase 7's manual reading — treat disagreements as interesting;
- authenticated manual probes for the Phase 3 access-control questions: the same request with no
  cookie, an expired cookie, a valid cookie with the `user` role against an admin path, and a
  tampered cookie. `ExpiredSessionCookieTest` and ADR-030 say what *should* happen; confirm on the
  wire;
- oversized and malformed bodies on both codec paths (Phase 4);
- rate-limit behaviour: confirm the limiter keys on a resolved client address that
  `X-Forwarded-For` cannot spoof (Wave 1.2 addressed this — verify it against the shipping image,
  since the proxy chain differs between JVM test and container);
- the jobs trigger with a wrong token, no token, and a token of the wrong length (constant-time
  comparison).

Record every scanner's name, version and configuration. **An unlabelled tool output is not
evidence.**

---

### Phase 9 — Rank, write, clean up (~3 h)

§7 and §8 below, then:

```
task stop:supabase
docker ps -a                     # nothing from this review
git status --porcelain           # ONLY docs/plans/SECURITY-ARCHITECTURE-REVIEW.md
```

If Phase 7 rebuilt the web bundle, leave it in a state where `task test:native` still passes.

---

## 7. What a finding must contain

```
### F<n> — <one-line claim, stated as the defect, not the fix>

**Class:** architectural | implementation | process | supply-chain
**Scope:** framework (every app inherits it) | application (zen_demo only) | pipeline
**Confidence:** verified | reasoned-from-code | unverified
**Standard:** <ASVS requirement id + version, and/or the API/MASVS/CI-CD item. "None" is allowed —
              a real finding that no list names is worth more than a mapped one that is not.>
**Boundary:** <B1–B9 from Phase 1>
**Where:** <file:line, module, or the deployed resource>
**Evidence:** <the command or the code path, and what it produced. Not a citation of a doc.>
**Exploitability today:** <given single-instance, same-origin, one-tenant, no-edge — be concrete>
**Impact:** <what the attacker gets>
**Silent?** <does anything detect or report this today — a test, a gate, a log line? yes/no>
**Fix:** <the specific change, and where it must live to be inherited>
**What the fix costs:** <what gets worse, or which invariant is touched — "nothing" only if you looked>
**Invariant touched:** <§7.1, or "none">
**ADR consequence:** <the ADR a fix would supersede, or "none">
```

**Ranking:** `(active exploitability × impact) / remediation cost`, as the predecessor. Then a
tie-break that is specific to this review: **a framework-scope finding outranks an
application-scope finding of equal severity**, because the framework one is latent in every app that
does not exist yet.

**Four groups, labelled:** **Architectural** (the shape is wrong — the review's reason for existing)
· **Free wins** (no invariant touched) · **Priced trade-offs** (an invariant is touched; present the
cost and let the owner decide) · **Closed** (verified correct as built, *with the evidence* —
including the F1–F20 confirmations, one line each).

### 7.1 The invariants, as a pre-submission checklist

A recommendation that violates one of these is rejected on arrival unless it engages with the
document that established it and prices the change.

1. The client talks to exactly one server, and it is jZen's.
2. Client config is compile-time. "Fetch config at startup" is not available.
3. The web app is served same-origin with the API.
4. Nothing sits between the client and Cloud Run — no CDN, no WAF, no API gateway. ADR-027 priced
   Cloud Armor (~$25–30/mo floor, rejected) and deferred Cloudflare free tier **on invariants, not
   price**: two written constraints depend on there being no edge. Recommending one means paying
   ADR-027's argument, not repeating the suggestion it already rejected.
5. `--max-instances=1` makes in-process state correct; `--min-instances=0` makes in-process *time*
   invalid.
6. Flyway is the single migration authority; a new table ships its Data API lockdown in the same
   change (ADR-036).
7. One orchestrator: `task` triggers native tools and never reimplements them (ADR-014, ADR-032).
8. No gate swallows a failure; no gate can pass having checked nothing (ADR-034).
9. Generated files are never hand-edited (`sync:contracts` enforces it).
10. jZen is proto-first; no server-side `quarkus-rest-jackson`.

---

## 8. Deliverable skeleton

`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md`:

```
# The architectural security review

A working document, not a source of truth. The architecture docs in ../architecture/ remain
authoritative.

**Reviewed:** <date>
**Scope:** <in and out>
**Standard:** <ASVS version + level, and every other artifact with its version and date read>
**Method:** static review / local dynamic testing / production reads
           — the production request ledger (§4.3)
           — every tool with its name, version and configuration
           — what was NOT assessed, said plainly

## 1. Summary — the ranked list, one line each, with scope and class
## 2. Trust boundaries and the threat model      (Phase 1)
## 3. Architectural findings                     (the framework/inheritance findings — Phase 2)
## 4. Free wins
## 5. Priced trade-offs
## 6. Closed — verified correct, with evidence (incl. the F1–F20 confirmations)
## 7. ASVS coverage map — every chapter: pass / gap / n/a with reason / not assessed
## 8. Open questions — each with the exact command a human should run
## 9. Appendix — the control inventory, the silent-no-op census, the gate-coverage table
```

Rank hard; cut anything without evidence. **Fifteen findings with mechanisms beat sixty with
severities.**

**No ADR.** `DECISIONS.md` is an append-only archive of *accepted* decisions and a review accepts
nothing on its own (ADR-011). Where a finding implies a decision, name the ADR it would supersede
and stop there; if the owner then decides, record it with the `add-adr` skill.

**No code changes**, including obvious ones. A one-line fix stated clearly in the report is worth
more than a commit that arrives mixed into a review.

---

## 9. Effort and ordering

| Phase | Wall time | Attention | Blocks |
|---|---|---|---|
| 0 Orientation + standards versions | ~2 h | high | everything |
| 1 Assets, boundaries, threat model | ~3 h | high | 3–7 |
| 2 **Inheritance + silent-no-op census** | ~4 h | **highest** | — |
| 3 Identity, session, authorization | ~4 h | high | 8 |
| 4 Transport seam and parsers | ~3 h | high | 8 |
| 5 Data plane, privileges, privacy | ~3 h | high | — |
| 6 Supply chain and build integrity | ~3 h | medium | — |
| 7 Client and browser surface | ~3 h | high | 8 |
| 8 Local dynamic verification | ~3 h | medium | needs 3, 4, 7 |
| 9 Rank, write, clean up | ~3 h | high | needs all |

Roughly **four focused days**. Start `task test`, `task audit` and `task test:native` early — they
are slow and unattended, and Phase 8 needs the native image. Phase 6 is independent of everything
and is good work to interleave while builds run. Phase 2 needs an unbroken block; do not fragment it.

---

## 10. Stop conditions

Stop and ask rather than improvise if:

- **A live, exploitable vulnerability is found.** Stop reviewing, write it up immediately, and tell
  the owner before continuing. Do not sit on it until Phase 9, and do not "confirm" it with an
  exploit against production.
- A production read returns something unexpected — a 5xx, an unfamiliar revision or hostname, an
  endpoint that should not exist. Do not probe to understand it.
- The request ledger reaches 12. Raising it is the owner's call, in writing, in the report.
- Any test requires writing to production, the hosted Supabase project, or a secret.
- A finding appears to require editing a tracked file to demonstrate. It does not; if it seems to,
  that is a finding about testability, not a licence to edit.
- Credentials are discovered in the repository or in a log. Stop, report, do not use them, do not
  paste them into the report.

---

## 11. What is still open

| # | Question | Default if unanswered |
|---|---|---|
| Q1 | Current versions of ASVS / API Top 10 / MASVS / CI-CD Top 10 (§2.1) | Blocking for citations. Fetch them; do not cite from memory. |
| ~~Q2~~ | ~~ASVS level~~ — **decided 2026-08-13: Level 2** (§2.3) | Not open. State it in the Method block; note L3 items as opportunities, not gaps. |
| ~~Q3~~ | ~~Hosted Supabase Data API probe~~ — **decided 2026-08-13: no** (§4.4) | Not open. Verify locally; record the hosted check as a command for a human, not as work you do. |
| Q4 | Is `task audit` wired into CI or a schedule anywhere? | Establish in Phase 6. If not, that is a finding, not an assumption. |
| Q5 | Does a second jZen application exist or is one imminent? (ADR-026) | Assume yes — it is what makes framework-scope findings urgent rather than theoretical. |
| Q6 | Is a formal threat-modelling notation wanted, or is the §Phase-1 table enough? | The table. Notation is not the deliverable. |
| Q7 | Is a penetration test — active, authorised, against a dedicated deployment — wanted after this? | Out of scope here. Name it as a recommendation if the review's residual justifies it. |

---

## 12. What would make this review worthless

- **Re-finding F1–F20.** They are closed and the closures are documented. Confirming one is a line
  in §6 of the report, not a finding.
- **Restating `STANDARDS.md`, `BLUEPRINT.md` or an ADR as though it were a discovery.** The
  discovery is where the document and the system disagree.
- **A generic OWASP checklist with jZen's file names pasted in.** If a finding would read the same
  against any Quarkus application, it is not this review's output. The framework/application seam,
  the dual-codec parser surface, the silent-no-op class, the Data API's second door, and the
  no-edge deployment are what make jZen's security posture jZen's — that is where the value is.
- **Severity without a mechanism.** "HIGH: insufficient input validation" is noise. Name the input,
  the path, and what reaches the other end.
- **Recommending a WAF, an API gateway, a CDN, an edge, Redis, Kubernetes, or a second orchestrator**
  without engaging with the ADR that already rejected or deferred it and the price it named.
- **Touching production with anything other than a read**, or pointing a scanner at a service whose
  documented capacity ceiling is 200 concurrent requests on one instance.
- **A long report.**
