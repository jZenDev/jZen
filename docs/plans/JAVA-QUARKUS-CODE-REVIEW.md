# Java / Quarkus multi-perspective code review

**Date:** 2026-09-14. **Scope:** every module under `server/` (`zen-core`, `zen-transport`,
`zen-identity`, `zen-email`, `zen-jobs`, `zen-ratelimit`, `zen-proto`) and
`apps/zen_demo/zen_demo_server`. **Companion:** `docs/plans/SECURITY-ARCHITECTURE-REVIEW-PROMPT.md`
owns the boundary-level/architectural findings; this review does not restate them.

**Rules of engagement honoured:** read-only. No source file was edited. No request was sent to the
deployed Cloud Run service or to the hosted Supabase project. Nothing was committed, pushed or
deployed.

**Urgent / live-exploitable:** none found. The one item that is live and needs acting on is
**F2 — `task audit` is currently RED**, including a Critical Netty advisory in a shipped
dependency. It is a supply-chain exposure rather than an application logic hole, so it leads the
list but is not an "exploitable right now against jZen" item.

---

## 0. What ran, and what did not

| Check | Result |
|---|---|
| `cd server && ./mvnw -B -q install -DskipTests` | **PASS** (exit 0) — everything compiles on JDK 25 / Quarkus 3.38.0 |
| `task test:apps:server` | **PASS** — `Tests run: 158, Failures: 0, Errors: 0, Skipped: 0`, BUILD SUCCESS |
| `task audit` (OSV, network) | **FAIL** — 259 Java deps checked, 3 advisories, see F2. `scripts/audit-suppressions.txt` is empty, as intended |
| `grep` for `jandex-maven-plugin` per module | see §1 inventory — correct in every module that needs it |
| `grep` for `quarkus-rest-jackson` in every `pom.xml` | **absent server-side.** Only `quarkus-rest-client-jackson` in `zen-identity` (outbound Supabase), which the rule permits |
| `grep` for string-concatenated JPQL/SQL | **clean** — every query is a constant string with named/positional parameters |
| `grep` for `Runtime.exec` / `ProcessBuilder` / `ObjectInputStream` / `readObject` / `XMLDecoder` | **no hits anywhere** |
| `grep` for `printStackTrace` | **no hits** |
| `grep` for hard-coded credentials | only three test constants (`JobTriggerAuthenticatorTest`, `JobTriggerResourceTest`, `DatabasePrivilegeTest`) — all `%test`-scoped literals that match `application.properties`' own `%test` values. No production secret in source |
| `grep` for `GOOGLE_APPLICATION_CREDENTIALS` / `GoogleCredentials.fromStream` / committed `*service-account*.json` | **no hits.** Cloud Run authenticates as its attached service account implicitly |
| `grep` for rest-client wire logging / secrets in log lines | **clean.** No `quarkus.rest-client.logging.scope` anywhere; `%dev.quarkus.log.category."zen".level=DEBUG` only, which does not reach the REST client's request logger. No log line contains a token, cookie, password or raw email |
| **semgrep `p/owasp-top-ten` + `p/java`** | **COULD NOT RUN — not installed on this machine** (`which semgrep` → not found). This is a gap, not a pass |
| **SpotBugs + find-sec-bugs** | **COULD NOT RUN — not installed** (`which spotbugs` → not found). `maven-pmd-plugin` 3.27.0 is wired into the build against `server/pmd-ruleset.xml`, but PMD's default rulesets are style/bug-pattern, not security-focused. A find-sec-bugs pass remains unperformed |
| Dynamic PoC against a local stack | **NOT RUN.** `:8080` and `:54321` on this machine are occupied by another project's Supabase/Quarkus stack (`supabase_*_bugeater-quarkus` containers). Per the standing "no broad process kills" rule, a busy port here is environmental and was left alone; booting `task run:demo` would have collided with it. Every finding below is therefore traced statically, and each one says so. F1's mechanism was confirmed at **bytecode** level instead (see its evidence) |

---

## 1. Module inventory (the map for §3.3 and §2)

| Module | Packaging | Contributes CDI beans / JAX-RS providers? | `jandex-maven-plugin` | `quarkus-rest-jackson` | Verdict |
|---|---|---|---|---|---|
| `zen-proto` | jar | no — generated DTOs, only `protobuf-java` | no | no | **correct** (leaf, no beans to index) |
| `zen-core` | jar | no — `ZenStatus` (interface of constants), `AcceptLanguage`, `ZenLocales`, all `final` + static | no | no | **correct** (zero-dependency pure Java by design; adding Jandex would make it a bean archive for nothing) |
| `zen-transport` | jar | **yes** — 2 filters, 4 body readers/writers, 2 exception-mapper-adjacent `@Provider`s, `SecurityHeaders`, `StaticCacheHeaders`, `CorsCredentialsGuard`, `ZenProtoReflection` | **yes** | no | **correct** |
| `zen-identity` | jar | **yes** — `AuthResource`, `AdminUserResource`, `AuthCallbackResource`, `WellKnownResource`, `CsrfFilter`, `AuthExceptionMapper`, `RoleAugmentor`, `SessionCookieAuthenticationMechanism`, `MigrateOnlyRunner`, services, MapStruct mapper | **yes** | no (`quarkus-rest-client-jackson` only) | **correct** |
| `zen-email` | jar | **yes** — `EmailService` | **yes** | no | **correct** |
| `zen-jobs` | jar | **yes** — `JobScheduler`, `JobTriggerResource`, `JobTriggerAuthenticator`, `JobTickCron`, `JobClock` producer | **yes** | no | **correct** |
| `zen-ratelimit` | jar | **yes** — `RateLimitFilter`, both limiters, `RateLimitProperties`, `RateLimitAddressGuard`, `RateLimitCleanupJob` | **yes** | no | **correct** |
| `apps/zen_demo/zen_demo_server` | **quarkus** | yes (the assembled app) | n/a (app module is scanned directly) | no | **correct** |

**Both named silent-failure traps are closed today.** Every bean-contributing library is indexed,
no module pulls `quarkus-rest-jackson`, and the app module carries wiring tests
(`CsrfWiringTest`, `RateLimitWiringTest`, `SecurityHeadersWiringTest`, `StaticCacheHeadersWiringTest`,
`MigrateOnlyWiringTest`, `CorsCredentialsGuardWiringTest`) that fail the build if an index is ever
dropped. This is the strongest part of the codebase and nothing here is a finding.

**Transport-seam invariants (§3.3) — all verified:**

- Every resource method returns `jakarta.ws.rs.core.Response` with `@APIResponse(@Schema(ref=...))`.
  No bare proto return type anywhere (`AuthResource`, `AdminUserResource`, `JobTriggerResource`,
  `DemoResource`, `HealthResource`, `WellKnownResource`, `AuthCallbackResource` all checked
  method by method).
- `ZenTransportFilter` is `@PreMatching`, gated to `api/`, and rewrites **only** `Accept`
  (`ZenTransportFilter:44`). It never touches `Content-Type` and never steers a reader.
- The request body's parser is chosen purely by `@Consumes` on
  `ProtoJsonMessageBodyReader` / `ProtobufMessageBodyReader`. `X-Zen-Transport` is response-only,
  exactly as `CLAUDE.md` states.
- Writers carry `@Priority(1)` and `isWriteable` matches only `com.google.protobuf.Message`.

**Contract-first hygiene (§3.8) — no drift found.** No hand-edited file under a generated path;
`zen-proto/target` is untracked as documented; `ZenProtoReflection`'s explicit list is gated by
`task sync:contracts`; the `openapi.yaml` component schemas (14 of them) each correspond to a
`@Schema(ref=...)` used by a resource, and every `ref` used by a resource has a schema.

**No BOLA (API1) found.** Traced every `@PathParam`-taking method: the only one is
`AdminUserResource#get/#update`, which is `@RolesAllowed(UserRole.Names.ADMIN)` — an admin is
legitimately allowed any id, so there is no ownership check to make. `IdentityService#currentUser`
is only ever called with the caller's own `sub`, and it explicitly compares the id before reusing
the augmentor's row (`IdentityService:292-294`) rather than trusting the attribute's presence —
that comparison is exactly the BOLA guard, and it is already there.

**No SQL/JPQL injection (A03 / CWE-89) found.** Every HQL fragment is a compile-time constant;
`AdminUserResource#buildFilter` appends only two hard-coded clause literals and binds the values as
named parameters (`AdminUserResource:257-282`); `AdminUserResource#buildSort` whitelists the sort
column through the `SORTABLE` map before it reaches `Sort.by`. `DurableLimiter`'s upsert and
`MigrateOnlyRunner`'s catalogue queries are all `PreparedStatement`/positional-parameter based.

---

## 2. Top 10 across the whole review

Ranked by severity × number of independent lenses × framework scope.

| # | Finding | Scope | Lenses | OWASP / CWE |
|---|---|---|---|---|
| **F1** | A Supabase **5xx** is turned into a **401 `unauthorized`**, is not retried, and never trips the circuit breaker — the opposite of what the interface's own javadoc claims | framework | Correctness, Quarkus idiom, Security, Concurrency/state, GCP+Supabase, Testing | A09, API8 / CWE-703, CWE-544 |
| **F2** | `task audit` is red today: 3 advisories on Netty 4.1.136.Final, one **Critical** | framework | Security, Testing | A06 / CWE-1395 |
| **F3** | Changing a password neither revokes the user's other sessions nor requires re-authentication | framework | Security | A07, API2 / CWE-613, CWE-620 |
| **F4** | No catch-all `ExceptionMapper`: any unmapped throwable leaves the `ZenError` contract and returns a bare Quarkus 500. Reachable today from `AdminUserResource`'s three query parameters | framework | Correctness, Transport seam, Security, Contract-first | A05, API8 / CWE-20, CWE-209 |
| **F5** | `RateLimitFilter` and `CsrfFilter` are both unprioritised post-matching filters; which one runs first is implementation-defined, and one order leaves a request class uncounted | framework | Quarkus idiom, Security, Concurrency | A04, API4 / CWE-696 |
| **F6** | No `Vary` header on any response, though two request headers change the response body | framework | Correctness, Transport seam, Performance, Security | A05 / CWE-524 |
| **F7** | The WebSocket upgrade sits outside every JAX-RS control — CSRF, rate limiting and the transport seam all stop at it; only `SameSite=Lax` stands between it and cross-site socket hijacking | framework gap, app exposure | Security, Concurrency, Transport seam | API4, API8 / CWE-1385 |
| **F8** | `UserStore#upsertOnLogin` is a check-then-act against the primary key and the `users.email` unique index | framework | Correctness, Concurrency | — |
| **F9** | `AcceptLanguage#resolve` ignores q-values entirely, including `q=0`, so it can return the language the caller explicitly rejected | framework | Correctness | — |
| **F10** | `IdentityMapper#toProto` hard-codes `lifecycle_state = "active"` for every identity, including anonymised ones | framework | Correctness, Contract-first | — |

---

## 3. Findings by module

### 3.1 `zen-identity` (framework — inherited by every application)

---

#### F1 — A Supabase 5xx becomes a 401, skips the breaker, and skips the retry

**Perspectives:** Correctness · Quarkus & CDI idiom · Security · Concurrency & state · GCP/Supabase
integration (§3b) · Testing & maintainability
**Scope:** `framework`
**OWASP:** A09 Security Logging & Monitoring Failures; API8 Security Misconfiguration. **CWE:**
CWE-703 (improper check of exceptional condition), CWE-544 (missing standardized error handling).
**Location:** `server/zen-identity/src/main/java/zen/identity/auth/SupabaseAuthClient.java:33-35`
(class javadoc) and every method's `@CircuitBreaker(... skipOn = WebApplicationException.class)` /
`@Retry(... abortOn = WebApplicationException.class)`; consumed at
`server/zen-identity/src/main/java/zen/identity/IdentityService.java:321-363`.

**The claim being made.** `SupabaseAuthClient`'s javadoc states the design explicitly:

> "a Supabase 4xx (`WebApplicationException`) skips the breaker and aborts retries (it is a real
> client error, not a transient fault), while **timeouts and 5xx trip the breaker**."

That split is the right design. The annotations do not implement it.

**Evidence — traced to bytecode, not inferred.** The MicroProfile Rest Client's fallback mapper is
`io.quarkus.rest.client.reactive.runtime.DefaultMicroprofileRestClientExceptionMapper`. Disassembled
from the resolved artifact:

```
$ javap -p -c io/quarkus/rest/client/reactive/runtime/DefaultMicroprofileRestClientExceptionMapper.class
  public java.lang.Throwable toThrowable(jakarta.ws.rs.core.Response);
        9: new           #15   // class jakarta/ws/rs/WebApplicationException
       13: ldc           #17   // String %s, status code %d
       45: invokespecial #45   // Method jakarta/ws/rs/WebApplicationException."<init>":(...)
  public int getPriority();
        0: ldc           #58   // int 2147483647
```

The class declares **no `handles(int, MultivaluedMap)` override**, so it inherits the
`ResponseExceptionMapper` interface default, `status >= 400`. Its priority is `Integer.MAX_VALUE`,
i.e. it is the fallback that runs when nothing else claims the response, and jZen registers no
`ResponseExceptionMapper` or `@ClientExceptionMapper` anywhere
(`grep -rn "ResponseExceptionMapper\|ClientResponseFilter" server apps` → no hits).

So **every** Supabase response from 400 through 599 arrives as a `WebApplicationException`. Three
consequences follow, all of them the opposite of the documented intent:

1. `skipOn = WebApplicationException.class` means a Supabase **500/502/503 is not recorded as a
   circuit-breaker failure**. The breaker can only ever trip on `TimeoutException` or a transport
   error. A Supabase instance that is up and answering 503 in 20 ms — the classic overload
   signature — is invisible to it forever.
2. `abortOn = WebApplicationException.class` means **no retry on a 5xx either**. (This half is
   defensible on its own; it is only wrong relative to the stated design.)
3. Worse, the failure is *misclassified to the caller*. `IdentityService#call` catches the
   `WebApplicationException` and hands it to `classifySupabaseError`, whose comment reads
   `// Unknown 4xx: a safe, generic message` — a 503's body matches none of the six needles, so it
   falls through to `IdentityService:362`:

   ```java
   return new AuthException(401, "unauthorized", "We could not complete your request.");
   ```

**Failure scenario.** Supabase Auth has an incident and returns `503` on `POST /token`. A user
types their correct password. jZen answers **401 `unauthorized`**. The Dart `ZenClient` parses a
`ZenError` on any status ≥ 400 and the client's identity layer treats 401 as "your session is not
valid" — so during a provider outage, every logged-in user is signed out and every login attempt
reads as wrong credentials. Nothing anywhere logs a provider error, no breaker opens, and the
`zen-ratelimit` `auth` durable counter is charged for each of those retries by a user who is doing
nothing wrong. This is the "failures surface; nothing is swallowed" rule inverted: the failure is
not swallowed, it is *relabelled as the user's fault*.

**Fix.** Split the two by status, not by exception type. The narrow change is a
`@ClientExceptionMapper` (or a `ResponseExceptionMapper` registered on the client) that throws a
distinct type for `status >= 500` — e.g. `SupabaseUnavailableException extends RuntimeException` —
leaving 4xx as `WebApplicationException`. Then the existing `skipOn`/`abortOn` say exactly what the
javadoc says, and `IdentityService#call` gains one branch mapping that type to a `503`-carrying
`AuthException` (`ZenStatus` has no 503 constant yet; adding one is a one-line change to an
extendable interface). **Cost:** touches a framework public surface in a small way (a new exception
type and a new `ZenStatus` constant), touches no migration, contradicts no ADR — ADR-007's fault
tolerance intent is what this restores. Worth a test in `IdentityServiceTest`, which today stubs a
transport failure (`doThrow(new IllegalStateException("supabase unreachable"))`) and never exercises
a 5xx `Response`.

---

#### F3 — A password change revokes nothing and re-authenticates nobody

**Perspectives:** Security
**Scope:** `framework`
**OWASP:** A07 Identification & Authentication Failures; API2 Broken Authentication. **CWE:**
CWE-613 (insufficient session expiration), CWE-620 (unverified password change).
**Location:** `server/zen-identity/src/main/java/zen/identity/auth/AuthResource.java:188-201`
(`setPassword`) → `server/zen-identity/src/main/java/zen/identity/IdentityService.java:193-202` →
`SupabaseAuthClient#updateUser`.

**What the code does.** `POST /api/v1/auth/password` is `@Authenticated`, CSRF-protected (it is not
in `CsrfRules.EXEMPT_PATHS`) and rate-limited in the `auth` bucket. It takes the caller's access
cookie and calls GoTrue `PUT /user` with `{"password": ...}`. It does **not** ask for the current
password, and it does **not** revoke any other session afterwards — `IdentityService#logout` is the
only code path that ever calls `SupabaseAuthClient#logout`, and it deliberately sends
`LOGOUT_SCOPE_LOCAL` (`IdentityService:46`).

**Failure scenario.** A user's refresh token is lifted (shared machine, stolen device, a token
captured before the `httpOnly` cookie hardening on some older client). The user does the one thing
every security guide tells them to do: they sign in and change their password. The attacker's
seven-day refresh token keeps working, because GoTrue does not revoke other sessions on a password
update unless asked, and jZen never asks. The victim now believes they have recovered the account
and they have not. The second half is narrower but real: anyone who reaches an unattended,
signed-in browser can set a new password without knowing the old one, permanently taking the
account — the CSRF token is JS-readable by design, and the attacker is same-origin at the keyboard.

This is precisely where `SupabaseAuthClient#logout`'s `scope` parameter — already present, already
documented as existing "because the upstream API has it, not because a second caller is planned" —
earns its keep. The seam is built; nothing uses it.

**Fix.** After a successful `updateUser`, call `authClient.logout(bearer(accessToken), "global")`,
then re-issue the caller's own cookies from a fresh `token` call so the user who just changed their
password is not signed out of the device they did it on. Separately, add an optional
`current_password` field to `SetPasswordRequest` and require it when the session was **not**
obtained from a recovery link — recovery must keep working without it, which is why
`setPassword`'s javadoc says it "asks nothing about how the session was obtained". That asymmetry
is the real design work here, and it is the reason this is a finding rather than a one-liner.
**Cost:** touches `proto/zen/v1` (a new optional field ⇒ the full `task verify:contracts` loop
across Java, Dart and TS), touches the client's set-password screen, and needs an ADR because it
changes what a framework-inherited endpoint requires of every application. No migration.

---

#### F4 — Nothing maps an unhandled exception, so a 500 leaves the `ZenError` contract

**Perspectives:** Correctness · Transport seam · Security · Contract-first hygiene
**Scope:** `framework`
**OWASP:** A05 Security Misconfiguration; API8. **CWE:** CWE-20 (improper input validation),
CWE-209 (information exposure through an error message).
**Location:** the gap is in `zen-transport` (only `InvalidBodyExceptionMapper` exists) and
`zen-identity` (only `AuthExceptionMapper`). The reachable trigger is
`server/zen-identity/src/main/java/zen/identity/user/AdminUserResource.java:117-121, 222-289` and
`server/zen-identity/src/main/java/zen/identity/user/UserRole.java:42-52`.

**Evidence.** `grep -rln "implements ExceptionMapper" server apps` returns exactly two files:
`AuthExceptionMapper` (`AuthException`) and `InvalidBodyExceptionMapper`
(`InvalidProtocolBufferException`). `AuthResource`'s javadoc states the framework's contract —
"endpoints return typed proto, errors return the shared `ZenError` proto, never an ad-hoc envelope"
— and there is nothing to honour it for any other throwable.

Three concrete paths reach it today, all through `AdminUserResource` (admin-authenticated, so the
severity is bounded, but every one of them is *input handling at a system boundary*):

- `GET /api/v1/admin/users?range=notjson` → `JSON.readValue(range, int[].class)` throws Jackson's
  `JsonParseException`. `parseRange` is declared `throws Exception` and `list` propagates it.
- `?sort=notjson` → same, via `buildSort`.
- `?filter={"role":"bogus"}` → `filterParams` calls `UserRole.fromValue`, which throws
  `IllegalArgumentException("Unknown UserRole: " + v)` — an exception whose **message embeds the
  caller's raw input**.
- `PUT /api/v1/admin/users/{id}` with a non-empty, unknown `role` → the same throw, at
  `AdminUserResource:189`.

Each produces a bare Quarkus 500 with no `ZenError` body, in a format the negotiated codec did not
choose, which the Dart `ZenClient` cannot decode into a `ZenError` and the react-admin panel cannot
display. All four are semantically **400**, not 500. The correct status is not a nicety here: a 500
is the signal an operator pages on, and these are ordinary bad requests.

**Fix.** Two pieces, and the first is the framework one:

1. A `ZenExceptionMapper implements ExceptionMapper<Throwable>` in `zen-transport` (already
   Jandex-indexed, already owns the codecs, already the home of `InvalidBodyExceptionMapper`), at a
   `@Priority` below the two specific mappers. It logs the exception server-side with its stack and
   returns a `ZenError` with a **fixed** code (`internal_error`) and a fixed message — never
   `exception.getMessage()`, which is how `IllegalArgumentException`'s echoed input would otherwise
   reach the wire. Because it sets no explicit media type, the pre-matching `Accept` rewrite
   serialises it in the caller's negotiated codec, exactly as `AuthExceptionMapper` and
   `InvalidBodyExceptionMapper` already do.
2. Validate at the boundary in `AdminUserResource`: catch the parse failures and the unknown role
   and return `Response.status(400)` with a `ZenError` code the panel can key on. `notFound(id)` is
   the pattern to copy.

**Cost:** one new `@Provider` in a module that already has them, plus four small branches. No
migration, no proto change, no ADR — it *implements* a rule STANDARDS already states rather than
changing one. Worth noting that a catch-all mapper is also the thing that would have caught F1's
misclassification, and that it must be careful **not** to swallow `AuthException` or
`InvalidProtocolBufferException` (JAX-RS picks the most specific mapper, so it will not, but the
test for it belongs in the app module).

---

#### F8 — `upsertOnLogin` is a check-then-act on two unique constraints

**Perspectives:** Correctness · Concurrency & state
**Scope:** `framework`
**Location:** `server/zen-identity/src/main/java/zen/identity/user/UserStore.java:82-123`.

```java
User user = User.findById(id);
boolean created = user == null;
if (created) { user = new User(); ... }
...
if (created) { user.persist(); }
```

Two races, both single-instance-legitimate (this is not a "won't scale horizontally" complaint —
one instance still serves up to 200 concurrent requests on many event-loop threads):

- **Primary key.** Two concurrent first-ever logins for the same Supabase identity — a client that
  fires `POST /login` twice, or a login racing an email-link `POST /session` — both see `null`, both
  build a row, both `persist()`. One transaction takes a `ConstraintViolationException` on the
  `users` PK. With F4 unfixed, that surfaces as a bare 500 on a perfectly ordinary login.
- **`users.email` unique index** (`V20260804113000__identity_email_unique.sql`). The reconciliation
  at `UserStore:109-111` writes Supabase's address onto an *existing* row with no check. If two
  Supabase identities ever hold the same address — an identity merge, a manual fix in the Supabase
  dashboard, an address freed and reused — the second login's flush violates the index. The same
  bare 500, and this one is not transient: that user cannot log in again until someone edits the
  database.

**Fix.** For the PK race, catch the constraint violation and re-read (`INSERT … ON CONFLICT DO
NOTHING` then select is the idiom, and `DurableLimiter` already demonstrates the single-statement
upsert pattern in this codebase). For the email collision, decide the policy explicitly rather than
letting the index decide it: either detach the address from the losing row before writing, or refuse
with a typed `AuthException` that says what happened. **Cost:** contained to `UserStore`; no
migration; `UserEmailUniquenessTest` exists and is the place to extend.

---

#### F10 — `lifecycle_state` is a constant

**Perspectives:** Correctness · Contract-first hygiene
**Scope:** `framework`
**Location:** `server/zen-identity/src/main/java/zen/identity/IdentityMapper.java:49` —
`.setLifecycleState("active")`.

Every `Identity` the framework has ever returned says `active`, unconditionally. Meanwhile
`UserRetentionService#anonymiseExpiredAccounts` exists precisely to move accounts through a
lifecycle, and `UserRetentionService`'s own `NOT_ANONYMISED` predicate proves the codebase can tell
an anonymised row from a live one (`email not like 'anon!_%' escape '!'`). A field on the wire
contract that cannot vary is either a lie or dead weight, and a client that trusts it — the obvious
use is "show this account as deactivated" — is trusting a literal.

**Fix.** Either derive it (the two retention timestamps plus the anonymised-email predicate already
express `active` / `warned` / `anonymised`), or delete the field from `zen/v1/identity.proto` and
stop claiming it. **Cost:** deriving it is free; deleting it touches the proto and therefore the
full `task verify:contracts` loop plus the Dart and TS consumers.

---

#### F11 — `classifySupabaseError` keys on substrings of an upstream body

**Perspectives:** Correctness · Testing & maintainability · Security
**Scope:** `framework`. **OWASP:** A09. **CWE:** CWE-1288 (improper validation of consistency
within input).
**Location:** `server/zen-identity/src/main/java/zen/identity/IdentityService.java:329-363`.

Six branches match lower-cased substrings of GoTrue's response body (`"rate limit"`,
`"password should"`, `"not confirmed"`, `"invalid login"`, …). The *design* — never hand the
upstream text to the client, key the client on a stable `code` — is right and is the reason this is
a maintainability finding rather than a security one on its own. The mechanism is the problem:

- A GoTrue wording change silently degrades every branch to the generic 401. Combined with F1 that
  means three different upstream conditions (a genuine bad password, a rate limit, and an outage)
  all present identically, and the `AuthResourceTest` assertions — which check the *code*, from a
  mocked client whose body text the test itself wrote — would stay green through all of it.
- The needles are broad enough to cross-match. `"not confirmed"` and `"rate limit"` are ordinary
  English that could appear inside an unrelated error description; `register()`'s enumeration
  defence (`IdentityService:120`) depends on `"already registered"`/`"user_already_exists"`/
  `"email_exists"` being matched, and a miss there turns the neutral 202 into a **409
  `email_taken`** — a user-enumeration oracle the code explicitly exists to prevent.

**Fix.** GoTrue returns a structured body with an `error_code` field on modern versions. Parse it
(Jackson is already on this module's classpath) and key on the code, keeping the substring match as
a documented fallback for older projects. Add a contract test that pins the real GoTrue error codes
rather than the strings a mock produces. **Cost:** contained to `IdentityService`; no proto change.

---

#### F12 — `AdminUserResource` hand-builds JSON, parses the filter twice, and depends on an outbound-only Jackson edge

**Perspectives:** Transport seam · Performance · Testing & maintainability · Contract-first
**Scope:** `framework`
**Location:** `server/zen-identity/src/main/java/zen/identity/user/AdminUserResource.java:79, 126,
130-143, 257-289`.

Three related observations about one class:

- **The Jackson edge.** `AdminUserResource` imports `com.fasterxml.jackson.databind.ObjectMapper`
  and `JsonNode`, which reach it only transitively through `quarkus-rest-client-jackson` — a
  dependency `zen-identity` declares for its *outbound* Supabase calls, and which `CLAUDE.md`
  explicitly carves out as "fine — outbound Supabase calls aren't proto". A framework REST resource
  now parses *inbound* request parameters with a library that is on the classpath for an unrelated
  reason. The day someone replaces the Supabase REST client (or the platform stops pulling Jackson
  into it), this class stops compiling for a reason that has nothing to do with what changed. It is
  not a violation of the no-Jackson rule — that rule is about the `application/json` *writer*, and
  no writer is involved — but it is an undeclared dependency on a coincidence.
- **The hand-built array.** `list` builds `[...]` in a `StringBuilder` and returns it as a
  `String` (`AdminUserResource:130-143`), which is the one place in the codebase where a response
  body bypasses the transport seam's writers entirely. ADR-005 chose the bare array over a wrapper
  proto, so the *shape* is deliberate; the bypass is the cost, and it means the `ra-data-simple-rest`
  array is the one response no `MessageBodyWriter` test covers.
- **Double parse.** `buildFilter(filter)` and `filterParams(filter)` each call `filterNode(filter)`,
  so the filter JSON is parsed twice per request (`AdminUserResource:126`). Trivial in cost,
  but it is also why the two can drift: they independently decide which keys are present.

**Fix.** Parse the filter once into a small record and pass it to both helpers. For the Jackson
edge, either declare `jackson-databind` explicitly in `zen-identity`'s pom with a comment saying
why, or — better — replace the three query-parameter parses with hand-rolled parsing of what are, in
fact, three trivially-shaped values (`[int,int]`, `[string,string]`, a flat object), removing the
dependency from the inbound path altogether. **Cost:** contained; no ADR, no migration.

---

#### F13 — Dead framework API

**Perspectives:** Testing & maintainability
**Scope:** `framework`

`grep` across `server/` and `apps/` finds no caller, in main or test code, for:

| Symbol | File |
|---|---|
| `UserRoleLoader#loadRole(UUID)` | `server/zen-identity/src/main/java/zen/identity/security/UserRoleLoader.java:80` |
| `UserRoleLoader#userExists(UUID)` | `.../UserRoleLoader.java:85` |
| `SessionService#readCookie(Map, String)` | `server/zen-identity/src/main/java/zen/identity/auth/SessionService.java:90` |
| `CsrfRules#exemptPaths()` | `server/zen-identity/src/main/java/zen/identity/auth/CsrfRules.java:102` |

The first two are `@Transactional public` methods that each open a transaction to delegate to
`loadUser` — in a framework library, a public method is API, and these are API nobody asked for on
the hottest path in the application. `CsrfRules#exemptPaths()`'s javadoc says it exists "for tests
and for anything that needs to state the list", and no test uses it (`CsrfRulesTest` exercises
`applies` directly, which is the better test). **Fix:** delete all four. **Cost:** none — they are
`zen-*` SNAPSHOT libraries with one consumer in this repository.

---

#### F14 — `AdminUserResource#update` writes an unvalidated language tag

**Perspectives:** Correctness · Security (minor)
**Scope:** `framework`. **OWASP:** API3 Broken Object Property Level Authorization (weak form).
**Location:** `server/zen-identity/src/main/java/zen/identity/user/AdminUserResource.java:193`.

`user.language = emptyToNull(incoming.getLanguage())` stores whatever the admin panel sends. That
column is, per `User`'s own javadoc, "the sole locale source for email, which has no request to read
`Accept-Language` from". It is read back by `EmailService#send` and `UserStore#supported()`, both of
which run it through `ZenLocales.resolve`, so an unknown tag degrades safely to `en` — but silently,
and the admin panel will keep showing the value they typed as though it took effect. Validate
against the application's `zen.i18n.supported` set (the same one `UserStore#supported()` reads) and
reject with a 400 otherwise. **Cost:** three lines; no migration.

---

#### F15 — Retention reads the system clock while the rest of the framework injects one

**Perspectives:** Testing & maintainability · Correctness
**Scope:** `framework`
**Location:** `server/zen-identity/src/main/java/zen/identity/user/UserRetentionService.java:116,
145, 175, 188, 207` — five `OffsetDateTime.now()` calls.

`zen-jobs` produces a CDI `Clock` (`JobClock`) precisely so that "due-ness, the catch-up rule, and
the recorded `last_run_at` are all assertions about specific instants" can be tested without
sleeping, and `zen-ratelimit` is its declared second consumer. `UserRetentionService` — the module
whose windows are *330 / 23 / 7 days* and whose terminal action is irreversible anonymisation —
reads the system clock directly. The consequence is not a runtime bug; it is that the boundary
behaviour of a data-destroying policy (an account exactly at its cutoff, a clock skew across the
find/stamp/anonymise phases) is the one thing the suite cannot assert cheaply. **Fix:** inject the
`Clock` and use `OffsetDateTime.now(clock)`, as `JobScheduler` and both limiters do. **Cost:**
`zen-identity` would need to see the `Clock` producer, which lives in `zen-jobs` — `zen-identity`
does not depend on `zen-jobs` and must not start to. That makes this the *third* consumer, and so
by ADR-008's own stated trigger ("a second consumer is the trigger to promote it, on evidence") it
is the evidence for promoting the producer. `zen-core` cannot host it (zero-dependency by design), so
the honest home is a new tiny `zen-time` module or `zen-transport`; this is an ADR-sized decision,
not a refactor, which is exactly why it is reported rather than fixed.

---

### 3.2 `zen-transport` (framework)

---

#### F5 — Two unprioritised post-matching filters, and the tie decides whether a request is counted

**Perspectives:** Quarkus & CDI idiom · Security · Concurrency & state
**Scope:** `framework`
**OWASP:** A04 Insecure Design; API4 Unrestricted Resource Consumption. **CWE:** CWE-696 (incorrect
behaviour order).
**Location:** `server/zen-ratelimit/src/main/java/zen/ratelimit/RateLimitFilter.java:32-33` and
`server/zen-identity/src/main/java/zen/identity/auth/CsrfFilter.java:58-59`.

Both are `@Provider ContainerRequestFilter`, both post-matching, and **neither carries
`@Priority`** — so both bind at the JAX-RS default `Priorities.USER` (5000) and their relative order
is whatever the container's tie-break happens to be. `RateLimitFilter`'s javadoc reasons carefully
about its ordering *against `ZenTransportFilter`* ("ordinary filters run after every pre-matching
one, so the ordering is structural rather than a priority number someone has to remember") — which is
correct, and does not address the other filter at the same level.

**Why it matters, in this codebase's own terms.** `CsrfFilter` calls `ctx.abortWith(403)`, which
ends the chain. If the container runs `CsrfFilter` first, then an authenticated caller who sends a
wrong-or-missing `X-CSRF-Token` is refused **before `RateLimitFilter` ever charges the request** —
i.e. a flood of such requests is unmetered while occupying concurrency slots. That is bit-for-bit
the defect `SessionCookieAuthenticationMechanism` was written to close ("**The rate limiter was
bypassable.** `RateLimitFilter` is a JAX-RS filter, so a request rejected before JAX-RS is never
counted"), reintroduced one layer up. The mirror case is benign: if `RateLimitFilter` wins, a
throttled request is refused before the CSRF check, which is correct.

I did **not** confirm which way the tie falls in Quarkus 3.38.0 — that needs a running server, and
the local ports were unavailable (§0). **That is the finding.** Whichever way it resolves today, it
resolves by accident, across two modules that do not know about each other, and it can change on a
platform upgrade with no test failing: `RateLimitEnforcementTest` proves a 429 on an *anonymous*
path, where `CsrfFilter` returns early anyway.

**Fix.** Give both an explicit `@Priority`, with `RateLimitFilter` strictly lower (earlier) — e.g.
`@Priority(Priorities.AUTHENTICATION - 100)` on the limiter and `Priorities.AUTHORIZATION` on the
CSRF filter — and add an app-module test that an authenticated request with a bad CSRF token is
still counted. **Cost:** two annotations plus a test. No ADR (it makes an existing, stated rule
enforceable), no migration. It does mean `zen-ratelimit` and `zen-identity` now share an ordering
contract, which deserves a sentence in STANDARDS "Backend multi-module rules" beside the Jandex
rule, since it is the same class of cross-module invariant.

---

#### F6 — No `Vary`, on responses that vary by two request headers

**Perspectives:** Correctness · Transport seam · Performance · Security
**Scope:** `framework`
**OWASP:** A05 Security Misconfiguration. **CWE:** CWE-524 (use of a cache containing sensitive
information).
**Location:** `server/zen-transport/src/main/java/zen/transport/ZenTransportResponseFilter.java` —
it sets `X-Zen-Transport` and nothing else. `grep -rn "Vary" server apps` returns **no hits
anywhere in the repository**.

Two request headers change the body a `/api/` response carries:

- `X-Zen-Transport` selects the codec, so the same URL returns proto3-JSON or binary protobuf.
- `Accept-Language` selects the language for `GET /api/v1/demo/ping` and `GET /api/v1/demo/terms`.

And `/api/` responses carry **no `Cache-Control` at all**: `StaticCacheHeaders` deliberately excludes
`/api/` from its `DYNAMIC_PREFIXES` (`StaticCacheHeaders:96`), which correctly stops it attaching a
build-stable ETag, but also means nothing sets `no-store` in its place. A response with no
`Cache-Control` and no `Vary` is heuristically cacheable by any shared cache and by the browser's own
cache. The result is a cache that can return a binary protobuf body to a JSON-mode caller, or
Ukrainian terms to an English one — and, for `GET /api/v1/auth/identity`, a *user's identity
document* that is cacheable by an intermediary.

This is out of reach today by deployment accident rather than by design: jZen serves Cloud Run
directly with no CDN (ADR-027), and `SecurityHeaders`' own javadoc leans on that same fact. But
`STANDARDS` "Deployment model" already treats "someone puts an edge in front" as a foreseeable
change with a documented blast radius, and this belongs on that list — it is the same failure mode
as the cookie-stripping edge, and it would be equally silent.

**Fix.** In `ZenTransportResponseFilter`, add
`Vary: X-Zen-Transport, Accept-Language, Origin, Cookie` (it already runs on every `/api/` response
and already holds the negotiated format), and set `Cache-Control: no-store` on authenticated
responses. **Cost:** a few lines in a module that already owns the seam; no ADR, no migration.
Worth a line in `SecurityHeaders`' or `StaticCacheHeaders`' javadoc explaining why `/api/` gets
`no-store` where static gets `no-cache` — the two are easy to confuse and this codebase documents
that kind of distinction well.

---

#### F16 — Locale-sensitive `toLowerCase()` in three parsers

**Perspectives:** Correctness
**Scope:** `framework`
**Location:** `server/zen-core/src/main/java/zen/core/i18n/AcceptLanguage.java:29`;
`server/zen-core/src/main/java/zen/core/i18n/ZenLocales.java:67`;
`server/zen-transport/src/main/java/zen/transport/ZenTransportFormat.java:65`.

All three call `String#toLowerCase()` with no `Locale`, so they use the JVM's default. On a JVM whose
default locale is Turkish or Azeri, `"IT".toLowerCase()` is `"ıt"` (dotless i), not `"it"` — so a
supported language tag containing an uppercase `I` fails to match, and the caller silently gets the
fallback. `CsrfRules:77` and `RateLimitRule:124` already do this correctly with
`toLowerCase(Locale.ROOT)`, and `IdentityService:339` uses `toLowerCase(Locale.ROOT)` too, so the
codebase knows the rule; these three are the misses.

The blast radius is small today (the shipped set is `{en, uk}`, neither of which contains an `I`,
and `ZenTransportFormat` matches `json`/`protobuf`) — but `ZenLocales`' whole point per ADR-044 is
that an *application* supplies a wider set, and jZen is a framework shipped for applications whose
deployment locale it does not control. **Fix:** `toLowerCase(Locale.ROOT)` in all three. **Cost:**
three characters each.

---

#### F17 — `ignoringUnknownFields()` silently discards contract drift

**Perspectives:** Correctness · Contract-first hygiene
**Scope:** `framework`
**Location:** `server/zen-transport/src/main/java/zen/transport/ProtoJsonMessageBodyReader.java:24`.

`JsonFormat.parser().ignoringUnknownFields()` is the right choice for forward compatibility and is
also a mass-assignment defence (a client cannot inject a field the proto does not declare — which is
worth stating as a positive API3 result). The cost is that a client sending a field the server's
generated message does not have gets a **200 with that field silently dropped**, which is precisely
the drift `task verify:contracts` exists to catch on the build side and which nothing catches at
runtime. This is not a defect to fix — the alternative (strict parsing) would break every rolling
deploy — but it is undocumented, and this codebase's standard is that a deliberate silent behaviour
carries the reasoning next to it. **Fix:** one paragraph of javadoc, matching how
`InvalidBodyExceptionMapper` documents its own scope. **Cost:** none.

---

#### F18 — Content-type sniffing is a substring match

**Perspectives:** Correctness · Transport seam
**Scope:** `framework`
**Location:** `server/zen-transport/src/main/java/zen/transport/ZenTransportFormat.java:49-57`.

`ct.contains("protobuf")` / `ct.contains("json")`, in that order, on `type + "/" + subtype`. The
order is right (`application/vnd.x+json` correctly resolves JSON; a protobuf content type resolves
protobuf), and the whole branch only runs when `X-Zen-Transport` is absent, so every first-party
client bypasses it. But a `Content-Type` such as `text/protobuf-notes` would select a **binary
protobuf response** for a caller that sent no transport header. It is a low-consequence edge — the
fallback behaviour of a fallback branch — and it is named here only because `ZenTransportFormat`'s
javadoc promises "an unrecognised value falls back to JSON, so an unknown header can never fail a
request", and the content-type sniff quietly does not share that property. **Fix:** compare the
subtype exactly (`x-protobuf` / `json` / `*+json`). **Cost:** a few lines plus a unit test; the class
has no test file of its own today, which is worth noting on its own.

---

### 3.3 `zen-jobs` (framework)

---

#### F19 — The trigger response and `zen_jobs.last_error` carry a raw exception string

**Perspectives:** Security · Testing & maintainability
**Scope:** `framework`. **OWASP:** A09; API8. **CWE:** CWE-209.
**Location:** `server/zen-jobs/src/main/java/zen/jobs/JobScheduler.java:187, 202` —
`error = e.toString()`, then `run.setError(error)`, returned in the `JobTickResult` proto that
`JobTriggerResource` hands back to the caller, and persisted to `zen_jobs.last_error`.

An exception's `toString()` is the class name plus its message, and in this application that message
can be a Hibernate/PostgreSQL error naming a schema object, a Supabase URL, or a file path. The
caller is credentialed (Cloud Scheduler holds the shared secret), so the severity is genuinely low —
but the rest of this codebase is unusually disciplined about what crosses the wire
(`IdentityService#classifySupabaseError` refuses to hand the upstream message to a client;
`InvalidBodyExceptionMapper` says "no field path, no byte offset, no exception class name"), and this
is the one response body that does not follow that standard. The persisted copy is fine and useful —
it is the *response* half that is the inconsistency.

**Fix.** Log the full exception (already done, `JobScheduler:188`), persist the full string (already
done, and `last_error` is `TEXT` so there is no truncation risk), and put a stable summary in the
proto — the exception's simple class name, or a fixed `job_failed`. **Cost:** one line; the
`JobRun.error` field's meaning narrows, which is a docs change in `openapi.yaml`'s `JobRun` schema.

---

#### F20 — Small robustness gaps in the tick

**Perspectives:** Correctness · Concurrency & state
**Scope:** `framework`
**Location:** `server/zen-jobs/src/main/java/zen/jobs/JobScheduler.java:207-229`.

`recordStart` and `recordOutcome` both do `JobState state = JobState.byId(id); state.field = ...`
with no null check. If an operator deletes a `zen_jobs` row between `dueJobs()` and the record (the
row is explicitly documented as "the operator's" and editable without a redeploy), the tick dies with
an NPE inside a `QuarkusTransaction` — and in `recordStart`'s case, *before* the job body runs, so
the whole remaining tick is lost rather than one job. Separately, `runOne` catches `RuntimeException`
only; an `Error` propagates out of `runDueJobs` and skips every job after it in the same tick (the
`ticking` flag is correctly released by the `finally`, so this does not wedge the scheduler — worth
recording as a positive).

**Fix.** Null-check both, log at WARN and treat a vanished row as "not due". **Cost:** four lines.

---

### 3.4 `zen-ratelimit` (framework)

---

#### F21 — The burst table's overflow behaviour is an attacker-reachable global reset

**Perspectives:** Security · Concurrency & state · Performance
**Scope:** `framework`. **OWASP:** API4 Unrestricted Resource Consumption. **CWE:** CWE-770.
**Location:** `server/zen-ratelimit/src/main/java/zen/ratelimit/BurstLimiter.java:107-123`.

When `windows.size()` reaches `zen.ratelimit.max-tracked-subjects` (100 000) and sweeping expired
entries does not free room, the map is **cleared entirely** and a WARN is logged. The javadoc argues
the trade honestly — "a bounded, stated degradation, not a swallowed failure… the alternative is no
service" — and that argument is correct as far as it goes. What it does not say is that the
degradation is *reachable on demand*: an attacker with 100 000 source addresses (a commodity botnet,
or a single IPv6 /64, since `ClientAddress#normalize` keys on the full address) can hold the map
full and thereby reset **every legitimate caller's burst counter** on a cadence they choose. The
burst tier then contributes nothing for the duration of the attack.

The mitigation the javadoc names is real and load-bearing: the `auth` and `job-trigger` buckets have
a **durable** tier in Postgres that a map clear does not touch, so the credential-guessing and
retention-trigger surfaces stay protected. The bucket that is fully defeated is `GLOBAL`, which has
`durable-limit=0` by design — and `GLOBAL` is, by `RateLimitRule`'s own javadoc, "the denial-of-service
bucket". So the tier that protects against a flood is the one a flood can switch off.

This is a design trade to re-examine, not a bug to patch: the fix is not obviously "clear less". The
honest options are (a) evict least-recently-used rather than clearing, which bounds memory without
forgiving anyone and costs a `LinkedHashMap` + lock or a small sharded structure; (b) raise
`max-tracked-subjects` and pair it with a note about the real memory ceiling; or (c) accept it and
say so in `RateLimitRule.GLOBAL`'s javadoc, which is where an operator reading about the DoS bucket
would look. Any of the three is defensible; the current state is (c) minus the sentence.

**Cost:** (a) is contained to `BurstLimiter` and its test; it does not touch ADR-028/029's model,
since this is still one instance owning one counter.

---

#### F22 — The `auth` bucket writes to Postgres before authentication

**Perspectives:** Performance · Concurrency & state · Security
**Scope:** `framework`
**Location:** `server/zen-ratelimit/src/main/java/zen/ratelimit/RateLimitFilter.java:72-75` →
`DurableLimiter#increment`.

Every request to one of the six `AUTH_PATHS` that clears the burst tier performs an
`INSERT … ON CONFLICT DO UPDATE … RETURNING` in its own transaction, before any credential is
checked. That is deliberate and correct ("on the credential buckets it is the failures that
constitute the attack"), and it is bounded — 10 requests/minute/address gets through the burst tier,
so one address can force at most 10 writes/minute. Recorded here only as the explicit answer to the
§3b question "does any outbound/expensive operation happen pre-auth": it does, it is bounded, and the
bound is the burst tier. **No change recommended.** The dependency to keep in mind is the inverse
one, already documented on `DurableLimiter`: a Postgres failure here surfaces as a 500 rather than
being swallowed, which is the right call given role resolution needs the same database anyway.

---

### 3.5 `apps/zen_demo/zen_demo_server` (application scope — `zen_demo` only)

---

#### F7 — Everything JAX-RS enforces stops at the WebSocket upgrade

**Perspectives:** Security · Concurrency & state · Transport seam
**Scope:** the exposure is `application` (`DemoWebSocket`); the **missing control is `framework`**
(`CsrfFilter` and `RateLimitFilter` are both JAX-RS providers and structurally cannot cover a
websockets-next endpoint).
**OWASP:** API4 Unrestricted Resource Consumption; API8 Security Misconfiguration. **CWE:** CWE-1385
(missing origin validation in WebSockets).
**Location:** `apps/zen_demo/zen_demo_server/src/main/java/zen/demo/DemoWebSocket.java:46-48` and
`.../WebSocketConnections.java`.

**What is already right, and it is most of it.** The handshake is `@Authenticated`, so an anonymous
caller cannot open the socket. Frame and message sizes are capped in `application.properties` (64 KiB
each, with the reasoning that `quarkus.http.limits.max-body-size` does not apply to frames).
Concurrent connections are capped at 200 by `WebSocketConnections`, whose `tryAcquire` uses a proper
CAS loop and whose `SLOT_HELD` marker correctly avoids releasing a slot a refused connection never
claimed. The auto-ping/idle-timeout pairing is documented and consistent. This is a well-defended
endpoint and the javadoc enumerating "three things bound this socket" is accurate.

**What remains, and why it is worth naming.** The *only* thing standing between this endpoint and
cross-site WebSocket hijacking is `SameSite=Lax` on `zen_access_token`. A WebSocket handshake from a
cross-origin page is not a top-level navigation, so `Lax` withholds the cookie and the
`@Authenticated` check fails — correct today, and I verified the cookie is `Lax`
(`SessionService:101`). But:

- `quarkus.http.cors.*` does **not** apply to a WebSocket upgrade, so the carefully-configured
  origin allowlist (and `CorsCredentialsGuard` that protects it) is not in the path at all.
- There is **no explicit `Origin` check** on the upgrade.
- `CsrfFilter` cannot cover it, and `CsrfRules`' own javadoc names the exact future that breaks
  this: *"the day someone needs `SameSite=None` for an embedding."* On that day, every HTTP mutation
  stays protected by the double-submit token and **the WebSocket silently does not**, because the
  filter that implements the token is a JAX-RS provider.
- `RateLimitFilter` charges the handshake and then stops seeing the connection —
  `WebSocketConnections`'s javadoc says this plainly and is the mitigation. Note the limit is
  per-*instance*, not per-*address*: one caller within the handshake budget can hold all 200 slots
  and lock every other user out of the socket. At `--max-instances=1` that is the whole fleet.

**Fix.** An explicit `Origin` allowlist check on `@OnOpen` (the same list `quarkus.http.cors.origins`
already carries), so the defence is stated rather than inherited from a cookie attribute that an
application may later change. A per-address slot ceiling alongside the global one would close the
lock-out. Both belong in the framework the moment a second application opens a socket, which is
`WebSocketConnections`' own stated promotion trigger. **Cost:** contained to the app today; a
sentence in STANDARDS "Deployment model" or beside `CsrfRules`' `SameSite=None` note would keep the
coupling visible. No ADR needed for the `Origin` check; promoting the class would need one.

---

#### F23 — `DemoResource#profile` re-implements `@Authenticated`

**Perspectives:** Quarkus & CDI idiom
**Scope:** `application`
**Location:** `apps/zen_demo/zen_demo_server/src/main/java/zen/demo/DemoResource.java:108, 127-139`.

`@PermitAll` plus a hand-written `securityIdentity.isAnonymous()` check that throws
`AuthException.unauthorized`. The reason is sound and is documented — it yields a `ZenError` body
rather than Quarkus's bare 401 challenge, and the javadoc calls it "the demo's asserted error path".
It is worth noting anyway because it is a pattern an application author will copy, and copying it
means `@PermitAll` on endpoints that are not permitted to all — which weakens the signal that
`quarkus.security.jaxrs.deny-unannotated-endpoints=true` exists to create. The framework-shaped
answer is an `ExceptionMapper<UnauthorizedException>` in `zen-transport` (the same mapper F4 calls
for), after which `@Authenticated` would produce the `ZenError` body on its own and this hand-rolled
check could go. **Cost:** folds into F4.

---

## 4. §3b — GCP & Supabase integration, checked as its own pass

Performed separately from the general security pass, per the brief.

| Check | Result |
|---|---|
| Is `SupabaseAuthClient` the only code path to Supabase? | **Yes.** `grep -rn "supabase" --include=*.java server apps` outside `zen-identity` returns only test files (mock setup and assertions that the provider is *not* named in a client-facing message). No second hand-rolled call, no `supabase_flutter`-equivalent on the server |
| Does every method carry the fault-tolerance triplet? | **Yes** — all six methods carry `@CircuitBreaker`/`@Retry`/`@Timeout` with identical parameters. **But the 4xx/5xx split they encode does not work — see F1.** Any new method added by copy-paste inherits the same defect |
| Does `supabase.key` resolve to the **anon** key, not service-role? | **Yes, confirmed.** `Taskfile.yml:1078-1081` — `export SUPABASE_KEY="${SB_ANON_KEY}"`, with the comment "GoTrue requires the anon key as the `apikey` header". `Taskfile.yml:1980` prompts for `<publishable/anon key>`. **No `service_role` key appears anywhere in the repository** |
| Is `supabase.key` kept out of logs? | **Yes.** It reaches the wire only via `@ClientHeaderParam(name="apikey", value="${supabase.key}")`. No `quarkus.rest-client.logging.scope` is set in any profile, so the REST client's request logger is off; `%dev` raises only the `zen` category to DEBUG, which is jZen's own code and logs no header |
| Config classification still correct after `fcff867`? | **Yes.** `Taskfile.yml:2463` — `--set-secrets` covers exactly the seven genuine secrets (`SUPABASE_KEY`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `ZEN_JOBS_TRIGGER_TOKEN`). `SUPABASE_URL`, `SITE_URL`, `CORS_ORIGINS`, `AUTH_REDIRECT_URI(S)`, `SMTP_HOST/PORT/FROM` are plain `--set-env-vars`. The split matches the rule: the anon key is a secret, the project URL is not |
| Is the GoTrue `/user` call the only validation for a token jZen did not mint? | **Yes.** `IdentityService#exchangeLinkTokens:171-181` calls `authClient.getUser(bearer(accessToken))` **before** any cookie is issued. No code path anywhere does a local-only JWKS check on a link token. SmallRye JWT's local verification applies only to the `zen_access_token` cookie, i.e. a token jZen itself issued from a Supabase session |
| Does any Panache/JDBC query assume RLS makes it safe? (ADR-031) | **No.** `AdminUserResource` is `@RolesAllowed(admin)`; `UserRoleLoader`/`UserStore`/`UserRetentionService` are keyed on the authenticated `sub` or run inside a credentialed job. Every authorization decision is made in Java, which is exactly what ADR-031 requires since RLS does not apply to the application's own connection. `MigrateOnlyRunner#dataApiExposure` additionally asserts the outcome at deploy time |
| Service-account key material in the image or repo? | **None.** No `GOOGLE_APPLICATION_CREDENTIALS`, no `GoogleCredentials.fromStream`, no committed `*-service-account*.json`. Cloud Run authenticates implicitly as its attached service account |
| Outbound timeouts bounded, given `--concurrency=200` on one instance? | **Yes, but worth stating.** `connect-timeout=2000` + `read-timeout=2000` + `@Timeout(2000)`, with `@Retry(maxRetries=2, delay=500)`. Worst case per inbound request during a Supabase *timeout* (not 5xx) is 3 × 2000 + 2 × 500 = **7 s**, and the breaker does trip on that path, so the exposure self-limits after 10 requests. No unbounded call exists. This is acceptable; it is named because F1's fix will change which failures reach this path |
| Logging that GCP tooling would over-expose? | **None found.** No request/response body, JWT content or cookie value is logged at any level. `CsrfFilter:102-105` explicitly logs method+path and neither the token nor the address; `RateLimitFilter:83-85` logs bucket+tier and not the address; `EmailService#recipient` masks the local part. `%prod` sets `quarkus.log.console.json=true` and raises nothing |

---

## 5. §3a — Standards used, and the API-by-API walk

**Standards.** OWASP Top 10 **2021** for triage vocabulary. OWASP API Security Top 10 **2023** as the
load-bearing list, walked endpoint by endpoint below. OWASP **ASVS 5.0** (current major version at
time of review) for the code-verifiable chapters only — input validation, authentication, session
management, error handling & logging, cryptography in transit; the architectural chapters are the
companion review's. CWE as a secondary tag where it sharpens a finding.

**Every REST endpoint, against the API Top 10.** All of `AuthResource`, `AdminUserResource`,
`JobTriggerResource`, `AuthCallbackResource`, `WellKnownResource`, `DemoResource`, `HealthResource`.

| Endpoint | Auth | CSRF | Rate bucket | API-Top-10 result |
|---|---|---|---|---|
| `POST /api/v1/auth/login` | `@PermitAll` (credential is the body) | exempt (documented: runs before the cookie exists) | `AUTH` 10/min, 100/h | API2 ok; **F1** misclassifies provider outage |
| `POST /api/v1/auth/register` | `@PermitAll` | exempt (same) | `AUTH` | API2/API3 ok — enumeration defence at `IdentityService:120` is correct and deliberate; **F11** is the way it can silently stop working |
| `POST /api/v1/auth/restore-password` | `@PermitAll` | exempt | `AUTH` | API4 ok — it triggers an outbound email, bounded to 100/h/address |
| `POST /api/v1/auth/session` | `@PermitAll` | exempt | `AUTH` | API2 **ok, and well argued** — the credential is a token validated against Supabase before a cookie is issued (`exchangeLinkTokens`), and the token is never handed back to the page |
| `POST /api/v1/auth/password` | `@Authenticated` | **enforced** | `AUTH` | **F3** — A07/CWE-613, CWE-620 |
| `POST /api/v1/auth/logout` | `@PermitAll` | enforced when authenticated | `GLOBAL` | ok — the amplifier question is asked and answered in `RateLimitRule.AUTH`'s javadoc, and `AuthResource:221` gates the outbound call on a non-anonymous identity |
| `POST /api/v1/auth/refresh` | `@PermitAll` (credential is the refresh cookie) | exempt — **the reasoning is correct**: the CSRF cookie shares the access token's TTL, so enforcing here would cap every session at 1 h | `AUTH` | ok |
| `GET /api/v1/auth/identity` | `@PermitAll`, returns 204 when anonymous | n/a (safe method) | `GLOBAL` | API1 ok — reads the caller's own `sub` only. **F6** applies (cacheable identity document) |
| `GET /api/v1/admin/users` | `@RolesAllowed(admin)`, role from `RoleAugmentor` **not** the JWT | n/a | `GLOBAL` | API5 ok; API4 ok (`MAX_PAGE_SIZE=1000`, clamped in long arithmetic — the overflow comment is correct); **F4** on malformed params |
| `GET/PUT /api/v1/admin/users/{id}` | `@RolesAllowed(admin)` | enforced on PUT | `GLOBAL` | API1 n/a (admin may read any id); API3 ok — `update` applies only the editable subset and leaves `id`, `email` and timestamps read-only; **F4**, **F14** |
| `POST /api/v1/jobs/trigger` | shared secret, `MessageDigest.isEqual`, fails closed when unconfigured | exempt — **correct**, the caller is a machine with no cookie jar | `JOB_TRIGGER` 5/min, **20/h** | API2/API5 ok and unusually well reasoned; **F19** |
| `GET /auth/callback` | `@PermitAll` | n/a | none (outside `/api/`) | ok — it reads no token; the fragment never reaches the server |
| `GET /.well-known/assetlinks.json`, `/apple-app-site-association` | `@PermitAll` | n/a | none | ok — config values are constrained by a `SAFE` regex before hand-built JSON, and 404 until configured (the "platforms cache a failed association" reasoning is right) |
| `GET /api/v1/demo/ping`, `/terms` | `@PermitAll` | n/a | `GLOBAL` | ok — `readTerms`' locale is pre-narrowed to `{en,uk}` by `ZenLocales`, so no path traversal. **F6** applies |
| `GET /api/v1/demo/profile` | `@PermitAll` + manual check | n/a | `GLOBAL` | API1 ok (own `sub` only); **F23** |
| `GET /api/v1/health` | `@PermitAll`, deliberate | n/a | `GLOBAL` | ok |
| `WS /api/v1/demo/ws` | `@Authenticated` on the upgrade | **structurally uncoverable** | handshake only | **F7** — API4/API8, CWE-1385 |

**API9 Improper Inventory Management.** `/api/v1/demo/ws` cannot be expressed in OpenAPI and is
documented only in `DemoWebSocket`'s javadoc — inherent to the format, not a defect, but it means the
one endpoint that escapes every JAX-RS control is also the one absent from the inventory. All 14
component schemas in `openapi.yaml` are referenced by a resource, and every `@Schema(ref=...)` a
resource declares resolves to a schema — no orphans in either direction. Note that
`quarkus-smallrye-openapi` is deliberately excluded from the native build (a Maven `openapi` profile),
so `/openapi` is not served by anything that ships — correct, and already recorded as F15 of the
security-remediation work.

**ASVS 5.0, the code-verifiable chapters:**

- *Input validation.* Boundary validation is present where it matters (`RedirectTargets` exact-match,
  `WellKnownResource`'s `SAFE` regex, `AdminUserResource`'s `SORTABLE` whitelist and `MAX_PAGE_SIZE`,
  `quarkus.http.limits.max-body-size=1M`, the WebSocket frame caps). The gaps are **F4** (malformed
  query params → 500) and **F14** (unvalidated language tag).
- *Authentication.* JWKS-verified ES256 with the algorithm **pinned**
  (`smallrye.jwt.verify.algorithm=ES256`) and the issuer pinned to `${SUPABASE_URL}/auth/v1` — no
  algorithm-confusion surface. Roles come from the `users` table on **every** request via
  `RoleAugmentor`, never from the token, which is both the documented design and what the code does;
  `RoleAugmentor` fails closed (a failed load leaves the identity un-augmented, so `@RolesAllowed`
  refuses) and logs at WARN rather than swallowing. One observation, not a finding:
  `mp.jwt.verify.audience` is not configured, so the `aud` claim (`authenticated` on Supabase tokens)
  is unchecked; issuer + JWKS pinning makes this low-value to add, but it is the one standard claim
  check that is absent.
- *Session management.* Cookies are `httpOnly` (except the intentionally JS-readable `XSRF-TOKEN`),
  `Secure` in every profile but `%dev`/`%test`, `SameSite=Lax`, path `/`, with a 1 h access TTL and a
  7-day rotating refresh TTL — all correct. Logout revokes upstream and clears regardless of the
  revocation's outcome, which is the right ordering. The gap is **F3** (no revocation on password
  change).
- *Error handling & logging.* Strong throughout — see the §3b logging row — with the two exceptions
  **F4** (unmapped → bare 500) and **F19** (raw exception string in a response body).
- *Cryptography.* `MessageDigest.isEqual` for both secret comparisons (`CsrfFilter#matches`,
  `JobTriggerAuthenticator#isAuthorized`) — correct constant-time usage, CWE-208 closed.
  `UUID.randomUUID()` for the CSRF token is `SecureRandom`-backed (122 bits of entropy) — adequate.
  `DurableLimiter#hash` is SHA-256 with a domain separator, truncated to 128 bits, and is a
  privacy measure rather than a security primitive, which its javadoc states accurately. HSTS is set
  only over HTTPS, with `includeSubDomains`/`preload` correctly withheld while the hostname is
  unsettled.

---

## 6. F2 in full — the dependency gate is red

**Perspectives:** Security · Testing & maintainability
**Scope:** `framework` (the whole dependency graph; both reactors)
**OWASP:** A06 Vulnerable and Outdated Components. **CWE:** CWE-1395.

`task audit` output, verbatim:

```
==> Checking 259 Java dependencies against OSV
  FAIL io.netty:netty-codec-http@4.1.136.Final  GHSA-8c42-7qj2-3j46 [Moderate]
         Netty Vulnerable to Cache Poisoning and Information Disclosure via CORS Vary Header Overwrite
  FAIL io.netty:netty-handler@4.1.136.Final  GHSA-c4c3-7fpv-j4q5 [Critical]
         Netty: SNI Routing Bypass via Fragmented TLS ClientHello Causing Fallback to Default SslContext
  FAIL io.netty:netty-handler@4.1.136.Final  GHSA-fccg-mwvh-qqg4 [Moderate]
         Netty: Fragmented ClientHello records trigger quadratic pre-handshake reassembly in default SNI parsing
!! 2 vulnerable dependencies.
task: Failed to run task "audit": exit status 1
```

`scripts/audit-suppressions.txt` is empty, as its own header says it should be. Netty arrives
transitively from `quarkus-bom` 3.38.0 and is **not** pinned in `server/pom.xml` — which already
carries exactly this kind of override for `jackson-bom`, with the comment "Remove this block once
the platform's own jackson passes the gate", so the mechanism and its precedent are both in place.

**Applicability to jZen, honestly assessed** — this is the part a suppression would have to argue,
and it is why this is "fix or justify" rather than "patch now, panic":

- Both SNI advisories concern **server-side TLS termination** with SNI-based `SslContext` selection.
  jZen terminates no TLS: Cloud Run's frontend does, and `%prod` sets `quarkus.http.ssl-port=0`. The
  Critical is therefore very likely not reachable in this deployment.
- The `netty-codec-http` CORS one is more interesting, because jZen *does* run credentialed CORS
  (`access-control-allow-credentials=true`) — and because the advisory is literally about a missing
  `Vary` header, which is **F6** arriving from the other direction. Quarkus uses its own Vert.x CORS
  handler rather than Netty's `CorsHandler`, so it is probably also not reachable, but "probably" is
  the word doing the work.

**Fix.** Preferred: take the Quarkus platform version that ships a patched Netty. Interim: add a
`netty-bom` `<dependencyManagement>` override in `server/pom.xml` beside the existing `jackson-bom`
block, using the same comment style and the same "remove this once the platform catches up" note.
If neither is available yet, write the three suppression lines — but each must state the
reachability argument above, which is what `audit-suppressions.txt`'s format is designed to force.
**Cost:** a version bump plus a full `task test` run; no code change. Leaving the gate red is the one
outcome to avoid, because a gate that is known-red stops being read.

---

## 7. What this review found no fault with

Stated because the brief asks findings to be grounded, and a clean result on a thing that is usually
broken is itself a finding:

- **The Jandex and no-Jackson invariants are fully honoured**, and are backed by wiring tests in the
  app module rather than by memory. This is the single best-defended property in the codebase.
- **Roles are never read from the JWT.** Traced end to end: SmallRye JWT sets the principal from
  `sub`, `RoleAugmentor` loads the row, `@RolesAllowed(admin)` reads the augmented identity. No
  shortcut exists anywhere.
- **No injection of any kind.** No string-concatenated SQL/JPQL, no `exec`, no untrusted
  deserialization outside the proto pipeline (which `ignoringUnknownFields` makes mass-assignment
  safe), no hand-built JSON that is not regex-constrained first.
- **No secret reaches a log or a response body**, and the discipline behind that (user ids instead of
  emails, masked local parts, bucket+tier instead of addresses) is consistent across five modules.
- **The two startup guards** (`CorsCredentialsGuard`, `RateLimitAddressGuard`) are the right shape
  for a single-instance Cloud Run deployment: a misconfiguration costs a failed deploy instead of an
  open API, because a revision that throws during boot never receives traffic.
- **The `--max-instances=1` assumptions are all sound and all argued.** `BurstLimiter`'s map,
  `JobScheduler`'s `AtomicBoolean` overlap flag, and `WebSocketConnections`' counter are each correct
  by construction, each name ADR-028's trigger for externalising, and none was flagged.
  `WebSocketConnections`' argument that a per-instance socket count is the *only* meaningful count
  is correct and goes further than the others.
- **`RoleAugmentor`'s per-request row is carried forward correctly**, including the id comparison
  (`IdentityService:292-294`) that keeps it from answering a different user's id with the caller's
  own row — that comparison is the BOLA guard, and it is already right.
- **`UserRoleLoader`'s latch is an instance field with an explicit note that a `static` one would be
  a native-image defect.** That is a real GraalVM trap, correctly avoided and correctly explained.
- **Active-record Panache, runtime server config, and the framework/app split** are all deliberate
  and all correct for what this is. No repository layer, second ORM, or horizontal-scaling machinery
  is recommended anywhere in this review.

---

## 8. Suggested order of work

1. **F2** — the gate is red today; either bump or write the argued suppressions.
2. **F1** — a provider outage currently presents as "wrong password" to every user.
3. **F4** — one framework `ExceptionMapper` closes a contract hole and is the prerequisite for F8's
   and F23's clean fixes.
4. **F5** and **F6** — two small, well-bounded changes in `zen-transport`/`zen-ratelimit` that each
   make an existing stated rule enforceable.
5. **F3** — the largest piece of work here, because the recovery-vs-ordinary-change asymmetry is a
   real design decision and touches the proto contract; it deserves an ADR.
6. **F7** — the explicit `Origin` check, before anyone needs `SameSite=None`.
7. The rest, in module order, as the files are next opened.
