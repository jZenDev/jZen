# Prompt: the architectural security review of jZen

This file is **the brief you hand to the reviewing model**, not the review. Everything below the
`---` is the prompt; paste it whole, or point the agent at this file. The material above the `---`
is for the person commissioning it.

**Why this exists.** jZen has already had one security audit
([`implemented/SECURITY-REMEDIATION.md`](implemented/SECURITY-REMEDIATION.md), 2026-08-03), and all
four of its waves are implemented. That audit worked at the level of a file and a line. This review
works at the level of a boundary and a control's *location*, and its reason for existing is that
jZen is a **framework**: a control that lives in `apps/zen_demo` protects one application, and a
control that can silently fail to load protects none. No generic OWASP checklist asks that question.

**Companion documents.** This brief states *what* the review must produce and how it will be judged.
[`SECURITY-ARCHITECTURE-REVIEW-PLAN.md`](SECURITY-ARCHITECTURE-REVIEW-PLAN.md) states *how* — the
phase order, the exact commands, the method traps, and the rules of engagement. **The reviewer needs
both.** Where the two disagree, the plan wins on method and this file wins on scope.

**Scope note for the commissioner.** The prompt assumes an agent with repository access, a shell,
Docker, and *read-only* discipline against the deployed environment. The two decisions that were
open are **settled as of 2026-08-13** and are written into both documents, so the reviewer weighs
neither: the bar is **ASVS Level 2**, and the hosted Supabase Data API is **not probed** — ADR-036's
lockdown is verified against the local stack. Nothing else needs answering before handoff.

**This review produces no code.** It is the middle document of three: this review, then an owner
decision pass, then a remediation plan with waves. Do not ask the reviewer to fix what it finds.

---

# You are conducting an architectural security review of jZen

## 1. Your objective

Produce a ranked, evidence-backed list of the ways this system's **architecture** — not its
individual lines — creates security risk, and for each one: the boundary it sits on, whether it is
inherited by every application built on jZen or only affects the reference app, whether anything
today would detect it, and the change that closes it.

Your deliverable is `docs/plans/SECURITY-ARCHITECTURE-REVIEW.md`, and nothing else. No code change,
no ADR, no migration, no deploy — including for findings whose fix is a single obvious line.

**Follow the method in `docs/plans/SECURITY-ARCHITECTURE-REVIEW-PLAN.md`.** It has ten phases, the
commands for each, five named method traps, the finding template, the report skeleton, and the rules
of engagement. Read it before Phase 0 and work through it in order. This file gives you the
objective, the leads, and the standard you will be judged against.

## 2. Three things this review is not

- **It is not a re-run of the 2026-08-03 audit.** F1–F20 are closed and the closures are documented.
  Confirming one still holds is a single line in the report's "Closed" section, with the evidence.
  A review that rediscovers rate limiting, CSRF, security headers, or the database privilege split
  has failed at its first duty.
- **It is not a summary of the architecture documents.** `MANIFESTO.md`, `BLUEPRINT.md`,
  `STANDARDS.md` and `DECISIONS.md` reason about security more carefully than most codebases ever
  do. They are the *claim under review*, not the material you report back. The finding is where a
  document and the system disagree — and that class of finding has already proved the most valuable
  here once (see the predecessor's §6).
- **It is not a penetration test.** You will run no scanner against production, and you will not
  prove a finding by exploiting it. §4 is not negotiable.

## 3. What makes this review jZen's rather than generic

**If a finding would read identically against any Quarkus application, it is not this review's
output.** Five properties make jZen's posture its own, and your attention belongs on them:

1. **It is a framework.** `server/zen-*` and `client/zen_*` are libraries; `apps/<app>/` assembles
   them; ADR-026 contemplates a second product consuming jZen from a sibling checkout. Every control
   therefore has a *scope*: framework (inherited by apps that do not exist yet) or application
   (inherited by nobody). A framework-scope finding outranks an application-scope finding of equal
   severity.
2. **Its signature failure mode is silence.** `CLAUDE.md` names three mechanisms where a missing
   declaration produces no error and no signal: a module without `jandex-maven-plugin` has its
   filters and augmentors *silently do nothing*; a client package reaching Supabase directly "fails
   *silently* — the app would authenticate and every suite would still pass"; `quarkus-rest-jackson`
   must be *absent* rather than out-prioritised. Each was found the hard way. **Nobody has asked how
   many more there are.** That census is the single highest-value thing you can produce.
3. **A client-controlled header selects between two parsers.** `X-Zen-Transport` picks Protobuf or
   canonical proto3 JSON, via a `@PreMatching` filter, on a server where
   `quarkus.http.auth.proactive=true`. Two decoders reachable before resource matching is an unusual
   surface and no OWASP list covers it.
4. **There is no edge.** No CDN, no WAF, no API gateway — deliberately, and two written invariants
   depend on it (ADR-027). The application *is* the perimeter, at `--max-instances=1` with 200
   concurrency slots.
5. **The database has a second door.** The Supabase Data API reaches the same Postgres without
   passing through the application at all (ADR-036). It is the only boundary where jZen's entire
   authorization model is simply not on the path.

## 4. Rules of engagement — the three that matter most

The full set is in the plan's §4. These three are the ones habit will break:

**Never point a scanner at production.** The deployed service runs one instance with 200 slots. A
baseline scan, a directory brute-force, or an ASVS-driven fuzz run *is* a denial of service — the
exact residual risk ADR-027 accepted in writing on the understanding that nobody would spend it.
It would also be laundered through the machinery under review: the limiter would throttle you, and
`DurableLimiter` would write thousands of rows to `zen_rate_limit_counters`, leaving production data
indistinguishable from a real attack in any later investigation. **All dynamic testing runs against
a local container** (`task test:native`). Production gets **12 budgeted reads**, logged in a ledger
in the report, and no `POST`.

**Do not probe the hosted Supabase project.** Verifying ADR-036's Data API lockdown against the live
project would mean presenting the anon key to a third-party endpoint, and the owner decided on
2026-08-13 that it does not happen. `task run:supabase` runs the same PostgREST against the same
migrations and answers the architectural question — does the lockdown cover *every* table, and what
is the default for a new one — without touching live infrastructure. Write the hosted check into
"Open questions" as a command for a human. **A local result that looks bad raises the value of the
hosted check; it does not authorise it.**

**If you find something live and exploitable, stop and report it immediately.** Do not hold it until
the write-up phase, and do not confirm it against production.

## 5. The standard, the level, and the rule about versions

**Your bar is ASVS Level 2.** That is an owner decision taken on 2026-08-13, not a judgement call
left to you: jZen handles authentication credentials, personal data and an admin role. A Level 3
requirement that is obviously cheap is an *opportunity*, ranked as such and not reported as a gap. A
**Level 2** requirement that is knowingly declined is a finding with an owner decision attached, and
never a silent omission.

OWASP ASVS is your spine — the only OWASP artifact that is a checklist rather than a ranking. Layer
the surface-specific lists on top: **API Security Top 10** for the REST and WebSocket surface,
**MASVS/MASTG** for the Flutter client, **CI/CD Security Top 10** for the build path, the relevant
**Cheat Sheets** for session management, JWT, CSRF, WebSocket and CSP. The web **Top 10** is for
vocabulary only — it is a prevalence ranking, not coverage.

**Establish every version; recall none.** Fetch each document, record its version, its release date,
and the URL and date you read it. **Do not cite a requirement number from memory** — ASVS renumbered
wholesale between major versions, and a wrong requirement id is indistinguishable from a fabricated
one. If an artifact has been superseded, use the successor and say so.

Beyond OWASP, check the 2026 practices ASVS does not reach: SLSA build provenance, SBOM generation,
container signing, keyless CI→cloud authentication, digest-pinned dependencies, secret scanning with
push protection, `__Host-` cookie prefixes, `Permissions-Policy`/COOP/COEP/CORP, CSP with nonces or
Trusted Types, and whether the email-link authentication flow holds up under current OAuth 2.1
guidance.

**Coverage is a deliverable**: an ASVS chapter map, every chapter marked `pass` / `gap` /
`n/a with reason` / `not assessed`. "Not assessed" is honest and acceptable; an unmarked chapter is
not.

## 6. An ADR is a decision, not an exemption

ADR-018 (email links sign the user in via an implicit fragment flow, explicitly not PKCE), ADR-031
(RLS is Supabase-side only), ADR-035 (HSTS stops short of `includeSubDomains` and `preload`),
ADR-030 (an unverifiable session cookie means anonymous, not an error) and ADR-027 (the 200-slot
residual is accepted) are reasoned positions with the reasoning written down. That does not make
them right in 2026, and it does not exempt them.

Re-examine each against its own stated reasoning and against current guidance, then **either confirm
it with evidence or challenge the premise explicitly**. Both lazy extremes are failures: treating an
ADR as settled and skipping it, or "finding" it as though the reasoning did not exist. If a decision
should change, say so and name the ADR a successor would have to supersede. `DECISIONS.md` is
append-only (ADR-011) and you write nothing to it.

## 7. Invariants your recommendations must respect

A recommendation that violates one of these is rejected on arrival unless it engages with the
document that established it and prices the change. The full list is the plan's §7.1; these are the
ones that most often get trampled by security advice:

1. **Nothing sits between the client and Cloud Run.** ADR-027 priced Cloud Armor (~$25–30/mo floor,
   rejected) and deferred the Cloudflare free tier **on invariants, not price** — two written
   constraints depend on there being no edge. "Put a WAF in front of it" is not a finding; it is the
   suggestion that document already rejected.
2. **The client talks to exactly one server, and it is jZen's.** No client package may call Supabase
   or any third party directly.
3. **Client config is compile-time.** "Fetch the config at startup" is unavailable — and note the
   security consequence, which cuts the other way: anything configured is *in the shipped bundle*.
4. **`--max-instances=1` makes in-process state correct; `--min-instances=0` makes in-process time
   invalid.** Both are load-bearing for the rate limiter and the scheduler.
5. **Flyway is the single migration authority**, and a new table ships its Data API lockdown in the
   same change (ADR-036).
6. **No gate swallows a failure, and no gate may pass having checked nothing** (ADR-034).
7. **jZen is proto-first**: no server-side `quarkus-rest-jackson`.

## 8. Leads

**These are unverified hypotheses, not findings.** They come from a shallow pass over the repository
on 2026-08-13 and exist so you do not spend a day rediscovering the obvious. Every one needs
confirming or refuting with evidence, and **a refuted lead is a result worth reporting** — put it in
"Closed", with what you checked. Do not let this list bound the review; the best finding will
probably not be on it.

| # | Lead | What would refute it |
|---|---|---|
| L1 | **The silent-no-op class has more members than the three `CLAUDE.md` names.** Enumerate every mechanism where a missing declaration yields no error and no signal. | A complete census showing the three are the only ones — which is itself the deliverable. |
| L2 | **Every security test lives in `apps/zen_demo/zen_demo_server`** (`SecurityHeadersTest`, `CsrfWiringTest`, `RateLimitWiringTest`, `DatabasePrivilegeTest`, …). Necessarily so — a `@QuarkusTest` needs an assembled app. But it means the framework libraries carry no proof of their own controls, and a second app inherits the code without inheriting the tests. | Framework-level tests that fail if a library's control is not wired. |
| L3 | **`task audit` may not run automatically anywhere.** ADR-034 says it "is run in CI on a schedule and before a release"; `ci.yml` did not appear to invoke it. A gate that has already caught one HIGH and is never triggered is not a gate. | Finding it in a workflow, a schedule, or a documented release checklist that someone follows. |
| L4 | **CI hardening is unreviewed.** No `permissions:` block was visible in `ci.yml`; third-party actions appear pinned by tag rather than digest; `dart pub global activate` and `corepack` fetch executable code at build time without a checksum. | Reading the workflow properly and finding the controls elsewhere. |
| L5 | **No SBOM, no image signing, no provenance attestation**, and the deploy's authentication to GCP (long-lived key vs workload identity federation) is unestablished. | Any of them existing. "SLSA level 0, stated honestly" is a legitimate finding. |
| L6 | **`zen_secure_store`'s security property may not hold on web.** The refresh token sits in Keychain/Keystore with `first_unlock_this_device` on mobile; the web target has no Keychain. If the web path degrades silently, that is L1's shape on the client side. | The web implementation refusing to store, or storing nothing sensitive. |
| L7 | **Secrets may be reachable in the shipped web bundle.** Compile-time config means every `String.fromEnvironment` value is in the artifact. `SUPABASE_KEY` must not be — verify against a built bundle, do not assume. | A clean grep over `task build:web` output, recorded. |
| L8 | **The CSRF exemption list's *default* is the architectural question.** Login and register are exempt by necessity. Does a newly added endpoint default to protected or to exempt? | A default-deny mechanism with the exemptions enumerated in one place. |
| L9 | **WebSocket authorization is a handshake-time check.** What happens to an open connection on logout, on a role change, or on token expiry? The connection cap is per-instance — valid at `--max-instances=1`, so say what breaks if that changes. | Per-message or periodic re-authorization. |
| L10 | **The Data API lockdown may cover only `users`.** `R__identity_data_api_lockdown.sql` lives in `zen-identity`; `zen_rate_limit_counters` and the `zen-jobs` tables come from other modules with their own migration version bands. ADR-036's rule is *every* table. | Verifying the lockdown applies to every table, including ones added after it. |
| L11 | **`RoleAugmentor` reads the role per request** — correct for revocation latency, but establish the failure mode when the database is unreachable, and confirm it still yields an identity *without* a role rather than a cached or default one. | The fail-closed path, tested. |
| L12 | **`zen-email`, `zen-jobs` and `zen-ratelimit` did not exist at the last audit** in their current form. They are new attack surface reviewed only by their own authors — including the constant-time trigger secret, the counter tables, and outbound mail. | A clean review of each; they may well be fine. |
| L13 | **`verify:boundaries` gained `.ts`/`.tsx` coverage but may still have holes**: platform channels, Kotlin/Swift sources, `pubspec.yaml` dependency declarations, generated code, transitive Dart packages that bundle their own HTTP client. | Reading `scripts/verify-boundaries.py` and finding the coverage complete — or finding the hole. |
| L14 | **The admin panel holds the highest privilege in the system** and imports the scaffold *from source* via a TypeScript alias rather than a pnpm edge (ADR-005). Its auth provider, session storage, XSS surface, and whether its bundle gets the same security headers as the app's are all unreviewed. | A review of it. |
| L15 | **The email-link flow (ADR-018/019) is the account-takeover primitive.** Fragment-borne tokens, link reuse, single-use enforcement, referrer leakage, and what an email-scanning or link-prefetching intermediary sees. `RedirectTargets`' exact-match rule was verified once and the allowlist source may have changed since. | Evidence that each concern is handled, or a reasoned confirmation of ADR-018 on current guidance. |

## 9. What a finding must contain

The template is in the plan's §7 and you must use it whole. Four fields carry most of the review's
value and are the ones a generic report omits:

- **Scope** — `framework` (every app inherits it) / `application` (zen_demo only) / `pipeline`.
- **Silent?** — does *anything* today detect or report this: a test, a gate, a log line? Yes or no.
- **Evidence** — the command you ran and what it produced, or the code path you traced. **Not a
  citation of a document.**
- **What the fix costs** — what gets worse, or which invariant is touched. "Nothing" is valid only
  if you looked.

**Ranking:** `(active exploitability × impact) / remediation cost`, then framework scope breaks ties
upward. CVSS vectors are optional and never replace that ranking — a base score knows nothing about
single-instance deployment, one tenancy, or which control is inherited by applications that do not
exist yet, and those are the facts that order this list.

**Rank hard.** Fifteen findings with mechanisms beat sixty with severities. "Insufficient input
validation, HIGH" is noise: name the input, the path, and what reaches the other end.

## 10. Deliverable

`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md`, in the skeleton the plan's §8 specifies. Its Method
block must state, plainly: the ASVS version and level, every other artifact with its version and the
date you read it, the production request ledger, every tool with its name and version and
configuration, and **what you did not assess**.

`git status --porcelain` at the end shows that one file and nothing else.

## 11. What would make this review worthless

- Re-finding F1–F20.
- Restating `STANDARDS.md`, `BLUEPRINT.md` or an ADR as though it were a discovery.
- A generic OWASP checklist with jZen's file names pasted in.
- Severity without a mechanism.
- Citing a requirement number you did not look up.
- Recommending a WAF, an API gateway, a CDN, an edge, Redis, Kubernetes, or a second orchestrator
  without engaging with the ADR that already rejected or deferred it and the price it named.
- Touching production with anything other than a read.
- Fixing something instead of reporting it.
- A long report.
