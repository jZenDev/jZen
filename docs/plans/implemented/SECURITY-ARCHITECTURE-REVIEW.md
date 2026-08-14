# The architectural security review

A working document, not a source of truth. The architecture docs in
[`../architecture/`](../architecture/) remain authoritative, and ADRs win on conflict.

**Reviewed:** 2026-08-13
**Method plan:** [`SECURITY-ARCHITECTURE-REVIEW-PLAN.md`](./SECURITY-ARCHITECTURE-REVIEW-PLAN.md)
**Predecessor:** [`implemented/SECURITY-REMEDIATION.md`](implemented/SECURITY-REMEDIATION.md) (2026-08-03,
F1–F20, all closed). This review is not a re-run of it; §6 carries the confirmations.

---

## Method

### Scope

**In scope.** jZen *as a framework*: what an application inherits from `server/zen-*` and
`client/zen_*`, and what it must remember to do for itself. The dual-codec transport seam, the
identity/session/authorization path, the data plane and its two doors, the build pipeline, the
Flutter and admin clients, and the deployed Cloud Run service's configuration.

**Out of scope.** Penetration testing. Active scanning of any deployed service. The hosted Supabase
project (owner decision, 2026-08-13 — plan §4.4). Legal/regulatory assessment of the retention
design. Cryptographic review of Supabase's own token minting.

**Standard: OWASP ASVS 5.0.0, Level 2.** Level set by the owner on 2026-08-13, not chosen here.
A Level 3 requirement that is cheap is reported as an *opportunity*, not a gap.

### Artifacts, with versions established rather than recalled

| Artifact | Version | Released | URL | Read |
|---|---|---|---|---|
| OWASP ASVS | **5.0.0** | 2025-05-30 | `owasp.org/www-project-application-security-verification-standard/` | 2026-08-13 |
| ASVS 5.0.0 chapter list | V1–V16 | — | `raw.githubusercontent.com/OWASP/ASVS/master/5.0/docs_en/…_5.0.0_en.csv` | 2026-08-13 |
| OWASP API Security Top 10 | **2023** | 2023 | `owasp.org/API-Security/editions/2023/en/0x11-t10/` | 2026-08-13 |
| OWASP MASVS | current (version not stated on the page; control groups confirmed) | — | `mas.owasp.org/MASVS/` | 2026-08-13 |
| OWASP Top 10 CI/CD Security Risks | **1.0** | 2022-10 | `owasp.org/www-project-top-10-ci-cd-security-risks/` | 2026-08-13 |

**Citation discipline.** Every requirement id below was looked up in the document named above. Where
no list names a finding, the **Standard** field says `none` — the plan is explicit that a real
finding no list covers is worth more than a mapped one that is not. MASVS is cited by control group
(`MASVS-STORAGE`) rather than by numbered control, because the page read did not establish the
version those numbers belong to.

### Tools, with versions and configuration

| Tool | Version | Configuration |
|---|---|---|
| `task` (go-task) | per `task doctor` | `audit`, `test`, `build:web`, `doctor` |
| Java / Quarkus | JDK 25.0.2 / Quarkus 3.38.0 | `%dev` and `%prod` profiles, both run locally |
| Flutter / Dart | 3.44.2 / 3.12.2 | `task build:web` (dart2wasm), `WEB_API_URL=https://review.invalid` |
| Docker | 29.7.2 | throwaway `postgres:17-alpine` on :55432, removed after |
| `curl` | system | `-D-` header reads; **no `POST` to production** |
| `gcloud` | 580.0.0 | control-plane **reads only**; no `update`, no `deploy`, no `secrets versions access` |
| `gh` | system | repository settings reads |

**No scanner was pointed at any deployed service.** No ZAP/nuclei/nikto/ffuf run at all — see
"What was not assessed".

### Dynamic testing, and where it ran

All dynamic testing ran against **locally built artifacts**: the app in `%dev` and then in `%prod`
profile (`quarkus-run.jar`), each against a throwaway `postgres:17-alpine` container on port 55432
that this review created and destroyed.

**Note on the local stack.** `task run:supabase` was *not* used: a different product
(`bugeater-quarkus`) already owns ports 54321/54322 on this machine with a running Supabase stack.
Displacing it was out of bounds ("work happens inside this repository"), so the backend was pointed
at a private throwaway Postgres instead. The consequence is stated plainly under "What was not
assessed": nothing requiring **GoTrue** or the **local PostgREST Data API** was exercised.

### The production request ledger

Twelve budgeted reads, all `GET`/`OPTIONS`, against
`https://zen-demo-server-tovqpjhspa-lm.a.run.app` (project `jzen-prod`, region `europe-central2`).

| # | Method | Path | Purpose | Status | Cold? |
|---|---|---|---|---|---|
| R1 | GET | `/api/v1/health` | security headers on an API path | 200 | warm (96 ms) |
| R2 | GET | `/` | headers on the SPA root | 200 | warm |
| R3 | GET | `/admin/` | headers on the admin panel | 200 | warm |
| R4 | GET | `/api/v1/auth/identity` | cookie attributes on an unauthenticated response | 204 | warm |
| R5 | OPTIONS | `/api/v1/auth/login` | CORS preflight from `https://evil.example` | **403** | warm |
| R6 | GET | `/openapi` | prod reachability (F15) | **404** | warm |
| R7 | GET | `/q/swagger-ui/` | prod reachability | **404** | warm |
| R8 | GET | `/q/dev/` | prod reachability | **404** | warm |
| R9 | GET | `/q/health` | prod reachability | 200 | warm |
| R10 | GET | `/.well-known/assetlinks.json` | App Links association | 404 | warm |
| R11 | GET | `/.well-known/apple-app-site-association` | Universal Links association | 404 | warm |
| R12 | GET | `/q/health` | body, for information disclosure | 200 | warm |

**Budget: 12 of 12 used. No `POST`. No write of any kind.** `verify:deploy`'s
`POST /api/v1/auth/restore-password` was skipped, per plan §4.3. Control-plane reads
(`gcloud run services describe`, `get-iam-policy`, `projects get-iam-policy`) cost no budget and
woke no container; the container was already warm from the first read onward.

### Preconditions, honestly recorded

| # | Precondition | Result |
|---|---|---|
| 3.1 | `task doctor` green | **No** — reports `DRIFT flutter (want 3.44.2)` while `flutter --version` *is* 3.44.2. The check depends on `fvm`, which is not installed. Recorded as finding **F13**; the toolchain itself is at the pin, so the review proceeded. |
| 3.2 | Docker running | Yes (29.7.2). |
| 3.3 | Repository green before the review | **Not on the first run.** `task test` failed with one error, `WellKnownResourceConfiguredTest.appleAssociation_namesTheTeamQualifiedBundleId` — `FlywaySqlUnableToConnectToDbException` from a Dev Services container during a profile-restart. Re-run in isolation: **passes**. Environmental flake, not a red suite. 155 tests, 1 error, 4 skipped on the failing run. |
| 3.4 | `task audit` result recorded | **Ran, and is RED** — see **F5**. 259 Java dependencies clean; 1 moderate npm advisory. |
| 3.5 | `gcloud` authenticated, read-only discipline | Yes. Active project was `jlogicsoftware`; jZen is `jzen-prod`. |
| 3.6 | Local Supabase can start/stop | **Not exercised** — ports held by another product (see above). |
| 3.7 | No hosted Supabase probe | Honoured. Not probed, with any key. |

### What was NOT assessed

Said plainly, because an unmarked gap is worse than a declared one.

1. **The hosted Supabase project and its Data API.** Owner decision. The exact command a human
   should run is in §8.
2. **The Data API lockdown against a real PostgREST.** `R__identity_data_api_lockdown.sql` was read
   and reasoned about, and observed logging `No anon role (non-Supabase database); there is no Data
   API to lock down` on plain Postgres — i.e. the local run proves the *guard*, not the *lockdown*.
   Blocked by the port conflict above.
3. **Any authenticated request path.** Login requires GoTrue. So: no session cookie was ever minted,
   and **CSRF enforcement, refresh-token rotation, upstream logout revocation, role-change latency,
   the WebSocket after upgrade, and BOLA/BFLA on `/api/v1/admin/*` were not exercised on the wire.**
   They were reviewed from code only, and every such finding is marked `reasoned-from-code`.
4. **The native image.** All dynamic testing used the JVM `quarkus-run.jar` in `%prod` profile, not
   the GraalVM native image that actually ships. `task test:native` was not run (long build; the
   review's remaining budget went to the census). Native-vs-JVM divergence is a known silent class
   (plan §5.2) and is **not** covered here.
5. **No passive or active scanner** was run anywhere, including locally. The ZAP baseline cross-check
   in plan Phase 8 did not happen; §7's header rows rest on manual wire reads only.
6. **The Flutter client on a device.** No MASTG procedure was executed; MASVS findings are static.
7. **Artifact Registry contents and Supabase project settings.** Not enumerated.

---

## 1. Summary — the ranked list

Ranked by `(active exploitability × impact) / remediation cost`, framework scope breaking ties
upward. **Class**: A architectural · I implementation · P process · S supply-chain.

| # | Finding | Class | Scope | Silent? | Rank |
|---|---|---|---|---|---|
| **F1** | The runtime service account holds `roles/editor` on `jzen-prod` | A | pipeline | **yes** | **Critical** |
| **F2** | Authorization has no default-deny: an unannotated endpoint is public | A | framework | **yes** | **High** |
| **F3** | `main` is unprotected; every gate is advisory | P | pipeline | **yes** | **High** |
| **F4** | `SecureTokenStore` has no web guard; the guard lives in the app | A | framework | **yes** | **High** |
| **F5** | `task audit` runs nowhere automatically — and is red today | P | pipeline | **yes** | **High** |
| **F6** | The shipped artifact never passes through CI; SLSA 0 | S | pipeline | **yes** | Medium |
| **F7** | A malformed body on either codec is an unmapped 500, not a `ZenError` | I | framework | partly | Medium |
| **F8** | Framework modules prove their logic but never their wiring | A | framework | **yes** | Medium |
| **F9** | The Jandex and no-Jackson rules are folklore, not gates | A | framework | **yes** | Medium |
| **F10** | The Data API lockdown binds to whichever role last ran it | A | framework | **yes** | Medium |
| **F11** | No `Permissions-Policy`, COOP/COEP/CORP, or CSP reporting | I | framework | **yes** | Low |
| **F12** | Third-party actions pinned by mutable tag; `setup-cli@v1 version: latest` | S | pipeline | **yes** | Low |
| **F13** | `task doctor` reports drift that does not exist | P | pipeline | no | Low |
| **F14** | `/q/health` is public and names its checks | I | application | no | Low |
| **F15** | `X-Zen-Transport` accepts an undocumented `msgpack` alias; the docs describe a rewrite that does not happen | A | framework | **yes** | Low |

**Eleven of fifteen are silent** — nothing today would tell anyone. That ratio is the review's
headline, and it is what plan §1 predicted: jZen's defect class is not "wrong line", it is
"correct once, unenforced thereafter".

---

## 2. Trust boundaries and the threat model

```
                        ┌───────────────────────────────────────────────┐
                        │  B7  GitHub Actions  ·  developer laptop      │
                        │      (CI verifies)      (CI never ships ──┐   │
                        └───────────────────────────────────────────┼───┘
                                                                    │ F6
   Browser / Flutter app                                            ▼
   ┌──────────────┐  B1   ┌──────────────────────────────────┐   Artifact
   │ SPA  /       │──────▶│                                  │   Registry
   │ admin /admin/│  B9   │      Cloud Run (single)          │      │
   └──────────────┘──────▶│   --max-instances=1  conc=200    │◀─────┘
          ▲               │   --allow-unauthenticated        │
          │ B6            │   NO EDGE (ADR-027)              │
      email link          │                                  │
          │               │  ┌────────────────────────────┐  │
   ┌──────┴──────┐        │  │ @PreMatching transport     │  │
   │  GoTrue     │◀───────┤  │ seam → 2 parsers (F7,F15)  │  │
   │  (Supabase) │  B2    │  └────────────────────────────┘  │
   └──────┬──────┘        │  runs as: 807939740716-compute   │
          │               │  which holds roles/EDITOR ◀── F1 │
          │               └───────────────┬──────────────────┘
          │                          B3   │ zen_runtime (least priv)
          │                               ▼
          │               ┌──────────────────────────────────┐
          └──────────────▶│   Postgres (Supabase, Ireland)   │
                          └──────────────────────────────────┘
                                          ▲
                                     B5   │  anon key — bypasses the app entirely
                        ┌─────────────────┴────────────────┐
                        │  Internet → Supabase Data API    │  ← ADR-036, F10
                        └──────────────────────────────────┘

   B8  framework library ──▶ application     (no wire; the seam F2/F4/F8/F9 live on)
   B4  Cloud Scheduler ──▶ POST /api/v1/jobs/trigger   (constant-time secret — verified)
```

### Assets, ranked

| # | Asset | Why it ranks here |
|---|---|---|
| A1 | **The `jzen-prod` GCP project** | F1 makes it reachable from the request path. Contains everything below. |
| A2 | The 20 Secret Manager secrets (DB, SMTP, Supabase, jobs token) | One `secretAccessor` grant away from the runtime identity; all injected per instance start. |
| A3 | The `users` table (email + role) | The only PII store. Admin role lives here, not in the JWT. |
| A4 | `zen_access_token` / `zen_refresh_token` cookies | The session. httpOnly, `Secure` by config. |
| A5 | The admin role | Full CRUD over A3 via `/api/v1/admin/users`. |
| A6 | `ZEN_JOBS_TRIGGER_TOKEN` | Drives retention — i.e. account anonymisation. |
| A7 | The Supabase anon key | Published on purpose; B5 is what makes it matter. |
| A8 | Artifact Registry push credential | A developer's gcloud, not a CI key (F6). |

### Threats that are live, per boundary

Only live threats are listed. STRIDE categories that the deployment makes unreachable are marked
out of scope with the reason, rather than enumerated.

| B | Live threat | Why live here | Covered by |
|---|---|---|---|
| B1 | Unauthenticated body reaches two parsers before resource matching | `@PreMatching`, `@PermitAll` login, no edge | F7, F15 |
| B1 | An endpoint added without an authorization annotation is world-reachable | no default-deny | **F2** |
| B2 | — | Outbound only, pinned URL, 2 s timeouts. Out of scope: SSRF (no user-controlled destination). | Closed |
| B3 | App role escalation to DDL | Split is provisioned (`APP_DB_*` present in prod) | Closed C7 |
| B4 | Trigger forgery → mass anonymisation | Internet-reachable, `--allow-unauthenticated` | Closed C3 (verified) |
| B5 | Data API reaches tables the app never sees | anon key is public by design | ADR-036; **F10** |
| B6 | Fragment-borne token replay / referrer leak | account-takeover primitive by construction | Closed C8 (partial) |
| B7 | A push to `main` skips every gate | no branch protection | **F3**, F5, F6 |
| B8 | A second app inherits code without controls | the framework seam | **F2, F4, F8, F9** |
| B9 | Admin panel XSS → highest privilege in the system | react-admin, `style-src 'unsafe-inline'` | F5 (dompurify), F11 |
| **all** | **Container compromise → project compromise** | `roles/editor` on the request path | **F1** |

---

## 3. Architectural findings

### F1 — The container that terminates untrusted internet traffic runs as a project Editor

**Class:** architectural **Scope:** pipeline (every app deployed by `task deploy:cloudrun`)
**Confidence:** verified **Boundary:** all — it is the blast radius of every other finding
**Standard:** ASVS 5.0.0 **V13 Configuration**; OWASP CI/CD **CICD-SEC-2** (Inadequate Identity and
Access Management); API Security Top 10 **API8:2023** (Security Misconfiguration)

**Where:** the deployed service `zen-demo-server`, `spec.template.spec.serviceAccountName`;
`Taskfile.yml` `deploy:cloudrun`, which never passes `--service-account`.

**Evidence:**

```
$ gcloud run services describe zen-demo-server --project=jzen-prod --region=europe-central2 \
    --format='value(spec.template.spec.serviceAccountName)'
807939740716-compute@developer.gserviceaccount.com

$ gcloud projects get-iam-policy jzen-prod --flatten='bindings[].members' \
    --filter='bindings.members:807939740716-compute@developer.gserviceaccount.com' \
    --format='value(bindings.role)'
roles/editor
roles/secretmanager.secretAccessor
```

The default Compute Engine service account carries `roles/editor` project-wide. `deploy:cloudrun`
does not set `--service-account`, so Cloud Run assigns that default. Note the second line: the
grant the application actually needs — `secretmanager.secretAccessor` — is **already present
separately**. `roles/editor` is pure excess; nothing in jZen uses it.

**Exploitability today:** it is not itself a way in. It is the multiplier on every way in. The
service is `--allow-unauthenticated` with `ingress: all`, it parses attacker-controlled Protobuf and
JSON before authentication, and there is no edge (ADR-027). Any RCE, deserialization fault, or SSRF
in that process runs with the metadata server one HTTP call away, and `roles/editor` on the token it
returns.

**Impact:** read all 20 secrets (DB credentials, SMTP credentials, `ZEN_JOBS_TRIGGER_TOKEN`,
`SUPABASE_KEY`); drop the database; delete or replace the Cloud Run service; push a new image to
Artifact Registry. Total loss of `jzen-prod`, from a single application-layer bug.

**Silent?** **Yes, and doubly so.** The insecure value is what you get by *not deciding* — no line in
this repository names the runtime identity, so nothing to review, nothing to diff, nothing to test.
`verify:deploy` does not check it. This is the infrastructure instance of the pattern plan §1 names:
a missing declaration producing no error and no signal.

**Fix:** create a dedicated runtime service account with `roles/secretmanager.secretAccessor` and
nothing else, and pass `--service-account` in `deploy:cloudrun`'s `gcloud run deploy` invocation
(around `Taskfile.yml:2232`). Add the account to the ONE-TIME SETUP block beside the existing step
1c/1d. Then assert it: `verify:deploy` should read `serviceAccountName` back and fail if it is the
`*-compute@developer` default — otherwise the next `deploy` from a fresh checkout silently restores
it.

**What the fix costs:** one one-time setup step and one flag. Nothing gets worse. The migration job
(`Taskfile.yml:2152`) needs the same account or its own. Verify Cloud Scheduler's OIDC caller is
unaffected — it authenticates with the header secret, not IAM (`JobTriggerAuthenticator`), so it is
not.

**Invariant touched:** none.
**ADR consequence:** none. ADR-027 and ADR-028 are about scaling and cost, not identity. A successor
would be a *new* ADR recording the runtime identity, not a supersession.

---

### F2 — Authorization has no default-deny: a resource method with no annotation is public

**Class:** architectural **Scope:** framework **Confidence:** verified **Boundary:** B1, B8
**Standard:** ASVS 5.0.0 **V8 Authorization**; API Security Top 10 **API5:2023** (Broken Function
Level Authorization)

**Where:** `apps/zen_demo/zen_demo_server/src/main/resources/application.properties` — the absence of
`quarkus.security.deny-unannotated-members`. Demonstrated by
`apps/zen_demo/zen_demo_server/src/main/java/zen/demo/HealthResource.java`.

**Evidence:** a full enumeration of every JAX-RS method in the repository and its authorization
annotation (not a sample — plan Phase 3 asks for enumeration):

| Endpoint | Annotation |
|---|---|
| `GET /api/v1/health` | **none** |
| `GET /api/v1/demo/ping`, `/terms`, `/profile` | `@PermitAll` |
| `POST /api/v1/auth/login`, `/register`, `/restore-password`, `/session`, `/logout`, `/refresh` | `@PermitAll` |
| `GET /api/v1/auth/identity` | `@PermitAll` |
| `POST /api/v1/auth/password` | `@Authenticated` |
| `GET|PUT /api/v1/admin/users[/{id}]` | class-level `@RolesAllowed(ADMIN)` |
| `POST /api/v1/jobs/trigger` | `@PermitAll` + header secret |
| `GET /.well-known/*`, `/auth/callback` | `@PermitAll` |

```
$ grep -rn "deny-unannotated\|auth.permission" --include="*.properties" --include="*.java" . | grep -v /target/
(no configuration match)
```

Every endpoint today is either correctly annotated or intentionally public — `HealthResource` is
deliberately open and is not itself a defect. **The finding is the default, not the instance.** With
`quarkus.http.auth.proactive=true` and `deny-unannotated-members` unset, a method that simply omits
its annotation is served to anonymous callers.

**Exploitability today:** none — no current endpoint is accidentally unannotated. This is a latent
framework property, which is precisely the class plan §1 says a line-level audit cannot see.

**Impact:** the next mutating endpoint added to `zen-identity`, `zen-jobs`, or any application that
omits `@RolesAllowed` is world-callable. Given `AdminUserResource` is a *framework* resource, the
plausible instance is a new admin route in a library.

**Silent?** **Yes.** No test, no gate, no log line. `HealthResource` proves it compiles, ships and
serves 200 with no annotation and no warning.

**Note the inconsistency this exposes.** jZen already made the opposite — correct — choice one layer
over: `CsrfRules.applies()` is **default-deny** (everything under `api/` is protected unless it
appears in `EXEMPT_PATHS`). So the system is default-deny for CSRF and default-allow for
authorization. That asymmetry is the finding's sharpest form, and it answers lead L8: CSRF's default
is right, and it is authorization's that is not.

**Fix:** set `quarkus.security.deny-unannotated-members=true`. It belongs in the **framework**, not
in `zen_demo`'s properties — `server/zen-transport/src/main/resources/META-INF/microprofile-config.properties`
(the pattern `zen-ratelimit` already uses to ship production defaults), so every app inherits it
rather than remembering it.

**What the fix costs:** real, and must be paid deliberately. `HealthResource` would start returning
401 and must gain `@PermitAll` — as must anything else unannotated, including in a second app. That
is the point: the change converts a silent omission into a compile-time-visible decision. Run
`task test:apps:server` and `task test:e2e` after; `/api/v1/health` is what Cloud Run probes.

**Invariant touched:** none.
**ADR consequence:** none directly; ADR-017 chose Jakarta Security and states the enforcement rules,
and this completes them rather than contradicting them.

---

### F3 — `main` is unprotected, so every gate in the repository is advisory

**Class:** process **Scope:** pipeline **Confidence:** verified **Boundary:** B7
**Standard:** OWASP CI/CD **CICD-SEC-1** (Insufficient Flow Control Mechanisms); ASVS 5.0.0
**V15 Secure Coding and Architecture**

**Evidence:**

```
$ gh api repos/jZenDev/jZen/branches/main/protection
{"message":"Branch not protected","status":"404"}

$ gh api repos/jZenDev/jZen --jq '{secret_scanning, push_protection, dependabot, visibility}'
secret_scanning: disabled   push_protection: disabled   dependabot: disabled   visibility: public
```

`.github/workflows/ci.yml` runs `verify:boundaries`, `sync:contracts`, `verify:docs`, the client,
admin, backend and e2e suites, and the web-bundle compile. **None of them is a required check**, and
nothing requires a pull request at all. A direct `git push` to `main` ships past all of it.

**Exploitability today:** requires write access to the repository, so this is an insider/compromised-
credential control, not a remote one. The repository is **public**, which raises the value of the
account rather than the code.

**Impact:** the four controls the architecture leans on hardest are exactly the ones that only exist
as CI jobs — `verify:boundaries` (the one gate for "the client talks to one server", which STANDARDS
says fails *silently* if broken), `sync:contracts`, `verify:docs`, `test:e2e`. Bypassing CI removes
all four at once.

**Silent?** **Yes.** A green CI badge on a branch nobody was required to use looks identical to an
enforced gate.

**Fix:** protect `main` — require a pull request and mark `gates`, `backend`, `e2e` and
`android-runner` as required status checks. Enable secret scanning and push protection (both free on
public repositories) and Dependabot alerts. All are repository settings, not code.

**What the fix costs:** a developer can no longer push straight to `main`. On a single-maintainer
repository that is friction with no reviewer to justify it — so the honest framing is: required
*status checks* are the part that matters here, and they work with or without required reviews.

**Invariant touched:** none — this *restores* invariant 8 ("no gate can pass having checked
nothing") at the flow-control layer, where it is currently unenforced.
**ADR consequence:** ADR-034 established the audit gate's standing. A successor would extend that
reasoning from "the gate must not lie" to "the gate must be unskippable".

---

### F4 — `zen_secure_store`'s security property holds only because the *application* remembers to guard it

**Class:** architectural **Scope:** framework **Confidence:** verified **Boundary:** B8
**Standard:** OWASP **MASVS-STORAGE** (sensitive data at rest); ASVS 5.0.0 **V14 Data Protection**

**Where:** `client/zen_secure_store/lib/src/secure_token_store.dart` (no web guard) versus
`apps/zen_demo/zen_demo_client/lib/main.dart:37` (the guard).

**Evidence:**

```dart
// apps/zen_demo/zen_demo_client/lib/main.dart:37  — the guard, in the APPLICATION
final TokenStore? tokens = zenIsWeb ? null : SecureTokenStore();
```

```dart
// client/zen_secure_store/lib/src/secure_token_store.dart — the FRAMEWORK, unguarded
_storage = storage ?? const FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
      mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    );
```

```
# what the web implementation would do, if it were reached:
~/.pub-cache/hosted/pub.dev/flutter_secure_storage_web-2.1.1/lib/flutter_secure_storage_web.dart:39
        ? web.window.sessionStorage
        : web.window.localStorage;
```

`zen_demo` is **correct**: on web it passes `null`, so no `SecureTokenStore` is constructed and the
refresh token stays in the httpOnly `zen_refresh_token` cookie. Lead L6 is refuted *for this app*.

The finding is that the correctness lives in the app. `SecureTokenStore` itself will happily
construct on web, where `flutter_secure_storage` resolves to the web backend and puts the refresh
token in **`localStorage`** — readable by any XSS, with `first_unlock_this_device` silently
meaningless because there is no Keychain.

**Exploitability today:** none in `zen_demo`. Live in the second application the moment it writes
`SecureTokenStore()` without the `zenIsWeb` ternary — the natural thing to write, since the class
name promises the property.

**Impact:** a refresh token in `localStorage` on the same origin as the admin panel and the SPA. XSS
becomes durable account takeover instead of a session-length one.

**Silent?** **Yes** — and this is the client-side instance of jZen's signature class. It compiles, it
runs, `flutter build web --wasm` succeeds, the app works, and every suite passes:
`client/zen_secure_store/test/secure_token_store_test.dart` runs on the Dart VM, never on web.

**Fix:** move the guard into the framework, where the promise is made. Either make
`SecureTokenStore`'s factory return `null`/throw on web (`zenIsWeb` is already available from
`zen_core`), or — better, and consistent with STANDARDS "Client config is compile-time" — give
`zen_secure_store` a conditional export so the web branch is a stub that refuses, the way
`zen_transport` already does with `session_client_io.dart` / `session_client_web.dart` /
`session_client_stub.dart`. That pattern exists three files away and is the house answer to exactly
this question.

**What the fix costs:** near nothing; `zen_demo`'s ternary becomes redundant and can stay as
belt-and-braces. Touches no invariant — the conditional-import mechanism is the one STANDARDS
mandates.

**Invariant touched:** none (invariant 2 is *upheld* more strongly).
**ADR consequence:** none.

---

### F5 — `task audit` is not run automatically anywhere, and it is red today

**Class:** process **Scope:** pipeline **Confidence:** verified **Boundary:** B7, B9
**Standard:** OWASP CI/CD **CICD-SEC-3** (Dependency Chain Abuse); ASVS 5.0.0 **V15**

**Evidence:**

```
$ grep -n 'audit' .github/workflows/ci.yml
(no match)

$ grep -n 'schedule\|workflow_dispatch' .github/workflows/ci.yml
(no match — triggers are pull_request and push:[main] only)

$ task audit
  ok   259 Java dependencies checked, no known vulnerabilities.
  moderate  DOMPurify: IN_PLACE hook removal leaves a detached subtree executable, causing XSS
  Package: dompurify   Vulnerable: <=3.4.12   Patched: >=3.4.13
  Paths: .>react-admin>ra-ui-materialui>dompurify
  1 vulnerabilities found — Severity: 1 moderate
task: Failed to run task "audit": exit status 1
```

**This is a doc/system disagreement, which plan §5.3 identifies as the most valuable class.**
ADR-034 records that `task audit` "is run in CI on a schedule and before a release". It is run in
neither: `ci.yml` has no `schedule:` trigger and never invokes it, and there is no release checklist
in the repository that does. Lead L3 is confirmed. The gate exists, is well-built, has already
caught two HIGH advisories once — and fires only when a human remembers.

**Exploitability today:** the live advisory is a DOMPurify XSS reachable through
`react-admin > ra-ui-materialui`, in the **admin panel** — the highest-privilege surface in the
system (B9). Whether it is reachable in practice depends on whether the panel renders untrusted HTML
through the affected path; that was not established, and the finding is the *gate*, not the CVE.

**Impact:** dependency advisories accumulate unobserved. Compounded by Dependabot being disabled
(F3): **nothing at all currently watches jZen's dependencies.**

**Silent?** **Yes.** The gate is honest when it runs — ADR-034 was careful that "we did not look" and
"we looked and it was clean" cannot share an exit code — but nothing makes it run.

**Fix:** add a `schedule:` trigger (weekly) and a `workflow_dispatch:` to `ci.yml` with a job that
runs `task audit`, in its own workflow file so a red advisory does not block unrelated PRs. Then
either bump `react-admin` past the patched `dompurify`, or record the exposure in
`scripts/audit-suppressions.txt` with the reasoning — the suppression file already exists for this.

**What the fix costs:** a scheduled job that can go red on a day nobody changed anything. That is
exactly what STANDARDS says it should do, and why it is deliberately outside `task test`.

**Invariant touched:** none.
**ADR consequence:** ADR-034 should be **superseded or amended** — it asserts a CI wiring that does
not exist. That is the ADR to name.

---

### F6 — The artifact that ships never passes through CI

**Class:** supply-chain **Scope:** pipeline **Confidence:** verified **Boundary:** B7
**Standard:** OWASP CI/CD **CICD-SEC-9** (Improper Artifact Integrity Validation), **CICD-SEC-1**;
SLSA (build provenance) — **level 0**

**Evidence:** `.github/workflows/ci.yml:4–9` states it plainly, as a deliberate decision:

> Deliberately NOT here, and why:
> `build:server:native` / `test:native` — the native build is slow and stays LOCAL … prod ships
> from a local build.
> `deploy:cloudrun` — deploy is manual, by a person. CI verifies; it never ships.

So the shipped native image is built on a developer workstation, tested there by `task test:native`,
and pushed to Artifact Registry from there with that developer's `gcloud` credentials. There is no
CI→GCP credential at all — which answers lead L5's "long-lived key vs workload identity federation"
question: **neither, because CI never deploys.**

Confirmed absent from the pipeline: any SBOM (CycloneDX or SPDX), any image signature (cosign or
otherwise), any provenance attestation.

Confirmed **present** and good: the base image is pinned by digest
(`quay.io/quarkus/ubi9-quarkus-micro-image@sha256:d4295e70…`) and the container runs as `USER 1001`.

**Exploitability today:** requires compromise of a maintainer's workstation. Not remote.

**Impact:** the JVM tests CI runs are not run against the artifact that serves traffic; native-image
divergence is a documented silent class in this repository (plan §5.2 cites `quarkus.log.min-level`).
And nothing downstream can verify that the image in Artifact Registry is the one built from the
reviewed commit — no signature, no attestation, no SBOM to diff.

**Silent?** **Yes**, in the specific sense that matters: there is no mechanism by which a substituted
or locally-modified image would be noticed.

**Fix, in the order the value comes:**
1. **Record what shipped.** Have `deploy:cloudrun` generate a CycloneDX SBOM (`cyclonedx-maven-plugin`
   is a Maven plugin, so it stays inside "task triggers native tools") and store it beside the image.
2. **Sign the image** with cosign at push time and verify at deploy.
3. Only then consider moving the native build into CI — which is a genuine cost decision the
   workflow file already argues, and this review does not overturn it.

**What the fix costs:** (1) and (2) add minutes to a deploy that is already long, and add cosign to
the toolchain `task doctor` checks. Neither touches an invariant. (3) would touch the cost reasoning
in `ci.yml` and is not recommended here.

**Invariant touched:** none for (1) and (2).
**ADR consequence:** none. Worth a new ADR recording SLSA level 0 as a *decision* rather than an
omission, since the reasoning in `ci.yml` is sound and only its consequence is unrecorded.

---

### F7 — A malformed body on either codec is an unmapped 500, not a `ZenError`

**Class:** implementation **Scope:** framework **Confidence:** verified **Boundary:** B1
**Standard:** ASVS 5.0.0 **V16 Security Logging and Error Handling**; API Security Top 10
**API8:2023**

**Where:** `server/zen-transport/src/main/java/zen/transport/ProtoJsonMessageBodyReader.java:35–38`
and `ProtobufMessageBodyReader.java:29–31` — neither catches `InvalidProtocolBufferException`, and
`zen-transport` registers no `ExceptionMapper`. `zen-identity`'s `AuthExceptionMapper` covers
`AuthException` only.

**Evidence.** Against the app in **`%prod`** profile (JVM, local, throwaway DB):

```
$ curl -X POST -H 'Content-Type: application/json' -d '{"email":' .../api/v1/auth/login
500 - Internal Server Error
Details:  Error id b79b86ed-…-1
Stack:

$ curl -X POST -H 'Content-Type: application/x-protobuf' --data-binary $'\xff\xff\xff\xff\xff' .../api/v1/auth/login
500 - Internal Server Error
Details:  Error id b79b86ed-…-2

  malformed json  -> 500
  malformed proto -> 500
```

And in **`%dev`**, the same requests return the exception class, message and stack trace in the
response body:

```
Details: Error id …, com.google.protobuf.InvalidProtocolBufferException:
         java.io.EOFException: End of input at line 1 column 10 path $.email
Stack:   com.google.protobuf.InvalidProtocolBufferException: jav…
```

**Both halves were checked deliberately, per plan §5.2.** The stack-trace disclosure is `%dev` only
and does not ship. The 500 does ship.

**Exploitability today:** trivially reachable, unauthenticated, on both codecs, on every resource
that takes a body. It is not a memory-safety issue — the limits hold (see C4) — it is an error-
contract and observability defect.

**Impact:** three things, in increasing order of importance.
1. A client error is reported as a server error, so genuine 5xx alerting is polluted by anyone
   sending a bad byte. On a single instance with no edge, that is also the cheapest way to make the
   error rate meaningless before doing something else.
2. The body is not a `ZenError`, so the Dart `ZenClient` cannot decode it and surfaces a *decode*
   failure rather than the server's actual complaint — CLAUDE.md's "the client never swallows a
   decode failure" holds, but the user-visible result is "I could not understand the server" for
   what is really "you sent bad JSON".
3. **STANDARDS' own framing.** "Every endpoint declares its own request and response messages …
   `ZenError` carries the error." For the codec layer, it does not.

**Silent?** **Partly.** Nothing tests it, and no gate covers it — but a 500 is logged, so it is
observable in principle. That is why it ranks Medium and not higher.

**Fix:** a `@Provider ExceptionMapper<InvalidProtocolBufferException>` in `zen-transport` (the module
that owns the codecs, and the one already Jandex-indexed, so every app inherits it) returning **400**
with a `ZenError` whose message names the codec and says nothing about the parser's internals. Add a
test in `zen-transport`'s own suite — this is one of the controls F8 says the framework should be
able to prove about itself, and it can be, because it needs no assembled app.

**What the fix costs:** nothing. One new provider, one new proto-shaped error path that already
exists.

**Invariant touched:** none — it *restores* "failures surface" and invariant 10 (proto-first errors).
**ADR consequence:** none.

---

### F8 — The framework proves its logic and never its wiring; only the application proves the wiring

**Class:** architectural **Scope:** framework **Confidence:** verified **Boundary:** B8
**Standard:** none. This is the finding no OWASP list names — plan §1's "question 2".

**Evidence.** Test classes by module:

| Module | Test classes | What they can prove |
|---|---|---|
| `zen-core` | 0 | — |
| `zen-proto` | 0 | — |
| `zen-email` | 0 | — |
| `zen-transport` | 2 | pure logic (`CorsCredentialsGuardTest`) |
| `zen-identity` | 5 | pure logic (`CsrfRulesTest`, `RedirectTargetsTest`, `UserRoleLoaderLatchTest`) |
| `zen-jobs` | 2 | pure logic (`JobTriggerAuthenticatorTest`) |
| `zen-ratelimit` | 4 | pure logic (`ClientAddressTest`, `BurstLimiterTest`, `RateLimitRuleTest`) |
| **`apps/zen_demo/zen_demo_server`** | **30** | **all wiring** |

**Lead L2 is refined rather than confirmed.** The framework modules are *not* untested — they carry
good unit tests for the logic that can be tested without a container. What lives only in the
application is the proof that the logic is **actually wired**, and the repository even has a naming
convention for it: `SecurityHeadersWiringTest`, `CsrfWiringTest`, `RateLimitWiringTest`,
`CorsCredentialsGuardWiringTest`, `MigrateOnlyWiringTest` — five `*WiringTest` classes, all in
`zen_demo`.

This is structurally necessary (`@QuarkusTest` needs an assembled app — CLAUDE.md), so it is not a
mistake. **The finding is that nothing carries the requirement across the seam.** A second
application gets `zen-transport` and `zen-identity` on its classpath and gets *zero* of those five
tests. If its assembly is subtly wrong — a missing dependency, an excluded module, a Jandex omission
(F9) — `SecurityHeaders` contributes nothing, and the second app's suite is green.

**Exploitability today:** none. Live for application number two, which ADR-026 already contemplates.

**Impact:** the controls at risk are exactly the load-bearing ones: security headers, CSRF, rate
limiting, the CORS credentials guard, migrate-only mode.

**Silent?** **Yes**, by construction — a control that is not wired does nothing and says nothing.

**Fix:** the seam needs an artifact, not a document. Two options, in preference order:
1. **Ship the wiring tests as a test-jar.** Package the five `*WiringTest` classes in a
   `zen-conformance` module (or `zen-transport`'s `test-jar`) that an application declares in test
   scope and runs against its own assembly. A new app then inherits the *proof* the way it inherits
   the code — which is the framework-shaped answer.
2. Failing that, a `verify:assembly` gate that asserts each expected `@Provider`/observer is present
   in the app's Jandex index and CDI container.

Option 1 also gives F9 somewhere to live.

**What the fix costs:** a new Maven module and a documented line in the "assembling a jZen app"
instructions. It is the largest fix in this report and the one with the longest payback — it is
worth doing when the second app starts, not before, and it should be *decided* now rather than
discovered then.

**Invariant touched:** none.
**ADR consequence:** none; extends ADR-001 (the framework/application split).

---

### F9 — The Jandex rule and the no-Jackson rule are held by comments, not by gates

**Class:** architectural **Scope:** framework **Confidence:** verified **Boundary:** B8
**Standard:** none — this is the silent-no-op census (plan Phase 2 Part B).

**Evidence.** The census, run across every library module:

```
zen-core        beancls:0   jandex:0     ← no beans, correctly no jandex
zen-proto       beancls:0   jandex:0     ← no beans, correctly no jandex
zen-email       beancls:1   jandex:1  ok
zen-identity    beancls:15  jandex:1  ok
zen-jobs        beancls:4   jandex:1  ok
zen-ratelimit   beancls:6   jandex:1  ok
zen-transport   beancls:9   jandex:1  ok
zen_demo_server beancls:3   jandex:0     ← the app itself; Quarkus scans it directly
```

**The rule holds today, in every module.** And the Jackson prohibition holds too — the built app
carries `quarkus-rest-client-jackson` and `quarkus-rest-jackson-common` (its transitive) but **not**
server-side `quarkus-rest-jackson`:

```
$ ls apps/zen_demo/zen_demo_server/target/quarkus-app/lib/main/ | grep -i jackson
io.quarkus.quarkus-jackson-3.38.0.jar
io.quarkus.quarkus-rest-client-jackson-3.38.0.jar
io.quarkus.quarkus-rest-jackson-common-3.38.0.jar
```

**What is missing is any enforcement.** Searching for a gate:

```
$ grep -rln 'jandex' --include='*.java' --include='*.py' --include='*.yml' server apps scripts .github | grep -v /target/
server/zen-ratelimit/src/main/java/zen/ratelimit/RateLimitFilter.java      ← a javadoc comment
server/zen-ratelimit/src/main/java/zen/ratelimit/package-info.java         ← a javadoc comment
server/zen-identity/src/main/java/zen/identity/auth/CsrfFilter.java        ← a javadoc comment
server/zen-identity/src/main/java/zen/identity/schema/MigrateOnlyRunner.java ← a javadoc comment
server/zen-transport/src/main/java/zen/transport/CorsCredentialsGuard.java ← a javadoc comment
```

Five javadoc comments and one line in STANDARDS. No test, no `verify:` task, no Maven enforcer rule.
The census command in plan Phase 2 — the one that produced the table above — **is not part of any
gate**; this review ran it by hand.

**Exploitability today:** none. Both rules currently hold.

**Impact:** a new library module (`zen-email` is the most recent, and STANDARDS lists more planned)
that contributes a `@Provider` and omits `jandex-maven-plugin` has its filters, writers and
augmentors silently do nothing. CLAUDE.md names this as one of the three known silent mechanisms;
what the census adds is that **the countermeasure is folklore**, which is the question plan §1 says
nobody had asked.

The Jackson rule is *slightly* better off: reintroducing `quarkus-rest-jackson` would produce wrong
response bodies that the existing suites would likely notice. It is not silent in the same degree.

**Silent?** **Yes** for Jandex — nothing errors, nothing warns, and the symptom is a missing control
rather than a failure.

**Fix:** make the census a gate. A small `scripts/verify-modules.py` (Rule 3 work — it must
*understand* pom.xml and Java source, so Python, per STANDARDS "Scripting") that fails when a module
under `server/zen-*` contains a CDI/JAX-RS annotation and its `pom.xml` lacks `jandex-maven-plugin`,
and when any `pom.xml` names `quarkus-rest-jackson` outside a comment. Wire it into `task test`
beside `verify:boundaries`, which is the exact precedent: a cheap static gate for a defect no test
can catch.

**Crucially, give it the stale-scope guard** that `scripts/verify-boundaries.py` already has (see
C10) — a module glob that matches nothing must fail, not pass.

**What the fix costs:** one script, one task, seconds of CI. Nothing.

**Invariant touched:** none — it *implements* invariant 8.
**ADR consequence:** none.

---

### F10 — The Data API lockdown's future-table protection binds to whichever role last ran it

**Class:** architectural **Scope:** framework **Confidence:** reasoned-from-code **Boundary:** B5
**Standard:** ASVS 5.0.0 **V8 Authorization**, **V13 Configuration**

**Where:** `server/zen-identity/src/main/resources/db/migration/R__identity_data_api_lockdown.sql`.

**Evidence.** First, **lead L10 is refuted** — the lockdown is schema-wide, not `users`-only:

```sql
EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', data_api_role);
EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA public'
                   || ' REVOKE ALL ON TABLES FROM %I', ddl_role, data_api_role);
```

and `zen-jobs` and `zen-ratelimit` each ship their own `R__*_row_level_security.sql` with a
`zen_runtime` policy carrying `WITH CHECK`. Both of ADR-036's independent layers are present, and
the file documents its own known gap (a table created by `supabase_admin` via the dashboard).

**The gap this review adds** is in the second statement. `ddl_role := current_user` — the role
Flyway is connected as *at the moment the file runs*. `ALTER DEFAULT PRIVILEGES FOR ROLE X` only
governs objects **X** subsequently creates. So the future-table protection is pinned to one role,
captured once.

Now combine that with how a repeatable migration re-runs: **only when its checksum changes.** The
event that invalidates the captured role — an operator provisioning a different DDL role, which
`application.properties:53–63` explicitly contemplates ("DB_USERNAME/DB_PASSWORD is the DDL role";
"the split cannot complete without an operator") — **does not change this file's checksum.** The
re-run trigger and the invalidation condition are uncorrelated.

**Exploitability today: none.** `DB_USERNAME` in `jzen-prod` is a Secret Manager reference that was
not read (and must not be), but the measured `pg_default_acl` in the file's own header shows
`postgres` as the creating role, and nothing indicates it has changed. This is latent, not live.

**Impact:** if the DDL role is ever rotated or replaced, every table created *after* that point is
born with Supabase's default grants to `anon` and `authenticated` — i.e. world-readable and
world-writable over HTTPS — while the file that is supposed to prevent exactly this sits in the
migration history looking applied and green. The per-table RLS layer would still hold, which is
precisely why ADR-036 insisted on two independent layers; this finding is that layer two silently
degrades to layer one.

**Silent?** **Yes.** Flyway reports the repeatable as applied. `DatabasePrivilegeTest` runs against
Dev Services' plain Postgres, where the whole file short-circuits on `No anon role`.

**Fix:** two options, and the second is better.
1. Have the block `ALTER DEFAULT PRIVILEGES` for *every* role that owns a table in `public`
   (`SELECT DISTINCT tableowner FROM pg_tables WHERE schemaname='public'`), not just `current_user`.
2. **Assert the outcome rather than re-running the cause.** Add a check — in `MigrateOnlyRunner`,
   which already runs on the DDL credentials at deploy time — that queries `pg_default_acl` and
   `information_schema.role_table_grants` for any `anon`/`authenticated` privilege in `public`, and
   fails the deploy if it finds one. That converts a rule that must be re-run into a property that is
   verified, and it would also catch the dashboard-created table the file names as out of reach.

**What the fix costs:** option 2 adds a query to the migration job, which runs once per deploy and
not per boot — so it costs nothing at runtime. It must be guarded on the `anon` role existing, the
same way the file already is, or it breaks `@QuarkusTest`.

**Invariant touched:** invariant 5 is *upheld* (Flyway remains the single authority; option 2 adds a
verification, not a second migration system).
**ADR consequence:** ADR-036 is confirmed in substance. A successor would record the
verify-the-outcome step, not reverse the decision.

---

## 4. Free wins

No invariant touched; each is small and self-contained.

### F11 — Three modern browser headers are absent, and the CSP reports nothing

**Scope:** framework · **Silent?** yes · **Standard:** ASVS 5.0.0 **V3 Web Frontend Security**

**Evidence** — from production (R1–R3) and confirmed locally in `%prod`. Present on all three of
`/api/v1/health`, `/`, `/admin/`:

```
content-security-policy: default-src 'self'; base-uri 'self'; object-src 'none';
  frame-ancestors 'none'; form-action 'self'; script-src 'self' 'wasm-unsafe-eval';
  style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:;
  font-src 'self' https://fonts.gstatic.com; connect-src 'self' https://fonts.gstatic.com;
  worker-src 'self' blob:
x-frame-options: DENY
x-content-type-options: nosniff
referrer-policy: strict-origin-when-cross-origin
strict-transport-security: max-age=31536000
```

Absent: **`Permissions-Policy`**, **`Cross-Origin-Opener-Policy`**, **`Cross-Origin-Embedder-Policy`**,
**`Cross-Origin-Resource-Policy`**, and any CSP `report-to` / `report-uri`.

The CSP itself is strong and unusually well-argued (`SecurityHeaders`' javadoc is 110 lines
explaining every relaxation, including the `connect-src` font trap found in a browser). The gap is
only these four.

**Fix:** in `SecurityHeaders.apply()` (`zen-transport`, so every app inherits it):
`Permissions-Policy: geolocation=(), camera=(), microphone=(), payment=(), usb=()` — jZen uses none
of them; `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Resource-Policy: same-origin`.
**Do not set COEP** without testing: `require-corp` interacts with the Wasm renderer's blob workers
and `fonts.gstatic.com`, and this review did not verify it in a browser.

**Cost:** COOP `same-origin` severs `window.opener` — check the email-link return flow (B6) still
works, since that is a cross-document navigation. Test in a browser, per the precedent
`SecurityHeaders`' own javadoc sets.

**Opportunity, not a gap:** a CSP report endpoint is ASVS Level 3 territory. Worth noting that
`style-src 'unsafe-inline'` is the policy's weakest term and the admin panel is where it matters
(F5's dompurify advisory is in that same panel); a report endpoint would be the cheapest way to
learn whether Material UI could be moved to nonces.

### F12 — Third-party actions are pinned to mutable tags, one to `latest`

**Scope:** pipeline · **Silent?** yes · **Standard:** OWASP CI/CD **CICD-SEC-3**, **CICD-SEC-9**

**Evidence** from `.github/workflows/ci.yml`: `actions/checkout@v4`, `actions/setup-java@v4`,
`actions/setup-node@v4`, `actions/setup-python@v5`, `subosito/flutter-action@v2`,
`arduino/setup-protoc@v3`, `arduino/setup-task@v2`, `supabase/setup-cli@v1` — every one a **mutable
tag**. Four are third-party (`subosito`, `arduino` ×2, `supabase`). And:

```yaml
      - name: Supabase CLI
        uses: supabase/setup-cli@v1
        with:
          version: latest        # ← unpinned tool, fetched at build time
```

Also unchecksummed at build time: `dart pub global activate protoc_plugin 25.0.0` (version-pinned,
which is the important half) and `corepack enable`, whose `packageManager: "pnpm@10.30.3"` in both
`package.json` files carries **no `+sha512…` integrity hash**.

**Mitigations already present, and they are real:** the workflow triggers on `pull_request`, not
`pull_request_target`, so a fork PR gets no secrets; and the repository's default workflow token is
**read-only** —

```
$ gh api repos/jZenDev/jZen/actions/permissions/workflow
{"default_workflow_permissions":"read","can_approve_pull_request_reviews":false}
```

So lead L4's "no `permissions:` block" is **half-refuted**: the effect is least-privilege today. But
the control lives in a *repository setting*, not in the repository — nothing in the tree asserts it,
and flipping it to `write` silently widens all four jobs at once. That is the same shape as F1.

**Fix:** pin the four third-party actions by commit SHA (`uses: subosito/flutter-action@<sha> # v2`);
pin `supabase/setup-cli`'s `version:` to an exact CLI version; add `packageManager` integrity hashes
(`corepack use pnpm@10.30.3` writes them); and add an explicit top-level
`permissions: contents: read` to `ci.yml` so the least-privilege posture is stated in the repository
rather than inherited from a setting. Dependabot's `github-actions` ecosystem keeps SHA pins current
once F3 enables it.

**Cost:** SHA pins need bumping. Dependabot does that.

### F13 — `task doctor` reports a drift that does not exist

**Scope:** pipeline · **Silent?** no (it is loud, and wrong) · **Standard:** none

**Evidence:**

```
$ task doctor
  DRIFT flutter        (want 3.44.2)
                       run: fvm use
  note  fvm            not installed
task: Failed to run task "doctor": exit status 1

$ flutter --version
Flutter 3.44.2 • channel stable
```

`.fvmrc` pins `3.44.2`; the installed Flutter **is** 3.44.2. `doctor` resolves the version through
`fvm`, so an absent `fvm` presents as version drift.

**Why it is worth a line in a security review:** `doctor` is precondition 3.1 for this review and for
`task deploy:cloudrun`. A gate that cries wolf gets ignored, and the next reader will skip past a
real drift. It is the mirror of ADR-034's concern — there, a tool reported success having checked
nothing; here, a tool reports failure having checked the wrong thing.

**Fix:** fall back to the `flutter --version` already on `PATH` when `fvm` is absent, and report
`ok (unmanaged)` if it matches `.fvmrc` — reserving `DRIFT` for a genuine mismatch and `note` for the
missing tool, which it already prints separately.

**Cost:** none.

### F14 — `/q/health` is public and enumerates its checks

**Scope:** application · **Silent?** no · **Standard:** API Security Top 10 **API9:2023**
(Improper Inventory Management); ASVS 5.0.0 **V13**

**Evidence** — production read R12:

```
$ curl https://…/q/health
{ "status": "UP",
  "checks": [ { "name": "Database connections health check", "status": "UP",
                "data": { "<default>": "UP" } } ] }
```

`/openapi`, `/q/swagger-ui/` and `/q/dev/` all correctly 404 in production (R6–R8 — F15's closure
confirmed on the wire). `/q/health` is the one that remains, unauthenticated, naming the
SmallRye Health check set and the datasource's status.

**Impact:** low. It confirms the stack is Quarkus and gives an unauthenticated database-liveness
oracle. Under `--max-instances=1` it is also a free way to wake and observe the instance.

**Fix:** if Cloud Run's probe is the only consumer, move it to `quarkus.management.enabled=true` on
a separate port that `ingress` does not publish, or restrict it via
`quarkus.http.auth.permission`. Confirm first what `deploy:cloudrun` configures as the startup/
liveness probe — if it is `/api/v1/health` (the application's own, which returns no check names),
`/q/health` may simply be unnecessary.

**Cost:** verify the Cloud Run probe config first; changing the wrong one causes deploy failures.

### F15 — The transport header accepts an undocumented alias, and the docs describe a rewrite that does not happen

**Scope:** framework · **Silent?** yes · **Standard:** none

**Evidence — the alias**, on the wire:

```
X-Zen-Transport: json      -> Content-Type: application/json;charset=UTF-8   echo: json
X-Zen-Transport: protobuf  -> Content-Type: application/x-protobuf           echo: protobuf
X-Zen-Transport: msgpack   -> Content-Type: application/x-protobuf           echo: protobuf   ← undocumented
X-Zen-Transport: MSGPACK   -> Content-Type: application/x-protobuf           echo: protobuf
X-Zen-Transport: garbage   -> Content-Type: application/json;charset=UTF-8   echo: json       ← safe fallback
```

`ZenTransportFormat.parseOrNull` carries `case "msgpack": // accepted alias for the binary format`.
CLAUDE.md, BLUEPRINT and the client's own `ZenTransportFormat` all say the values are `json` and
`protobuf`. A third accepted value exists on the public wire contract and is documented nowhere.

**Evidence — the rewrite.** CLAUDE.md and BLUEPRINT state that `ZenTransportFilter` "rewrites
`Accept`/`Content-Type`". It rewrites only `Accept`:

```java
// ZenTransportFilter.java:44
ctx.getHeaders().putSingle(HttpHeaders.ACCEPT, format.mediaType());
```

So `X-Zen-Transport` selects the **response** codec, and the **request** parser is selected by the
client's raw `Content-Type` via `@Consumes` — independently. This was confirmed on the wire: a
protobuf body sent with `X-Zen-Transport: json` is still parsed by the protobuf reader.

**Why this matters, and why it ranks Low rather than not at all.** The behaviour is *safe* — the two
selections are independent, so the header cannot steer a body into the wrong parser, which answers
plan Phase 4's central question in the negative. But an architecture document that describes the
mechanism incorrectly is how the next person reasons wrongly about it, and this is the seam
CLAUDE.md calls "the framework's core mechanism".

**Fix:** either document `msgpack` or delete it (nothing in `client/zen_transport` emits it — deleting
is safer and is a wire-contract change worth an ADR line). Correct the two documents to say the
filter rewrites `Accept`, and that request parsing is content-type-driven.

**Cost:** none. Both are documentation, plus one `case` label.

---

## 5. Priced trade-offs

Nothing in this review requires an invariant to be broken. That is worth stating explicitly, because
the usual security advice for a system with no edge is "put an edge in front of it", and ADR-027
priced and rejected exactly that (~$25–30/mo Cloud Armor floor; Cloudflare deferred **on invariants,
not price**). **This review does not recommend a WAF, CDN, API gateway, Redis, Kubernetes, or a
second orchestrator.** None of the fifteen findings needs one:

- F1, the highest-ranked finding, is a `--service-account` flag.
- F2 is one config property, placed in the framework.
- F3, F5, F12 are repository settings and workflow edits.
- F7, F9, F10, F11 are code inside modules that already exist.

**The one residual that genuinely has no cheap answer** is the one ADR-027 already accepted in
writing: 200 concurrency slots on one instance, reachable by anyone, with the rate limiter as the
only throttle. This review spent none of that budget (§4.2 of the plan) and found no reason to
reopen the decision. The relevant new fact is F1 — the *consequence* of a successful attack through
that surface is larger than ADR-027 assumed, because it reaches the whole GCP project. **Fixing F1
lowers the price of ADR-027's accepted residual without changing the decision**, which is the
cheapest way to improve that trade and the reason F1 ranks where it does.

**One decision worth re-examining but not overturning here.** ADR-035 stops HSTS short of
`includeSubDomains` and `preload` because the hostname is a generated `*.run.app` address and the
domain question is open. Verified on the wire (R1–R3): `max-age=31536000`, no additions. **The
reasoning holds in 2026** and, notably, `*.run.app` is itself on the HSTS preload list, so the
marginal value of preloading a subdomain of it is near zero. Confirmed, not challenged.

---

## 6. Closed — verified correct, with evidence

### The 2026-08-03 findings, spot-confirmed

| Finding | Confirmation | Evidence |
|---|---|---|
| F15 — OpenAPI off in prod | **holds** | R6–R8: `/openapi`, `/q/swagger-ui/`, `/q/dev/` all **404** in production. No library reintroduced `quarkus-smallrye-openapi` transitively — the extension is present in the JVM build (Maven `openapi` profile) and absent from the native image, exactly as STANDARDS describes. |
| CSRF wiring | **holds** | `CsrfFilter` + `CsrfRules` present, `CsrfWiringTest` + `CsrfRulesTest` + `CsrfFilterTest` green. Default-deny — see C1. |
| Rate limiting | **holds** | `zen-ratelimit` module present with burst + durable tiers, `RateLimitEnforcementTest` proves a real 429 with its own tiny limits; `RateLimitAddressGuard` refuses to boot on a hops/proxy mismatch. |
| Security headers | **holds** | R1–R3, all three surfaces, from production. |
| Database privilege split | **holds** | See C7. |
| Committed dev/test trigger tokens | **scoping holds** | `%dev.zen.jobs.trigger.token` / `%test.…` are profile-scoped literals; `%prod` takes `${ZEN_JOBS_TRIGGER_TOKEN:}` and fails closed — see C3. |

### Verified correct in this review

**C1 — CSRF is default-deny, and its exemption list is closed and central.** Lead L8 refuted.
`CsrfRules.applies()` returns true for **every** non-safe method under `api/` unless the normalized
path is in `EXEMPT_PATHS` — a six-entry `Set.of` in one file. A new endpoint therefore defaults to
**protected**. This is the correct default and the one F2 says authorization should copy.

**C2 — The `api/` prefix gate cannot be evaded by path trickery.** Hypothesised bypass (a leading
`//` surviving `CsrfRules.normalize`, which strips only one leading slash) tested on the wire, using
`ZenTransportFilter`'s echo as the oracle since it consumes the identical `UriInfo.getPath()`:

```
/api/v1/health          -> 200  X-Zen-Transport: json
//api/v1/health         -> 200  X-Zen-Transport: json    ← normalized before the filter sees it
/./api/v1/health        -> 200  X-Zen-Transport: json
/foo/../api/v1/health   -> 200  X-Zen-Transport: json
/%2fapi/v1/health       -> 404
```

The filter matched in every reaching case, so the path arrives already normalized and both the
transport seam and `CsrfRules` see `api/…`. Refuted.

**C3 — The jobs trigger fails closed and compares in constant time.** Verified on the wire:

```
token=''                       -> 401
token='wrong'                  -> 401
token='d'          (1 byte)    -> 401
token='dev-job-trigger-token'  -> 200
```

`JobTriggerAuthenticator.isAuthorized` filters a blank configured secret to `null` before comparing,
so `%prod`'s `${ZEN_JOBS_TRIGGER_TOKEN:}` empty default rejects rather than matching an empty header
— the trap this review specifically looked for. `MessageDigest.isEqual` is the JDK's length-safe
constant-time comparison. Lead L12's trigger-secret concern refuted.

**C4 — Both parsers are bounded.** `quarkus.http.limits.max-body-size=1M`, verified: a 3 MB body
returns **413**. JSON nested 2000 deep returns 500 (protobuf's parser recursion limit), not a hang or
a crash. WebSocket frames are separately bounded at 64 KiB for frame *and* message, with the
reasoning that `max-body-size` does not apply to frames — a trap correctly identified in the config.

**C5 — CORS rejects a disallowed origin, and cannot be misconfigured into a wildcard.** Production
read R5: `OPTIONS` with `Origin: https://evil.example` returns **403** with no
`access-control-allow-origin`. `CorsCredentialsGuard` refuses to boot if
`access-control-allow-credentials=true` meets an unrestricted origin list, and correctly treats all
three "unrestricted" shapes — `*`, unset, **and empty** — as dangerous.

**C6 — `RoleAugmentor` fails closed.** Lead L11 confirmed. On any `RuntimeException` from
`UserRoleLoader` it logs a warning and returns the identity **un-augmented** — authenticated, with no
role — so `@RolesAllowed(ADMIN)` yields 403, not access. The `usersTableConfirmed` latch is a
one-way `volatile` set only on success, and `UserRoleLoaderLatchTest` covers it. Role is read per
request, so a role change takes effect on the next request with no cached copy.

**C7 — The database privilege split is provisioned in production.** Control-plane read: the service
carries both `APP_DB_USERNAME` and `APP_DB_PASSWORD` as Secret Manager references, so ADR-031's
cutover is complete and the application is not falling back to the DDL credentials. All 20 secrets
are `valueFrom` secret references, not literals — only `ZEN_BUILD_ID` is a literal, correctly.

**C8 — `RedirectTargets` is exact-match with an empty default.** `resolve()` accepts only a string
present in the allow-list, which is the configured `auth.redirect-uri` plus an explicitly configured
`auth.redirect-uris` list, empty by default. No prefix matching, no scheme wildcard, no
normalization to be tricked. Lead L15's open-redirect half refuted; the fragment-flow half of B6 was
**not** exercised (no GoTrue — see "What was not assessed").

**C9 — The web bundle carries no secrets.** Lead L7 refuted, with the command:

```
$ WEB_API_URL=https://review.invalid task build:web
$ R=apps/zen_demo/zen_demo_server/src/main/resources/META-INF/resources
$ grep -rIl --binary-files=text -e 'supabase' -e 'service_role' -e 'SUPABASE_KEY' $R   # no output
$ grep -rao --binary-files=text 'eyJ[A-Za-z0-9_-]\{10,\}' $R                            # no output
```

No Supabase reference, no JWT-shaped literal, no service-role key in the dart2wasm bundle.

**C10 — `verify:boundaries` cannot pass vacuously, and covers more than expected.**
`scripts/verify-boundaries.py` scans Dart (`client/*/lib`, `apps/*/*/lib`), TypeScript
(`admin/src`, `apps/*/*_admin/src`), **and `pubspec.yaml` dependency declarations** — so lead L13's
"pubspec" hole is refuted. It carries an explicit `StaleScope` exception that fails when a glob
matches nothing, with the reasoning written at the top of the file: *"a stale glob produces no hits,
and no hits is indistinguishable from a clean repository."* That is invariant 8 implemented, and it
is the model F9 asks for.

**The one hole that remains:** it does not scan Kotlin or Swift. A platform channel in
`android/…/*.kt` or `ios/…/*.swift` calling Supabase directly would pass. Given `zen_demo` has no
custom platform channels today this is latent, and it is a natural addition to the same script
rather than a finding of its own.

**C11 — The admin panel gets the same security headers as the app.** Lead L14's header question:
production read R3 shows `/admin/` returning the identical CSP, `X-Frame-Options`,
`X-Content-Type-Options`, `Referrer-Policy` and HSTS as `/`. Its remaining surface — the auth
provider, where its session lives, react-admin's XSS surface — was reviewed only as far as the
dompurify advisory in F5; a fuller review is in §8.

**C12 — The Jandex rule and the Jackson prohibition both hold today.** See F9's census — the finding
there is the absence of enforcement, not a present violation.

---

## 7. ASVS 5.0.0 coverage map

Level 2 is the bar. Every chapter is marked; "not assessed" is honest and appears where it is true.

| Ch | Name | Verdict | Note |
|---|---|---|---|
| V1 | Encoding and Sanitization | **partial** | Output encoding is proto/proto-JSON, not string templating — injection surface is structurally small. Admin panel's HTML sanitization is the live question (F5, dompurify). Not assessed in the browser. |
| V2 | Validation and Business Logic | **not assessed** | Bean Validation is present (`hibernate-validator` installed); per-endpoint constraint coverage not enumerated. |
| V3 | Web Frontend Security | **gap** | Strong CSP, `frame-ancestors 'none'`, `nosniff`, `Referrer-Policy` all verified on the wire. Missing `Permissions-Policy`, COOP/COEP/CORP, CSP reporting — **F11**. `style-src 'unsafe-inline'` is a known, argued relaxation. |
| V4 | API and Web Service | **gap** | Two parsers bounded and verified (C4); malformed input unmapped — **F7**. Undocumented header alias — **F15**. |
| V5 | File Handling | **n/a** | jZen accepts no file upload and serves only build-produced static assets. |
| V6 | Authentication | **partial** | Delegated to Supabase GoTrue. ES256 pinned, issuer pinned, JWKS cached. **Not exercised** — no GoTrue available (see "What was not assessed"). Neutral-202 enumeration property not re-verified on the new paths. |
| V7 | Session Management | **partial** | httpOnly cookie, `Secure` by config, per-request role resolution (C6), ADR-030's anonymous-on-unverifiable behaviour reviewed in code. **Rotation, upstream logout revocation and expiry not exercised on the wire.** `__Host-` prefix not used — see §8. |
| V8 | Authorization | **gap** | Admin surface correctly `@RolesAllowed(ADMIN)` at class level; RLS scope correct per ADR-031. **No default-deny — F2.** Data API future-table binding — **F10**. |
| V9 | Self-contained Tokens | **partial** | ES256 pinned via `smallrye.jwt.verify.algorithm` (deprecated property — see §8), issuer verified, role deliberately **not** taken from the JWT. Audience is not verified; single-tenant, so low. Algorithm-confusion and JWKS-unreachable behaviour **not** exercised. |
| V10 | OAuth and OIDC | **partial** | ADR-018's implicit fragment flow is explicitly not PKCE. Reviewed as a decision; **not exercised**, and the OAuth 2.1 re-examination is an open question — §8. |
| V11 | Cryptography | **n/a with reason** | jZen implements no cryptography. It consumes JDK primitives (`MessageDigest.isEqual`, correctly) and delegates token minting to Supabase. |
| V12 | Secure Communication | **pass** | HTTPS only at Cloud Run; HSTS verified on the wire; `%prod.quarkus.mailer.start-tls=REQUIRED`; Supabase client over HTTPS with 2 s timeouts. ADR-035's HSTS scope confirmed (§5). |
| V13 | Configuration | **gap** | **F1** (runtime identity), F14 (`/q/health`), F12 (action pinning). Secrets correctly injected as Secret Manager references (C7); no secret in the client bundle (C9). |
| V14 | Data Protection | **partial** | Retention/anonymisation design reviewed in code (`UserRetentionService`, ADR-008); PII-in-logs re-verification and the retention job's behaviour **not** exercised. **F4** is the live data-protection finding. |
| V15 | Secure Coding and Architecture | **gap** | **F8, F9** — the framework/application seam and the unenforced rules. F3, F6 on the pipeline side. |
| V16 | Security Logging and Error Handling | **gap** | **F7** — unmapped codec errors as 500s. Stack traces are `%dev`-only (verified). Log content and retention **not** assessed. |

**Summary: 1 pass · 7 gap · 6 partial · 2 n/a · 0 unmarked.**

---

## 8. Open questions — each with the command a human should run

**Q1 — Verify the Data API lockdown against the hosted project.** Not done, by owner decision
(plan §4.4), and *not* authorised by anything in this review. If the owner decides to:

```bash
# Substitute the project ref and anon key. This presents the anon key to a third-party endpoint.
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "apikey: $SUPABASE_ANON_KEY" \
  "https://<project-ref>.supabase.co/rest/v1/users?select=id&limit=1"
# Repeat for: zen_jobs, zen_rate_limit_counters, flyway_schema_history
# Expect 401 or 404 for every one. A 200 — even an empty array — means the revoke did not take.
```

**Q2 — Verify the Data API lockdown locally**, which this review could not (ports held by another
product). Once 54321/54322 are free:

```bash
task run:supabase && task run:server      # applies migrations incl. R__identity_data_api_lockdown
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c \
  "SELECT grantee, table_name, privilege_type FROM information_schema.role_table_grants
    WHERE table_schema='public' AND grantee IN ('anon','authenticated');"
# Expect zero rows. Then create a new table as the Flyway role and re-run — that tests F10's
# ALTER DEFAULT PRIVILEGES half, which is the part no existing test covers.
task stop:supabase
```

**Q3 — Confirm the runtime service account's roles and fix F1.** The read this review ran:

```bash
gcloud projects get-iam-policy jzen-prod --flatten='bindings[].members' \
  --filter='bindings.members:807939740716-compute@developer.gserviceaccount.com' \
  --format='value(bindings.role)'
```

**Q4 — The email-link flow under current guidance (ADR-018).** Not exercised; needs GoTrue. The
architectural questions that remain open, none of which this review could answer: is a recovery link
single-use and does GoTrue enforce it; what does a link-prefetching mail scanner (Outlook Safe Links,
Gmail image proxy) do to a fragment-borne token — noting that a **fragment is not sent to the
server**, which is the flow's main structural defence and worth stating in the ADR if it is not
already; and does `Referrer-Policy: strict-origin-when-cross-origin` (verified present) suffice given
the token is in the fragment rather than the query. Re-examine against OAuth 2.1, which deprecates
the implicit flow — ADR-018's reasoning is that the client never trusts the token and the *server*
validates it with the provider, which is a materially different posture from classic implicit and
may well survive. **Confirm or challenge explicitly; do not treat as settled.**

**Q5 — `__Host-` cookie prefix.** `zen_access_token` and `zen_refresh_token` use no prefix. Renaming
to `__Host-zen_access_token` would bind them to the exact origin with `Path=/` and no `Domain`,
which the same-origin deployment (ADR-015) already satisfies. **Check first** whether
`mp.jwt.token.cookie` handles a prefixed name, and note this interacts with STANDARDS "Deployment
model" — the whole cookie design depends on nothing renaming cookies at an edge. Low value, cheap,
worth a test.

**Q6 — The deprecated JWT algorithm property.** Every boot logs:

```
SRJWT03006: 'smallrye.jwt.verify.algorithm' property is deprecated and will be removed
in a future version. Use 'mp.jwt.verify.publickey.algorithm' property instead
```

If it is removed in a Quarkus upgrade, SmallRye reverts to its RS256 default and **ES256 tokens stop
verifying** — so this fails *closed*, as an outage rather than a bypass. Rename it anyway; a one-line
change now avoids a confusing production incident later, and the warning is currently noise that
trains readers to ignore boot warnings.

**Q7 — Is a penetration test wanted?** Plan Q7. This review's residual does not obviously justify one
*before* F1, F2 and F3 are closed — a pentest against a service whose container is a project Editor
would mostly re-derive F1. Worth revisiting after.

**Q8 — WebSocket authorization after upgrade (lead L9).** `DemoWebSocket` is `@Authenticated` at
class level, so the handshake is gated. What happens to an **open** connection on logout, role change
or token expiry was **not** established — no session could be minted. The connection cap is
per-instance and therefore valid only at `--max-instances=1`; raising it splits the cap N ways.
Establish with a live session, then decide whether per-message re-authorization is warranted.

---

## 9. Appendix

### 9.1 Control inventory

| Control | Code lives in | Test lives in | Inherited by a new app? | If absent | Silent? |
|---|---|---|---|---|---|
| Security headers / CSP | `zen-transport` `SecurityHeaders` | **app** (`SecurityHeadersTest`, `…WiringTest`, `…BehindProxyTest`) | yes, if Jandex holds | fails **open** | **yes** |
| Static cache/ETag | `zen-transport` `StaticCacheHeaders` | app | yes | open | yes |
| Transport negotiation | `zen-transport` `ZenTransportFilter` | `zen-transport` (partial) | yes | open (JSON default) | yes |
| Codec readers/writers | `zen-transport` ×4 | app | yes | 500s | no |
| **Codec error mapping** | **absent** | — | — | **500 not `ZenError`** | partly (**F7**) |
| CORS credentials guard | `zen-transport` `CorsCredentialsGuard` | `zen-transport` + app wiring | yes | fails **closed** at boot | no |
| CSRF | `zen-identity` `CsrfFilter`/`CsrfRules` | `zen-identity` (logic) + app (wiring) | yes | open | yes |
| Session cookie auth | `zen-identity` `SessionCookieAuthenticationMechanism` | app (`ExpiredSessionCookieTest`) | yes | anonymous (ADR-030) | no |
| Role augmentation | `zen-identity` `RoleAugmentor`/`UserRoleLoader` | `zen-identity` (latch) + app | yes | **closed** (no role) | partly |
| Open-redirect allow-list | `zen-identity` `RedirectTargets` | `zen-identity` | yes | closed (empty default) | no |
| **Endpoint authorization** | annotations only | app, per endpoint | **no default** | **open** | **yes (F2)** |
| Rate limiting | `zen-ratelimit` (all) | `zen-ratelimit` (logic) + app (enforcement) | yes | open | yes |
| Rate-limit address guard | `zen-ratelimit` `RateLimitAddressGuard` | `zen-ratelimit` | yes | **closed** at boot | no |
| Jobs trigger secret | `zen-jobs` `JobTriggerAuthenticator` | `zen-jobs` + app | yes | **closed** | no |
| Migrate-only / rollback refusal | `zen-identity` `MigrateOnlyRunner` | app (`MigrateOnlyWiringTest`) | yes | closed (exit 2) | no |
| DB privilege split | `R__identity_application_role.sql` | app (`DatabasePrivilegeTest`) | yes | falls back to DDL role | **yes** |
| Data API lockdown | `R__identity_data_api_lockdown.sql` | none that reaches it | yes | open | **yes (F10)** |
| Per-table RLS | `R__jobs_…`, `R__ratelimit_…`, `V2` | none that reaches it | per module | zero rows / open | **yes** |
| Client one-server rule | — | `verify:boundaries` gate | gate is repo-wide | open | gate catches it |
| Token storage | `zen_secure_store` | `zen_secure_store` (VM only) | yes, **unguarded on web** | localStorage | **yes (F4)** |
| **Runtime identity** | **nothing** | **nothing** | default = Editor | **project compromise** | **yes (F1)** |

### 9.2 The silent-no-op census

Every mechanism found where a missing or wrong declaration produces **no error and no signal**.
CLAUDE.md names the first three; this review adds seven.

| # | Mechanism | Symptom if wrong | Detected by | New? |
|---|---|---|---|---|
| 1 | `jandex-maven-plugin` omitted from a bean-bearing module | filters/writers/augmentors do nothing | **nothing** — 5 javadoc comments (**F9**) | known |
| 2 | Client package reaching Supabase directly | app works, suites pass, backend stops being the only authority | `verify:boundaries` (Dart/TS/pubspec; **not** Kotlin/Swift — C10) | known |
| 3 | `quarkus-rest-jackson` reintroduced server-side | Jackson claims `application/json`, serializes builder internals | nothing explicit; suites would likely notice (**F9**) | known |
| 4 | **A resource method with no authorization annotation** | endpoint is public | **nothing** (**F2**) | **new** |
| 5 | **`SecureTokenStore()` constructed on web** | refresh token in `localStorage` | **nothing** (**F4**) | **new** |
| 6 | **Runtime service account left at the default** | container holds `roles/editor` | **nothing** (**F1**) | **new** |
| 7 | **DDL role changed after the lockdown last ran** | new tables born world-writable via the Data API | **nothing** (**F10**) | **new** |
| 8 | **A new app that never writes the `*WiringTest` classes** | controls present on the classpath, not wired | **nothing** (**F8**) | **new** |
| 9 | **Repo workflow-permission setting flipped to `write`** | all four CI jobs gain a write token | **nothing** in the repository (**F12**) | **new** |
| 10 | **A push straight to `main`** | every gate skipped | **nothing** (**F3**) | **new** |

**The pattern across all ten:** the insecure state is what you get by *not acting* — an omitted
plugin, an omitted annotation, an omitted flag, an unwritten test, an unchanged default. jZen's
controls are almost all correct and almost all opt-in. Items 6, 9 and 10 add a dimension CLAUDE.md's
three did not have: **the declaration is not in the repository at all**, so no amount of code review
can reach it.

### 9.3 Gate coverage

| Gate | Checks | Does *not* check, despite the name | Can it pass having checked nothing? |
|---|---|---|---|
| `verify:boundaries` | provider SDK in client pkgs, provider host/credential in client code, absolute URL literals — Dart `lib/`, TS `src/`, **and `pubspec.yaml`** | Kotlin/Swift platform channels; a transitive Dart package bundling its own HTTP client | **No** — `StaleScope` fails when a glob matches nothing. The model gate. |
| `sync:contracts` | regenerates all cross-language artifacts, diffs the tree | that generation actually *ran* — mitigated by STANDARDS' "never fingerprint a task a gate composes" | No, given that rule holds |
| `verify:docs` | documented `task` references resolve | whether the prose is *true* (F5 and F15 are both doc/system disagreements it cannot see) | No |
| `audit` | 259 Java deps + npm vs OSV; fails on finding **and** on unreachable DB | — | No. **But it runs nowhere automatically (F5)** |
| `test:e2e` | real Supabase + Quarkus, no mocks | the native image; the deployed artifact | No |
| `doctor` | toolchain versions | Flutter, when `fvm` is absent — reports false DRIFT (**F13**) | No (it over-reports) |
| `verify:endpoints` | headers present, `/openapi` absent from the image | whether the page is *usable* — the `SecurityHeaders` javadoc records a CSP that passed this gate and rendered no text | No |
| **module rules** | — | **Jandex, Jackson — no gate exists (F9)** | **n/a** |
| **branch protection** | — | **nothing; not enabled (F3)** | **n/a** |

---

## Closing note

The architecture documents in `../architecture/` are, on the evidence of this review, unusually
accurate — the CSP javadoc, the rate-limit config comments, ADR-036's lockdown file and the
`verify-boundaries.py` header each anticipate a failure mode this review went looking for and found
already handled. Three places where a document and the system disagree became findings (**F5**
ADR-034's CI wiring, **F13** `doctor`'s drift report, **F15** the `Accept`/`Content-Type` rewrite),
which is a low rate for 6,000 lines of prose.

The gap is not knowledge. It is that jZen's controls are **opt-in, and the framework has no way to
make an application take them** — F2, F4, F8, F9 and F10 are five faces of one shape, and the
ten-row census in §9.2 is its measure. F1 sits outside that pattern and above it, because it is the
only finding whose blast radius is the entire project rather than the application.
