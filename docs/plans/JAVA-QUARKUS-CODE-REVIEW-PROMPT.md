# Prompt: a multi-perspective code review of jZen's Java/Quarkus code

This file is **the brief you hand to the reviewing model**, not the review. Everything below the
`---` is the prompt; paste it whole, or point the agent at this file. The material above the `---`
is for the person commissioning it.

**Why this exists.** jZen's backend (`server/zen-*` and each `apps/<app>/<app>_server`) is reviewed
piecemeal today — a PR diff here, a `/code-review` pass there. Nothing looks at the Java/Quarkus
surface as a whole, from more than one angle, on a schedule. This prompt is that pass: it names the
perspectives explicitly (correctness, Quarkus/CDI idiom, the transport seam's invariants, security,
vulnerability testing against OWASP references, the GCP/Supabase integration code specifically,
concurrency, performance, testing, contract-first hygiene, dependency hygiene) so a reviewer does
not collapse them into one generic "looks fine" sweep.

**Relationship to the architecture security review.**
[`SECURITY-ARCHITECTURE-REVIEW-PROMPT.md`](SECURITY-ARCHITECTURE-REVIEW-PROMPT.md) already covers
jZen's security **at the level of a boundary** — ASVS L2, framework vs. application scope, the
silent-failure census. This prompt's security lens (§3.4) and its dedicated OWASP vulnerability
pass (§3a) work **at the level of a file and a line**: does *this* endpoint validate *this* input,
does *this* query concatenate a string, does *this* dependency have a published CVE. Run this review
first if you have not run the architectural one recently — code-level findings here often become the
evidence an architectural finding needed. Do not duplicate the architectural review's boundary-level
findings here; cite them instead if code you're reading is the mechanism behind one.

**Scope note for the commissioner.** This is a *code* review — it reads `server/` and
`apps/*/​*_server`, not the architecture documents in the abstract. Where a file appears to violate a
written rule in `CLAUDE.md` / `STANDARDS.md` / `DECISIONS.md`, that is exactly the finding to report;
the reviewer is not asked to re-derive or second-guess the rules themselves. Unlike
[`SECURITY-ARCHITECTURE-REVIEW-PROMPT.md`](SECURITY-ARCHITECTURE-REVIEW-PROMPT.md), this review does
not require a dedicated companion plan — the phases and checklist live in this one file.

**This review produces no code.** Its deliverable is a report. Fixing findings is a separate,
later pass — possibly `/code-review --fix` or a follow-up task against specific findings, run by a
human decision, not by this reviewer on its own initiative.

---

# You are conducting a multi-perspective code review of jZen's Java/Quarkus code

## 1. Your objective

Read every file under `server/` (the framework libraries: `zen-core`, `zen-transport`,
`zen-identity`, `zen-email`, `zen-jobs`, `zen-ratelimit`, `zen-proto`) and every
`apps/<app>/<app>_server` (today only `apps/zen_demo/zen_demo_server`), and produce a ranked,
evidence-backed list of defects and risks, each one tagged with **which perspective surfaced it**
(§3) and **which module it belongs to** (framework code inherited by every app, vs. application code
scoped to `zen_demo`).

Your deliverable is `docs/plans/JAVA-QUARKUS-CODE-REVIEW.md`. `git status --porcelain` at the end
shows that one file and nothing else — you read code, you do not change it.

## 2. What makes this jZen's review, not a generic Java review

A finding that would read identically against any Quarkus service is not wrong, but it is not
this review's point. Ground every finding you can in what is specific here:

- **The framework/app split.** A defect in `server/zen-*` is inherited by every application built on
  jZen, including ones that do not exist yet. The same class of defect in `apps/zen_demo` affects
  one app. Rank framework-scope findings above application-scope findings of equal severity, and say
  explicitly which scope each finding is.
- **The dual-mode transport seam is unusual and load-bearing.** `X-Zen-Transport` picks the response
  codec (JSON or Protobuf) via a `@PreMatching` `ZenTransportFilter` that rewrites `Accept`; the
  request body's parser is chosen independently by the client's own `Content-Type`. MapStruct maps
  entity ⇄ proto. A bug here (wrong precedence, a codec falling back silently, a mapper dropping a
  field) is invisible to a reviewer who does not already know the negotiation order in `CLAUDE.md`.
- **Two silent-failure traps are named and load-bearing:** a library module missing
  `jandex-maven-plugin` has its CDI beans and JAX-RS providers **silently** not discovered by
  Quarkus — no error, no log; and `quarkus-rest-jackson` must be **absent**, not merely
  out-prioritized, or its writer claims `application/json` ahead of `ProtoJsonMessageBodyWriter` and
  serializes proto builder internals into 500s. Check every module's `pom.xml` against both.
- **Auth and role resolution are deliberately not from the JWT.** `RoleAugmentor` reads the role from
  the `users` table per request; the JWT is verified against JWKS but does not carry the role a
  resource trusts. A shortcut that reads a role from the token instead is a correctness *and*
  security regression, not a style nit.
- **Single-instance deployment makes some patterns correct that would be wrong elsewhere.**
  `--max-instances=1` means in-process rate limiting, in-memory caches, and login counters are valid
  by construction. Do not flag them as "won't scale horizontally" — that is out of scope by design.
  Do flag anything that assumes multi-instance semantics it doesn't have (e.g., something that
  *should* be externalized because the app now reads `--max-instances` above 1 somewhere, or
  in-memory state with no eviction that would leak inside a single long-lived instance).
- **`ZenResult`/`ZenError`/`ZenStatus` (`zen-core`) is the one error-handling vocabulary.** A resource
  or service that throws an unchecked exception across a boundary the framework expects to carry a
  `ZenResult`, or that swallows a failure into a null/empty return, is a "nothing swallows a failure"
  violation (`CLAUDE.md`, STANDARDS.md) — treat this as a first-class category, not a minor style
  point.
- **Panache is active-record; there are no repository classes by design.** Do not recommend
  reintroducing a repository layer as a "clean architecture" improvement — that contradicts a
  deliberate choice. Flag it only if a `PanacheEntity` genuinely leaks persistence details across a
  boundary that isn't supposed to know about Hibernate (e.g., into a proto mapper or a REST layer
  in a way that breaks the contract-first flow).

## 3. Perspectives — review from each of these explicitly

Work through the same code from each of these seven lenses. A file can and should generate findings
from more than one lens. Do not merge them into one pass and lose the tagging.

1. **Correctness.** Logic errors, off-by-ones, null-handling, incorrect MapStruct field mappings,
   wrong HTTP status codes, `ZenResult` short-circuits that drop a failure, transaction boundaries
   that don't match the intended atomicity (`@Transactional` scope vs. what the method actually
   needs), timezone/locale handling against `ZenLocales`/`AcceptLanguage`.
2. **Quarkus and CDI idiom.** Bean scope mismatches (`@ApplicationScoped` holding per-request state,
   `@RequestScoped` where a singleton was intended), constructor injection vs. field injection
   consistency, `@Provider`/`@PreMatching` ordering, whether `jandex.idx` is actually produced for
   every module that needs it, correct use of `quarkus-websockets-next` for the WS surface, whether
   MicroProfile config is read at the right layer (server = runtime config, by design — flag Dart
   client code doing the opposite, but that's `client/`, not this review's scope).
3. **The transport seam's own invariants.** Every resource returns `jakarta.ws.rs.core.Response`
   with `@APIResponse(@Schema(ref=...))`, never a bare proto return type; every module contributing
   beans/providers has Jandex; no `quarkus-rest-jackson` anywhere server-side; `X-Zen-Transport` is
   only a response-codec signal, never used to steer request parsing.
4. **Security.** Auth checks present on every mutating endpoint that needs one, role checks correct
   (`RoleAugmentor`-sourced role, not JWT-sourced), CSRF exemption list correctness (default should be
   protected, not exempt), input validation at system boundaries (REST payloads, not internal calls),
   SQL/JPQL injection via any hand-built query, secrets never logged, cookie flags
   (`httpOnly`/`Secure`/`SameSite`) on anything setting `zen_access_token`-like cookies, timing-safe
   comparison for any secret/token comparison (e.g., in `zen-jobs`' trigger secret). Treat this lens
   as the entry point into the dedicated OWASP vulnerability pass in §3a — every finding here should
   end up mapped to an OWASP category there, not left as a standalone note.
5. **Concurrency and state.** Shared mutable state in `@ApplicationScoped` beans without
   synchronization, races in in-memory counters (`zen-ratelimit`), non-atomic check-then-act on
   Panache entities, blocking calls on a Vert.x event-loop thread not marked as such (missing
   `@Blocking` or a wrong `@RunOnVirtualThread` assumption), correctness of any scheduled/`zen-jobs`
   task under `--min-instances=0` (a job assuming continuous wall-clock uptime is invalid here).
6. **Performance.** N+1 queries from Panache relationships, unnecessary eager fetching, unbounded
   collections loaded into memory, redundant proto (de)serialization, missing indexes implied by a
   query pattern (check against Flyway migrations in `zen-identity/db/migration/`), allocation in hot
   paths of the transport filters/writers.
7. **Testing and maintainability.** `@QuarkusTest` coverage gaps (a framework library's control that
   has no test anywhere, since tests only live in the assembled app module), test names/asserts that
   don't match what they claim to check, dead code, duplicated logic across `zen-*` modules that
   should be shared, naming that doesn't match the bare-`zen` namespace (`zen.core`, `zen.transport`,
   `zen.demo` — not `dev.zen`), Javadoc/comments that explain *what* instead of *why* or that have
   rotted relative to the code.

Add an eighth, cross-cutting lens as you go rather than as a separate pass:

8. **Contract-first hygiene.** Any hand-edited file under a generated path (Java DTOs from
   `zen-proto`, anything `protoc` produces), any REST shape defined by MapStruct/DTO first, then
   retrofitted into OpenAPI, rather than SmallRye annotations being canonical for the REST surface,
   any drift between `META-INF/openapi.yaml` and what a resource actually returns.

## 3a. Security & vulnerability testing (OWASP)

This is not a ninth item in the list above — it's where every §3.4 security finding gets mapped,
tested, and given a standard reference, so severity isn't a guess.

**Standards to use, and how:**

- **OWASP Top 10 (2021)** — vocabulary and triage only. Tag each finding with its category
  (`A01 Broken Access Control`, `A03 Injection`, `A05 Security Misconfiguration`, `A07
  Identification & Authentication Failures`, `A08 Software & Data Integrity Failures`, `A09
  Security Logging & Monitoring Failures`, etc.). It's a prevalence ranking, not a checklist — don't
  stop at "no A03 found" without having actually traced every query/deserialization path.
- **OWASP API Security Top 10 (2023)** — jZen's backend is REST + one WebSocket endpoint, so this is
  the more load-bearing list. Walk every resource in `zen-identity`'s `AuthResource`/
  `AdminUserResource` and every `apps/zen_demo/zen_demo_server` resource against it explicitly:
  `API1` Broken Object Level Authorization (does a resource check the caller owns the `id` path
  param it's given, not just that they're authenticated?), `API2` Broken Authentication, `API3`
  Broken Object Property Level Authorization (does a DTO/proto mapper expose a field — e.g. a role
  or an internal id — that the caller shouldn't set or see?), `API4` Unrestricted Resource
  Consumption (pairs with `zen-ratelimit` — is every mutating/expensive endpoint actually covered by
  it?), `API5` Broken Function Level Authorization, `API8` Security Misconfiguration, `API9`
  Improper Inventory Management (an endpoint reachable but undocumented in `openapi.yaml`).
- **OWASP ASVS** (current major version — fetch and record which) as the code-level checklist for
  input validation, session/cookie handling, cryptography (JWKS verification, timing-safe secret
  comparison), error handling, and logging. You are not doing the full architectural ASVS chapter
  map here (that's the companion review's job) — pull only the V-chapters that are code-verifiable
  from source: input validation, authentication, session management, error handling/logging,
  cryptography at rest/in transit.
- **CWE** as a secondary tag where it sharpens a finding beyond its OWASP category (e.g., CWE-89 SQL
  Injection, CWE-352 CSRF, CWE-208 timing side-channel) — optional, never a substitute for tracing
  the actual code path.

**Static tooling — run what's available, name what you couldn't run:**

- `task audit` (if it exists and you're allowed to hit the network) — the framework's own dependency
  vulnerability gate over every shipped Java (and TypeScript) dependency against published
  advisories. Run it and report its output verbatim; do not re-derive CVEs by hand for dependencies
  it already covers.
- A Java security-focused static analyzer if one is installed or quick to add in a throwaway,
  uncommitted local run — SpotBugs with the `find-sec-bugs` plugin, or `semgrep --config
  p/owasp-top-ten --config p/java` against `server/` and `apps/*/​*_server`. If you can't run one
  (no network, no time budget), say so explicitly in the report rather than silently skipping this
  category — an unrun tool is a gap, not a pass.
- Grep-based checks that need no tool at all: string-concatenated JPQL/SQL (`"SELECT ... " + `),
  `Runtime.exec`/`ProcessBuilder` with unsanitized input, deserialization of untrusted data outside
  the proto pipeline, hard-coded secrets or credentials, `printStackTrace`/raw exception messages
  reaching an HTTP response body.

**Dynamic/vulnerability testing — local only, never production:**

Any hypothesis from the static pass that needs confirming against a running server is tested against
`task run:demo` or a local `@QuarkusTest`/`RestAssured` test — **never** the deployed Cloud Run
instance. This mirrors the architectural review's rule of engagement and for the same reason: a
single-instance, 200-concurrency-slot production service does not tolerate probing, and anything you
send it becomes indistinguishable from a real attack in `zen-ratelimit`'s own counters. If a finding
would benefit from a proof-of-concept request (e.g., confirming BOLA by requesting another user's
resource with a valid-but-wrong-owner token), write it as a `curl`/RestAssured snippet against
`localhost` and include the actual local response in the finding's evidence — a hypothesis you didn't
run is a lead, not a finding.

**If you find something live and exploitable in production-reachable code, stop and report it
immediately** rather than holding it for the final write-up.

## 3b. GCP & Supabase integration security (from the Java/Quarkus side)

jZen's only two external systems are GCP Cloud Run (where the app runs) and Supabase (auth + the
database it's fronted by). Both are reached from Java code, and both have their own class of
mistake that a generic OWASP pass will not surface. Review the *code and config that touch them*,
not the cloud consoles themselves — this is still a code review.

**Supabase, via `zen-identity`:**

- **`SupabaseAuthClient`** (`server/zen-identity/src/main/java/zen/identity/auth/`) is the only
  code path that calls Supabase. Confirm nothing else in the codebase reaches it directly — a
  second hand-rolled HTTP call to Supabase from elsewhere is both a duplication finding and a
  security finding (an unreviewed second door with its own fault-tolerance/timeout posture, or none).
- **Fault tolerance is part of the security posture here, not just reliability.** Each method
  carries `@CircuitBreaker`/`@Retry`/`@Timeout` deliberately tuned so a genuine 4xx (bad credentials)
  aborts immediately while a 5xx/timeout trips the breaker — check that every *new* method added to
  this interface preserves that split rather than retrying a real auth failure (which would look
  like a credential-stuffing amplifier from jZen's own server) or blocking indefinitely on a
  Supabase outage (which, at `--max-instances=1`, exhausts request-handling capacity for every
  other user).
- **The `apikey` header carries `supabase.key`.** Confirm this resolves to the anon key, not the
  service-role key, for anything this client does on a user's behalf; a service-role key on a
  client reachable per-request would defeat RLS for every table the moment one endpoint using this
  client is compromised. Trace where `supabase.key` is populated (`application.properties` →
  environment/secret at deploy) and confirm it isn't logged — `@ClientHeaderParam` values can end up
  in Quarkus's REST client debug logging if that's ever enabled.
- **The GoTrue `/user` call is the *only* valid way to check a token jZen didn't mint itself**
  (per its own Javadoc) — confirm no code path shortcuts this with a local-only JWKS check for
  email-link/recovery tokens, which would accept a token Supabase has already invalidated.
- **Config classification.** `fcff867` moved eight public config values out of secrets — confirm
  the classification is still correct going forward: `SUPABASE_URL` and any project ref are public;
  `SUPABASE_KEY` (anon) and anything resembling a service-role key are not. A new config value added
  since should be checked against this split, not assumed safe because it "looks like a URL."
- **RLS is Supabase-side only (ADR-031)** — the Java code must never assume a query is
  authorization-safe merely because it goes through Supabase; anything querying Postgres directly
  from `zen-identity`/Panache still needs its own authorization check in Java, since RLS does not
  apply to the application's own DB connection.

**GCP Cloud Run, from the code's point of view:**

- **Runtime config is deliberately not compile-time on the server** (unlike the Dart client) — trace
  every `@ConfigProperty`/MicroProfile-config-backed value the app reads at startup and confirm each
  one that should come from Secret Manager/Cloud Run's secret-binding mechanism isn't instead a
  plain env var holding a real secret, and vice versa (a public value shouldn't cost a Secret
  Manager binding it doesn't need — see the `fcff867` precedent above).
- **No service-account key file should ever be bundled into the container image or committed** —
  grep for `.json` credential files, `GOOGLE_APPLICATION_CREDENTIALS` pointing at a shipped path, or
  any `GoogleCredentials.fromStream(...)` reading a packaged file rather than Application Default
  Credentials / the metadata server. Cloud Run should authenticate as its attached service account
  implicitly.
- **Outbound HTTP clients (Supabase or otherwise) need sane timeouts** given `--concurrency=200` on
  a single instance — an unbounded or over-long timeout on any outbound call is a self-inflicted
  denial-of-service path, not just a performance nit; cross-reference with §3.5 (Performance) and
  §3.6 (Concurrency).
- **Logging must not leak into a place GCP-side tooling would expose more broadly than intended** —
  check that no request/response body logged for debugging (Supabase calls, JWT contents, cookie
  values) survives at a log level Cloud Run's default logging sink would capture in production.

**Dynamic testing here follows the same rule as §3a: local only.** Confirm behavior against
`task run:supabase`/`task run:demo`'s local Supabase stack (same PostgREST, same migrations). Do
not authenticate to or probe the hosted Supabase project, and do not run anything against the
deployed Cloud Run service — both are explicitly out of bounds per
`SECURITY-ARCHITECTURE-REVIEW-PROMPT.md`'s rules of engagement, which this review inherits rather
than re-litigates.

## 4. Method

1. **Inventory.** List every module under `server/` and every `apps/*/​*_server`, with its `pom.xml`
   dependencies and whether it declares `jandex-maven-plugin`. This is your map for §3.3 and §2.
2. **Read module by module**, framework libraries first (`zen-core` → `zen-transport` →
   `zen-identity` → `zen-email`/`zen-jobs`/`zen-ratelimit` → `zen-proto`), then the app server(s).
   Reading in dependency order means you already know a lower module's contracts before judging
   whether a higher one honors them.
3. **For each file, sweep all eight lenses from §3** before moving on — do not do a correctness-only
   pass over the whole tree and then a security-only pass over the whole tree; that's how the
   transport-seam-specific checks (§2) get skipped the second time around.
4. **Cross-reference `STANDARDS.md` "Backend multi-module rules"** and the relevant `DECISIONS.md`
   ADRs for anything that looks like a deliberate but unusual choice before flagging it as a defect —
   the framework/app split, active-record over repositories, and runtime config are all intentional.
5. **Run what's cheap to run.** `cd server && ./mvnw -B -q install -DskipTests` to confirm everything
   still compiles before you start reasoning about it; grep for `quarkus-rest-jackson` across every
   `pom.xml`; grep for `jandex-maven-plugin` presence per module; `task test:apps:server` if you want
   to confirm current test-suite status as a baseline (not required, but cheap context).
6. **Run the §3a security/vulnerability tooling** — `task audit`, a static security analyzer if
   available, and the grep-based injection/secret checks — as their own step, not an afterthought
   after the reading pass. Record what ran, its version, and what you could not run.
7. **Trace the Supabase and GCP integration points per §3b** — `SupabaseAuthClient`, every
   `@ConfigProperty` the server reads, and how each resolves at deploy — as their own step; this is
   easy to fold silently into the general security pass and lose the GCP/Supabase-specific checks.
8. **Confirm any exploitability hypothesis locally**, per §3a/§3b's dynamic-testing rule — `task
   run:demo` / `task run:supabase` or a targeted `@QuarkusTest`, never the deployed instance or the
   hosted Supabase project.
9. **Do not run `task deploy:*` and do not touch production or the hosted Supabase project** — every
   dynamic check in this review runs against a local stack.

## 5. What a finding must contain

- **Perspective(s)** — which of the eight lenses in §3 surfaced it (a finding can name more than
  one).
- **OWASP/CWE tag** — required for any §3.4/§3a security finding: the OWASP Top 10 and/or API
  Security Top 10 category, plus a CWE id where it sharpens the finding. Not applicable to a pure
  correctness/performance/style finding — leave it off those rather than forcing a tag.
- **Scope** — `framework` (inherited by every app) or `application` (`zen_demo` only).
- **Location** — file and line/method.
- **Failure scenario** — concrete input/state that triggers the defect, or the concrete cost if it's
  a maintainability/design finding rather than a bug.
- **Evidence** — the code path you traced, or the command output. Not a citation of a document as if
  that alone were proof.
- **Fix** — what changes, and what it costs (touches a migration, a public API, an ADR-protected
  invariant, etc.). "Nothing" is valid only if you checked.

**Ranking:** severity × how many perspectives independently flagged the same code, framework scope
breaks ties upward. Group findings by module, ranked within each module, with an overall top-10
across the whole review at the top of the report.

## 6. What would make this review worthless

- Reporting the same finding once per lens as if they were independent (merge and tag instead).
- Flagging deliberate architecture (active-record Panache, runtime server config, single-instance
  deployment, the framework/app split itself) as a defect without engaging with the ADR/doc that
  chose it.
- A generic Java style checklist with no jZen-specific finding at all.
- Recommending a repository layer, a second ORM, a service mesh, or horizontal-scaling machinery
  that `--max-instances=1` makes moot.
- Fixing something instead of reporting it.
- Skipping the transport-seam invariants (§2, §3.3) because they require reading `CLAUDE.md` first.
- Naming OWASP Top 10 categories in the abstract without tracing an actual code path (§3a).
- Sending any request — proof-of-concept or otherwise — to the deployed production instance or the
  hosted Supabase project (§3b).
- Treating "it calls Supabase" or "it reads a Cloud Run env var" as inherently safe without tracing
  what key/value actually flows through it (§3b).
- A long report where a ranked top-10 would have said as much.
