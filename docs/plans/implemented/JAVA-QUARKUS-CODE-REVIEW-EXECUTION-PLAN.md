# Execution plan: Java/Quarkus code review remediation

**Source:** `docs/plans/JAVA-QUARKUS-CODE-REVIEW.md` (2026-09-14). 23 findings (F1–F23) across
`zen-identity`, `zen-transport`, `zen-jobs`, `zen-ratelimit`, and `apps/zen_demo/zen_demo_server`.
**Out of scope:** boundary/architectural findings live in
`docs/plans/SECURITY-ARCHITECTURE-REVIEW-PROMPT.md` — not restated or scheduled here.

This plan turns the review into ordered, independently-landable units of work. Each unit names its
branch, the files it touches, the steps, the tests to add or extend, and whether it trips
`task verify:contracts`, needs an ADR, or needs a `DECISIONS.md` entry. Nothing here is executed
yet — this is the plan to work from, one branch at a time, with `task test` green before each PR.

## Ground rules for every unit below

- One finding (or tightly-coupled pair) per branch, per `CLAUDE.md`: `fix/`, `security/`, or
  `docs/` prefix, never onto `main`.
- `task test` (which includes `test:e2e`) must pass before a PR is opened. `task test:apps:server`
  alone is not sufficient for anything touching `zen-transport`, `zen-ratelimit`, or the WebSocket
  surface, because wiring tests live in the app module.
- Any `.proto` change → run the `sync-contracts` loop and let `task verify:contracts` catch drift;
  do not hand-edit generated Dart/TS output.
- Any change to a rule stated in `STANDARDS.md`/`BLUEPRINT.md` gets a one-line doc update in the
  same PR; any change that reverses or supersedes a prior architectural decision gets a
  `DECISIONS.md` entry via the `add-adr` skill, not a silent edit to an accepted ADR.
- `task audit` must be green (or carry an argued suppression) before anything else merges, since a
  known-red gate stops being read — this is why F2 is Phase 0, not last.

---

## Phase 0 — Unblock the gate (do first, blocks nothing else technically but must not be deferred)

### F2 — `task audit` is red (Critical Netty advisory)

- **Branch:** `security/pin-netty-bom`
- **Files:** `server/pom.xml` (new `netty-bom` `<dependencyManagement>` override, styled after the
  existing `jackson-bom` block and its "remove once the platform catches up" comment).
- **Steps:**
  1. Check whether a newer Quarkus 3.38.x patch release already ships a fixed Netty; if so, bump
     `quarkus.platform.version` instead of pinning — preferred per the review.
  2. If no patched platform release exists yet, add the `netty-bom` override pinning
     `netty-codec-http` and `netty-handler` past the three advisories (GHSA-8c42-7qj2-3j46,
     GHSA-c4c3-7fpv-j4q5, GHSA-fccg-mwvh-qqg4).
  3. Only if neither is possible: write the three lines in `scripts/audit-suppressions.txt`, each
     with the reachability argument from the review (no server-side TLS termination; Quarkus uses
     Vert.x CORS, not Netty's `CorsHandler`) — the suppression file's format exists to force this
     argument, not to skip it.
  4. Run `task test` in full (native-image-adjacent dependency bump — watch for transitive break).
- **Tests:** no new tests; `task audit` itself is the gate. Re-run `task build` to confirm no
  transitive API break from the version bump.
- **verify:contracts:** no.
- **ADR:** no.
- **Effort:** S (version bump path) or M (suppression path, since the reachability argument must be
  written carefully).
- **Depends on:** nothing. **Blocks:** nothing directly, but should land before other PRs pile up
  behind a red gate.

---

## Phase 1 — High-severity, contained fixes (independent, can be parallelized across sessions)

### F1 — Supabase 5xx misclassified as 401, skips breaker and retry

- **Branch:** `fix/supabase-5xx-classification`
- **Files:** `server/zen-identity/src/main/java/zen/identity/auth/SupabaseAuthClient.java`,
  `server/zen-core/.../ZenStatus.java` (new 503 constant), `zen-identity/.../IdentityService.java`
  (`classifySupabaseError` / `call`).
- **Steps:**
  1. Add a `@ClientExceptionMapper` (or registered `ResponseExceptionMapper`) on
     `SupabaseAuthClient` that throws a new `SupabaseUnavailableException extends RuntimeException`
     for `status >= 500`, leaving `WebApplicationException` for 4xx.
  2. Update each method's `@CircuitBreaker(skipOn=...)`/`@Retry(abortOn=...)` so the new exception
     type is *not* skipped/aborted — i.e. 5xx now trips the breaker and is retried, exactly as the
     existing javadoc claims.
  3. Add a `ZenStatus` constant for 503 (it's documented as an extendable interface — one-line
     addition, no proto change since it's a Java-side status, not a wire enum — verify this
     assumption against `ZenStatus`'s actual shape before committing to "no proto change").
  4. In `IdentityService#call`, add a branch mapping `SupabaseUnavailableException` to a
     503-carrying `AuthException` instead of falling through to the generic 401.
- **Tests:** extend `IdentityServiceTest` with a case that stubs a `Response` carrying a 503 (not
  just `doThrow(new IllegalStateException(...))` as today) and asserts the breaker records a
  failure and the caller sees 503, not 401.
- **verify:contracts:** only if `ZenStatus` turns out to be proto-backed — check first.
- **ADR:** no — this restores stated intent (ADR-007's fault-tolerance design), doesn't change it.
- **Effort:** M.
- **Depends on:** nothing. **Note:** touches the same file (`SupabaseAuthClient`) as F11 —
  sequence F1 before F11 or expect a rebase.

### F4 — No catch-all `ExceptionMapper`; unmapped throwables break the `ZenError` contract

- **Branch:** `fix/catch-all-exception-mapper`
- **Files:** new `server/zen-transport/src/main/java/zen/transport/ZenExceptionMapper.java`;
  `server/zen-identity/.../user/AdminUserResource.java` (input validation at the boundary).
- **Steps:**
  1. Add `ZenExceptionMapper implements ExceptionMapper<Throwable>` in `zen-transport`, at a
     `@Priority` below `AuthExceptionMapper` and `InvalidBodyExceptionMapper` (JAX-RS picks the
     most specific mapper, but pin the priority explicitly so this is not "probably fine").
  2. It logs the exception server-side with stack trace, returns `ZenError` with a **fixed** code
     (`internal_error`) and fixed message — never `exception.getMessage()`.
  3. In `AdminUserResource`, catch the three concrete triggers (`range`/`sort` JSON parse failures,
     unknown `role` in `filter` or in `PUT`) and return `Response.status(400)` with a typed
     `ZenError` code, following the existing `notFound(id)` pattern.
- **Tests:** app-module test asserting `ZenExceptionMapper` does **not** shadow `AuthException` or
  `InvalidProtocolBufferException` (the review explicitly flags this as the risk to guard). New
  tests in `AdminUserResourceTest` for each of the four malformed-input cases now returning 400
  with a `ZenError` body instead of a bare 500.
- **verify:contracts:** no (no proto change — `ZenError` already exists).
- **ADR:** no — implements a rule STANDARDS already states.
- **Effort:** M.
- **Depends on:** nothing directly, but **F23 folds into this** (do them in the same PR or as an
  immediate follow-up, since F23's fix is "delete the hand-rolled check once `@Authenticated`
  produces a `ZenError` via this mapper").
- **Unblocks:** F8's and F23's clean fixes per the review's own ordering (§8).

### F5 — `RateLimitFilter`/`CsrfFilter` ordering is implementation-defined

- **Branch:** `fix/filter-priority-ordering`
- **Files:** `server/zen-ratelimit/.../RateLimitFilter.java`,
  `server/zen-identity/.../auth/CsrfFilter.java`; `docs/architecture/STANDARDS.md` (one sentence
  under "Backend multi-module rules" documenting the cross-module ordering contract, beside the
  Jandex rule).
- **Steps:**
  1. Add explicit `@Priority` — `RateLimitFilter` strictly earlier (e.g.
     `Priorities.AUTHENTICATION - 100`), `CsrfFilter` at `Priorities.AUTHORIZATION`.
  2. Add an app-module test: an authenticated request with a bad/missing CSRF token must still be
     counted against the rate limit (i.e. `RateLimitFilter` runs first and charges it before
     `CsrfFilter` aborts with 403).
  3. Add the STANDARDS sentence stating this is a cross-module invariant, same class as Jandex.
- **Tests:** new test alongside `RateLimitEnforcementTest`/`CsrfWiringTest` proving the order on an
  *authenticated* path (the existing `RateLimitEnforcementTest` only proves it on an anonymous
  path, which doesn't exercise the CSRF interaction).
- **verify:contracts:** no.
- **ADR:** no.
- **Effort:** S.
- **Depends on:** nothing.

### F6 — No `Vary` header; `/api/` has no explicit `Cache-Control`

- **Branch:** `fix/vary-and-no-store-headers`
- **Files:** `server/zen-transport/.../ZenTransportResponseFilter.java`;
  `docs/architecture/STANDARDS.md` or a javadoc note on `SecurityHeaders`/`StaticCacheHeaders`
  explaining the `/api/` = `no-store` vs static = `no-cache` distinction.
- **Steps:**
  1. Add `Vary: X-Zen-Transport, Accept-Language, Origin, Cookie` to every `/api/` response in
     `ZenTransportResponseFilter` (it already runs on every such response and already knows the
     negotiated format).
  2. Set `Cache-Control: no-store` on authenticated responses.
  3. Document why `/api/` gets `no-store` where static assets get `no-cache`, next to
     `StaticCacheHeaders`' existing `DYNAMIC_PREFIXES` exclusion comment.
- **Tests:** extend the existing transport-filter test (or add one) asserting the `Vary` header is
  present and `GET /api/v1/auth/identity` carries `no-store`.
- **verify:contracts:** no.
- **ADR:** no.
- **Effort:** S.
- **Depends on:** nothing. Can land in the same PR as F5 (both are small, both are
  `zen-transport`/`zen-ratelimit` housekeeping) or separately — reviewer's call.

---

## Phase 2 — Medium, contained fixes (batch by module to minimize rebase churn)

Group these by the module they touch since several land in the same files as Phase 1 items.

### F8 — `upsertOnLogin` check-then-act race (PK + email unique index)

- **Branch:** `fix/upsert-on-login-race`
- **Files:** `server/zen-identity/.../user/UserStore.java`.
- **Steps:**
  1. PK race: switch to `INSERT ... ON CONFLICT DO NOTHING` then re-select, following the
     single-statement upsert idiom `DurableLimiter` already uses in this codebase.
  2. Email collision: decide the policy explicitly — either detach the address from the losing row
     before writing, or refuse with a typed `AuthException` naming what happened. Pick one; don't
     leave it to the unique-index exception to surface as an opaque 500.
  3. **Sequence after F4** — the constraint-violation path currently surfaces as a bare 500; once
     F4's catch-all mapper exists, a residual race (if any survives the fix) at least returns a
     `ZenError`, but the goal here is to close the race, not just tidy its failure mode.
- **Tests:** extend `UserEmailUniquenessTest`; add a concurrency test for the PK race (two
  concurrent first-logins for the same identity) if the test harness supports it, else document why
  not and cover it via a targeted unit test of the upsert SQL logic.
- **verify:contracts:** no. **ADR:** no. **Effort:** M.
- **Depends on:** F4 landed first is preferable but not required.

### F10 — `lifecycle_state` hard-coded to `"active"`

- **Branch:** `fix/derive-lifecycle-state` (or `fix/remove-lifecycle-state-field` if the decision is
  to delete it — see step 1).
- **Files:** `server/zen-identity/.../IdentityMapper.java`; possibly `proto/zen/v1/identity.proto`.
- **Steps:**
  1. **Decision point, resolve before coding:** derive `active`/`warned`/`anonymised` from
     `UserRetentionService`'s two retention timestamps and its `NOT_ANONYMISED` predicate (free,
     no proto change), **or** delete the field from `identity.proto` if no consumer needs it yet.
     Check the Dart/TS consumers first — if the admin panel or `zen_demo_client` already renders
     this field, deriving it is almost certainly the right call over deleting it out from under a
     consumer.
  2. Implement the chosen path in `IdentityMapper#toProto`.
- **Tests:** unit test on `IdentityMapper` covering all three derived states, including the
  anonymised-email-pattern boundary.
- **verify:contracts:** yes, if deleting the field (full Java/Dart/TS regen loop via
  `sync-contracts`); no, if deriving it in Java only.
- **ADR:** only if deleting a field from a framework-inherited proto contract — check with
  `add-adr` skill if that's the chosen path.
- **Effort:** S (derive) or M (delete, due to `verify:contracts` loop and consumer check).

### F11 — `classifySupabaseError` keys on brittle substrings

- **Branch:** `fix/structured-supabase-error-codes`
- **Files:** `server/zen-identity/.../IdentityService.java`.
- **Steps:**
  1. Parse GoTrue's structured `error_code` field (Jackson already on this module's classpath for
     outbound calls) and key on it; keep the substring match as a documented fallback for GoTrue
     versions without the structured field.
  2. Add a contract test pinning real GoTrue error-code strings rather than a mock's invented body
     text, so a wording change upstream can't silently degrade all six branches at once — the risk
     the review calls out for the enumeration defence in `register()`.
- **Tests:** new `IdentityServiceTest` cases keyed on `error_code`, plus the fallback path retained
  and tested.
- **verify:contracts:** no. **ADR:** no. **Effort:** M.
- **Depends on:** rebase against F1 if F1 has already landed (both touch `IdentityService.java` and
  `SupabaseAuthClient`-adjacent code) — land F1 first.

### F12 — `AdminUserResource` double-parses filter, hand-builds JSON, undeclared Jackson dependency

- **Branch:** `fix/admin-user-resource-filter-cleanup`
- **Files:** `server/zen-identity/.../user/AdminUserResource.java`; possibly `zen-identity/pom.xml`.
- **Steps:**
  1. Parse the filter JSON once into a small record; pass it to both `buildFilter` and
     `filterParams` to remove the double parse and the drift risk between them.
  2. Resolve the Jackson edge: either declare `jackson-databind` explicitly with a comment
     explaining the inbound use is intentional, or replace the three query-parameter parses
     (`[int,int]`, `[string,string]`, flat object) with hand-rolled parsing, removing the dependency
     from the inbound path entirely (the review's preferred option).
  3. Leave the hand-built JSON array response as-is — ADR-005 chose the bare-array shape
     deliberately; this is not part of the fix.
- **Tests:** existing `AdminUserResourceTest` coverage should still pass; add a test asserting
  `buildFilter`/`filterParams` see a consistent parsed representation (regression guard against the
  drift the review names).
- **verify:contracts:** no. **ADR:** no. **Effort:** M.
- **Depends on:** land after F4 (both touch `AdminUserResource.java`'s query-param handling) to
  avoid a three-way merge conflict — do F4, then F12, in sequence on the same file.

### F13 — Dead framework API (delete)

- **Branch:** `fix/remove-dead-identity-api`
- **Files:** `UserRoleLoader.java` (`loadRole`, `userExists`), `SessionService.java`
  (`readCookie`), `CsrfRules.java` (`exemptPaths`).
- **Steps:** delete all four methods; delete now-unused imports; confirm no test references them
  (`CsrfRulesTest` already exercises `applies` directly per the review).
- **Tests:** `task test:apps:server` should stay green with no changes needed to existing tests.
- **verify:contracts:** no. **ADR:** no. **Effort:** XS. This is a good "first PR of the day"
  cleanup — zero risk, zero design decisions.

### F14 — Unvalidated language tag on admin update

- **Branch:** `fix/validate-admin-user-language`
- **Files:** `server/zen-identity/.../user/AdminUserResource.java` (`update`).
- **Steps:** validate `incoming.getLanguage()` against the application's `zen.i18n.supported` set
  (the same one `UserStore#supported()` reads) before writing; reject with 400 + `ZenError` on a
  miss (reuse F4's mapper/pattern if landed, otherwise a local `Response.status(400)`).
- **Tests:** `AdminUserResourceTest` case for an unsupported tag → 400.
- **verify:contracts:** no. **ADR:** no. **Effort:** XS.
- **Depends on:** ideally after F4 so the 400 path is consistent with the new convention.

### F16 — Locale-sensitive `toLowerCase()` in three parsers

- **Branch:** `fix/locale-root-tolowercase`
- **Files:** `AcceptLanguage.java:29`, `ZenLocales.java:67`, `ZenTransportFormat.java:65`.
- **Steps:** change all three to `toLowerCase(Locale.ROOT)`, matching `CsrfRules`, `RateLimitRule`,
  and `IdentityService` which already do this correctly.
- **Tests:** add a regression test with a JVM default locale forced to Turkish
  (`Locale.setDefault(new Locale("tr"))` in a `@BeforeEach`/`@AfterEach` pair that restores it) for
  at least one of the three, to prove the fix and prevent recurrence.
- **verify:contracts:** no. **ADR:** no. **Effort:** XS.

### F17 — Undocumented `ignoringUnknownFields()` behavior

- **Branch:** `docs/document-ignoring-unknown-fields`
- **Files:** `server/zen-transport/.../ProtoJsonMessageBodyReader.java` (javadoc only).
- **Steps:** add a paragraph matching how `InvalidBodyExceptionMapper` documents its own scope:
  state that unknown fields are silently dropped (forward-compat + mass-assignment defence, API3
  positive), and that runtime drift is not caught here — only `task verify:contracts` catches it at
  build time.
- **Tests:** none (doc-only). **verify:contracts:** no. **ADR:** no. **Effort:** XS.

### F18 — Content-type sniffing is a loose substring match

- **Branch:** `fix/exact-content-type-subtype-match`
- **Files:** `server/zen-transport/.../ZenTransportFormat.java:49-57`; new test file (class has
  none today).
- **Steps:** compare the subtype exactly (`x-protobuf` / `json` / `*+json`) instead of
  `contains("protobuf")`/`contains("json")`.
- **Tests:** new `ZenTransportFormatTest` — first test file for this class — covering the sniff
  fallback path including the edge case named in the review (`text/protobuf-notes` must not select
  binary protobuf for a header-less request).
- **verify:contracts:** no. **ADR:** no. **Effort:** S.

### F19 — Raw exception string in `JobTickResult` response

- **Branch:** `fix/job-error-summary-not-raw-exception`
- **Files:** `server/zen-jobs/.../JobScheduler.java:187,202`; `docs/.../openapi.yaml` (`JobRun`
  schema doc comment narrowing `error`'s meaning).
- **Steps:** keep logging the full exception and persisting the full string to `zen_jobs.last_error`
  (both already correct); change only the **response** value to a stable summary — exception's
  simple class name, or a fixed `job_failed` code.
- **Tests:** `JobSchedulerTest` (or equivalent) asserting the response no longer contains the raw
  message while the persisted `last_error` column still does.
- **verify:contracts:** no (response is a proto string field, value change only, no shape change).
- **ADR:** no. **Effort:** XS.

### F20 — NPE risk on vanished `JobState` row; `Error` not caught in tick loop

- **Branch:** `fix/job-scheduler-robustness`
- **Files:** `server/zen-jobs/.../JobScheduler.java:207-229`.
- **Steps:** null-check `JobState.byId(id)` in both `recordStart` and `recordOutcome`; log at WARN
  and treat a vanished row as "not due" instead of NPE-ing mid-transaction. Leave the
  `RuntimeException`-only catch in `runOne` as documented (catching `Error` is a deliberate
  non-goal per JVM convention) unless the review's note is read as asking for that too — re-check
  with the user before widening the catch, since catching `Error` is usually the wrong call.
- **Tests:** test deleting a `zen_jobs` row between `dueJobs()` and `recordStart`/`recordOutcome`,
  asserting the tick continues rather than dying.
- **verify:contracts:** no. **ADR:** no. **Effort:** S.

### F21 — Burst-limiter overflow is an attacker-reachable global reset

- **Branch:** `security/burst-limiter-eviction-policy`
- **Files:** `server/zen-ratelimit/.../BurstLimiter.java:107-123`; its javadoc; `RateLimitRule`
  javadoc (the `GLOBAL` bucket's DoS-bucket note).
- **Steps — decision required before coding (flag to user, this is a design trade, not a bug):**
  1. **(a)** Evict least-recently-used instead of clearing (bounds memory without forgiving
     anyone) — needs a `LinkedHashMap`-based LRU or a small sharded structure + lock. Contained to
     `BurstLimiter` and its test; doesn't touch ADR-028/029's model.
  2. **(b)** Raise `max-tracked-subjects` and document the real memory ceiling.
  3. **(c)** Accept current behavior, add the missing sentence to `RateLimitRule.GLOBAL`'s javadoc.
  Recommend **(a)** if there's appetite for the work; **(c)** as the zero-risk minimum that must
  happen regardless of which of (a)/(b) is also chosen, since honest documentation of a known trade
  is non-negotiable per this repo's own standard.
- **Tests:** if (a): a test that fills the map past `max-tracked-subjects` and asserts LRU eviction
  rather than a full clear, plus a test that legitimate callers' counters survive an eviction storm
  that an attacker's addresses would have triggered.
- **verify:contracts:** no. **ADR:** possibly, if (a) or (b) is chosen — check whether it touches
  ADR-028/029's stated model closely enough to warrant an entry; the review says it doesn't for (a).
- **Effort:** S (c only) / M (a or b).
- **This one needs an explicit decision from the user before scheduling** — surface it rather than
  picking silently.

### F22 — `auth` bucket writes to Postgres pre-auth

- **No branch — no change recommended.** The review classifies this as verified-safe-by-design
  (bounded to 10 writes/min/address by the burst tier). Record as closed with no action; do not
  create a task for it.

### F23 — `DemoResource#profile` re-implements `@Authenticated`

- **Folds into F4.** Once F4's catch-all mapper (or a dedicated
  `ExceptionMapper<UnauthorizedException>` in `zen-transport`) makes `@Authenticated` alone produce
  a `ZenError` body, delete the hand-rolled `securityIdentity.isAnonymous()` check in
  `DemoResource#profile` and rely on `@Authenticated`.
- **Branch:** do this as a follow-up commit on the F4 branch, or a tiny separate
  `fix/demo-resource-use-authenticated` PR immediately after F4 merges.
- **Tests:** `DemoResourceTest` should still assert 401 on anonymous access, now via the framework
  path instead of the hand-rolled one.
- **Effort:** XS, but blocked on F4.

---

## Phase 3 — Design-level work requiring an ADR (largest, sequence last within their dependency chains)

### F3 — Password change revokes nothing, requires no re-auth

- **Branch:** `security/password-change-session-revocation`
- **Files:** `proto/zen/v1/*.proto` (new optional `current_password` field on
  `SetPasswordRequest`), `server/zen-identity/.../auth/AuthResource.java` (`setPassword`),
  `IdentityService.java`, the client's set-password screen (Dart), `docs/architecture/DECISIONS.md`.
- **Steps:**
  1. **Write the ADR first** (via the `add-adr` skill) — this is explicitly called out as a design
     decision, not a refactor: the asymmetry between "session-authenticated password change" (needs
     `current_password`) and "recovery-link password change" (must keep working without it) is the
     real work, and it changes what a framework-inherited endpoint requires of every application.
  2. Add the optional `current_password` field to `SetPasswordRequest` in
     `proto/zen/v1/identity.proto` (or wherever the message lives) → run the full `sync-contracts`
     loop (Java DTOs, Dart messages, TS types) → `task verify:contracts`.
  3. In `AuthResource#setPassword`/`IdentityService`, require `current_password` when the session
     was **not** obtained from a recovery link; skip the check for recovery flows.
  4. After a successful `updateUser`, call `authClient.logout(bearer(accessToken), "global")`, then
     re-issue the caller's own fresh cookies via a `token` call so the user isn't signed out of the
     device they just used.
  5. Update the Dart client's set-password screen to send `current_password` when applicable.
- **Tests:** `AuthResourceTest`/`IdentityServiceTest` covering: (a) ordinary change with correct
  current password succeeds and revokes other sessions; (b) ordinary change with wrong/missing
  current password is rejected; (c) recovery-link change succeeds without `current_password` and
  still revokes other sessions; (d) the caller's own new cookies work immediately after.
- **verify:contracts:** **yes — full loop.** **ADR:** **yes — write before implementing.**
- **Effort:** L.
- **Depends on:** nothing technically, but should be scheduled after Phase 1/2 land so the ADR
  discussion isn't competing with in-flight smaller PRs touching the same files
  (`AuthResource.java`, `IdentityService.java`).

### F7 — WebSocket upgrade bypasses CSRF/rate-limit/transport-seam controls

- **Branch:** `security/websocket-origin-check`
- **Files:** `apps/zen_demo/zen_demo_server/.../DemoWebSocket.java` (`@OnOpen`),
  `docs/architecture/STANDARDS.md` (a sentence in "Deployment model" or beside `CsrfRules`'
  `SameSite=None` note).
- **Steps:**
  1. Add an explicit `Origin` allowlist check in `@OnOpen`, reusing the same list
     `quarkus.http.cors.origins` already carries — state the defence rather than inheriting it from
     a cookie attribute (`SameSite=Lax`) that could change later.
  2. Add a per-address slot ceiling in `WebSocketConnections` alongside the existing global 200-slot
     cap, closing the single-caller lock-out the review names (`--max-instances=1` means one caller
     holding all 200 slots locks out the whole fleet).
  3. Add the STANDARDS sentence documenting this coupling (CSRF/rate-limit stop at the WS upgrade)
     so it isn't rediscovered by the next application that opens a socket.
- **Tests:** app-module WebSocket test asserting a cross-origin handshake (mismatched `Origin`
  header) is refused; a test asserting a single address cannot exceed its per-address slot ceiling
  while other addresses can still connect.
- **verify:contracts:** no (app-scoped, no proto change). **ADR:** **only if/when
  `WebSocketConnections` is promoted to a framework module** — not needed for the `Origin` check
  itself, per the review. Note the promotion trigger ("the moment a second application opens a
  socket") is not yet met — do not promote preemptively.
- **Effort:** M.
- **Depends on:** nothing.

### F15 — `UserRetentionService` reads the system clock directly (ADR-sized, reported not fixed)

- **Do not schedule as a normal fix.** The review is explicit that this is "the evidence for
  promoting" `zen-jobs`' `Clock` producer per ADR-008's own stated trigger ("a second consumer"),
  and the honest home (`zen-transport`? a new `zen-time` module?) is itself the decision to make.
- **Action for this plan:** raise it as a proposal, not a branch. Use `add-adr` to draft a decision
  on where the shared `Clock` producer should live once `zen-identity` becomes its third consumer,
  **before** writing any code that injects `Clock` into `UserRetentionService`. Only after that ADR
  is accepted does this become a normal Phase 2-sized fix (`fix/inject-clock-user-retention`):
  inject `Clock`, replace the five `OffsetDateTime.now()` calls, and extend
  `UserRetentionServiceTest` to assert exact-cutoff boundary behavior using a fixed clock instead of
  sleeping or tolerating flakiness.
- **Effort:** ADR discussion first (unscheduled), then S once the module question is settled.

---

## Suggested sequencing summary

| Order | Item(s) | Why here |
|---|---|---|
| 1 | F2 | Gate is red today; blocks nothing else but shouldn't be left red |
| 2 | F13 | Zero-risk deletion; good warm-up, no dependencies |
| 3 | F1 | Provider outage currently presents as "wrong password"; high real-world impact |
| 4 | F4 (+F23 follow-up) | Closes the contract hole; prerequisite for F8/F23's clean fixes |
| 5 | F5, F6 | Small, well-bounded, make existing stated rules enforceable |
| 6 | F16, F17, F18, F19, F20 | Small, independent, no shared-file conflicts with the above once F4 has landed |
| 7 | F8, F11, F12, F14 | Depend on F4 having landed (shared files / consistent 400 pattern) |
| 8 | F10 | Needs the derive-vs-delete decision first |
| 9 | F21 | Needs the (a)/(b)/(c) decision from the user first |
| 10 | F7 | Explicit `Origin` check, before anyone needs `SameSite=None` |
| 11 | F3 | Largest piece; write the ADR before coding; touches the proto contract |
| 12 | F15 | ADR proposal first; do not code against an undecided module home |
| — | F22 | No action — verified safe by design |

## Decisions to surface to the user before scheduling

1. **F21** — which of (a) LRU eviction, (b) raise the ceiling, or (c) document-only should the
   burst limiter get? All three are defensible; (c) is required regardless of which is also chosen.
2. **F10** — derive `lifecycle_state` in Java (free) or delete it from the proto (touches
   `verify:contracts` and any existing Dart/TS consumers) — check consumers before deciding.
3. **F3** — confirm the `current_password` requirement/recovery-flow asymmetry design before
   drafting the ADR, since it changes a framework-inherited endpoint's contract for every app.
4. **F15** — confirm before drafting: does the shared `Clock` producer move to a new `zen-time`
   module, or into `zen-transport`? `zen-core` is ruled out (zero-dependency by design).
