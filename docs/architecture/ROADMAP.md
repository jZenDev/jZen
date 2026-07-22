# jZen Roadmap

Migration sequence from the current skeleton to a fully re-engineered DartZen. Each step
is independently shippable and independently testable — a change to one package must be
provable in isolation (the atomic-upgrade rule in [`STANDARDS.md`](./STANDARDS.md)).

Status legend: ✅ done · ▶ next · ☐ pending

## Step 0 — Skeleton ✅

Delivered by this pass. No migrated source; structure and orchestration only.

- Directory layout, multi-module Maven backend, Dart pub workspace, `admin`
  scaffold, `supabase/config.toml`, the four architecture docs, and `Taskfile.yml`.
- **Verified:** `server/` builds all backend modules green (`./mvnw package`); the Dart
  workspace resolves (`dart pub get`); `admin` builds (`pnpm build`); the Taskfile
  parses and `task doctor` reports the toolchain; the `sync:contracts` gate catches a
  drifted generated file.

## Step 1 — Walking skeleton ✅

The first executable proof of the hardest mechanism: dual-mode transport end to end.
Delivered.

- `proto/zen/v1/health.proto` — one `HealthStatus` message, compiled to Java in the new
  `zen-proto` leaf module (a dependency-free module for generated code, so the protobuf
  plugin never has to resolve an unbuilt internal jar).
- `zen-transport` seam: `ZenTransportFormat`, `ZenTransportFilter` (@PreMatching, gated
  to `api/`), `ZenTransportResponseFilter`, and Protobuf + ProtoJson
  `MessageBodyWriter`/`Reader` for `com.google.protobuf.Message`.
- `zen-app` `HealthResource` returning `Response` with an `@APIResponse` ref; static
  `META-INF/openapi.yaml` supplies the clean schema.
- **TA-1 spiked and resolved.** A bare-proto return type produced 130+ garbage schemas;
  the `Response` + static-merge approach yields exactly 1 clean `HealthStatus` schema,
  which `openapi-typescript` turns into a usable TS type. Two findings folded into
  BLUEPRINT.md / STANDARDS.md: drop server-side `quarkus-rest-jackson`, and every library
  module needs a Jandex index.
- The negotiation header is `X-Zen-Transport` (renamed from DartZen's `X-DZ-Transport`).
- **Verified:** a `@QuarkusTest` (`HealthResourceTest`, Dev Services Postgres) asserts
  both modes green; a live server confirmed the exit test —
  `curl -H "X-Zen-Transport: protobuf"` returns 20 bytes of parseable protobuf,
  `-H "X-Zen-Transport: json"` returns `{"status":"ok","service":"zen-app",...}` canonical
  proto3 JSON, both echoing the negotiated `X-Zen-Transport` header; no header defaults to
  JSON.

## Step 2 — Core Dart packages ✅

Port the foundation, Firestore-free.

- `zen_core` ← `dartzen_core`, stripping GCP env constants
  (`../DartZen/packages/dartzen_core/lib/src/dartzen_constants.dart:20-62`).
- `zen_localization` ← `dartzen_localization`, made Dart-pure (**TA-3**).
- `zen_transport` ← `dartzen_transport`: keep the negotiation (header renamed
  `X-Zen-Transport`); replace the msgpack codec with generated protobuf; delete the dead
  `ZenTransport` facade, the duplicate middleware, and the duplicate export barrel (all
  listed in [`BLUEPRINT.md`](./BLUEPRINT.md)); fix the `ZenClient` bugs (**TA-6**).
- **Keep the compile-time config (`String.fromEnvironment`) and conditional-import
  selectors (**TA-7**)** — they tree-shake native/web code out of the wrong bundle and are
  mandatory for the client. Rename `DZ_*` build defines → `ZEN_*`.
- Land packages flat under `client/` and add each to `client/pubspec.yaml`'s `workspace:`
  list as it arrives.
- **Verified:** all three landed flat under `client/` and registered in the workspace at
  `0.1.0`. The `X-DZ-Transport` → `X-Zen-Transport` header, the `msgpack` → `protobuf`
  binary codec (generated Dart messages committed under
  `client/zen_transport/lib/src/generated/`, `writeToBuffer`/`toProto3Json`), and the
  compile-time `selectDefaultCodec()` selector are all in place; the `ZenTransport` facade,
  the Shelf middleware, the duplicate barrels, the envelope, and the `shelf` dep are gone.
  Both **TA-6** bugs are fixed (default codec via `selectDefaultCodec`; a decode failure
  surfaces a `ZenError` from `common.proto`, never `null`) and **TA-3** (localization is
  Dart-pure, `flutter` dev-only). `task doctor` is green; `task build:client` analyzes
  clean; `task test:client` passes 179 tests (`zen_core` 85, `zen_localization` 55,
  `zen_transport` 39); `task test:client:matrix` proves the codec selector per
  `ZEN_ENV`/platform (dev→json, prd-native→protobuf, web→json); `task sync:contracts`
  reports "Contracts in sync" and its drift gate rejects a hand-edited generated file.

## Step 3 — Identity on Supabase ✅

- Backend: port `SupabaseAuthClient` (re-pointed at Supabase Auth / GoTrue REST),
  `SessionService` (un-hacked, **TA-4** — normal `zen_access_token` cookie, no `__session`
  packing, no `SessionFilter`), `RoleAugmentor` (role loaded from the `users` table, not the
  JWT), and the `User` entity into `zen-identity`. A `MapStruct` mapper maps `User` → the
  `Identity` proto; the `AuthResource` (login, register, restore-password, logout, **refresh**,
  get-current-identity) lives in `zen-app` and returns typed proto, with a `ZenError` error
  path. Flyway `V1__init_identity.sql` + `V2__row_level_security.sql` (the RLS guarded on
  `auth.uid()` so it is a no-op on the Dev Services database). The `users` table keeps the
  payment (`is_premium`) and GDPR (`analytics_consent`, `deletion_warning_*`) compliance
  columns as first-class scaffold concerns (see [`BLUEPRINT.md`](./BLUEPRINT.md) "Persistence").
- Dart: `zen_identity` ← `dartzen_identity`, re-pointed from Identity Toolkit to
  Supabase Auth, with a `SupabaseIdentityRepository` that implements the declared
  `IdentityRepository` interface exactly (**TA-5**) over `zen_transport`'s `ZenClient`,
  discarding the Firestore repository/mapper/token-verifier.
- `zen_ui_navigation` ← `dartzen_ui_navigation` (adopted as-is; `dz*` platform constants and
  path deps renamed) and `zen_ui_identity` ← `dartzen_ui_identity` (provider-agnostic; the
  Supabase re-point is a one-line `identityRepositoryProvider` override in the app), plus
  their two example apps. New proto: `proto/zen/v1/identity.proto`
  (`Identity`, `LoginRequest`, `RegisterRequest`, `RestorePasswordRequest`).
- **Verified:** `task test:server` is green — `AuthResourceTest` round-trips
  login/register/logout as typed proto in **both** transport modes, asserts the TA-4 cookie
  (`zen_access_token` / `zen_refresh_token`, no `__session`, no `access|refresh` packing) and
  a `ZenError` error path, and `RoleAugmentorTest` proves the role is loaded from the `users`
  table (no JWT present). `task test:client` passes the ported identity/UI suites and the
  `SupabaseIdentityRepository` tests. `task sync:contracts` regenerates and its drift gate is
  green; `dart analyze` is clean.

## Step 4 — the reference app: showcase + living test stand ✅

> **Reframed during delivery (see [`DECISIONS.md`](./DECISIONS.md) ADR-001).** jZen is a
> **framework**: `server/` + `client/` are libraries, and the reference app is a full-stack
> example under `apps/zen_demo/{zen_demo_client, zen_demo_server}` that *assembles* them — not a
> Flutter package driving "the one backend." `zen_demo_server` is the relocated `zen-app`; auth
> moved into the `zen-identity` framework library so every app inherits it. Because both sides
> assemble the framework, `task test:e2e` is a **framework** end-to-end gate (each product app,
> e.g. `workspaces`, gets its own).

`zen_demo` is not throwaway sample code. It has two first-class jobs, both inherited from
DartZen's ZenDemo ("the breathing minimum... a real end-to-end system. No mocks. No stubs.
No TODOs." — `../DartZen/apps/ZenDemo/README.md`) and kept as hard requirements:

1. **Product showcase** — the canonical, runnable demonstration of jZen: the Flutter UI
   packages, Supabase auth, localization, and both transport modes, driving the real
   backend. It is what a newcomer runs first and what the README points to.
2. **Living end-to-end test stand** — it exercises the *real* Quarkus + Supabase stack, no
   stubs, so it is the integration/e2e harness the unit tests can't be. It is wired into
   CI: a green `zen_demo` run is a release gate.

Deliverables:

- `client/zen_demo` ← `../DartZen/apps/ZenDemo/dartzen_demo_client`, calling the Quarkus
  server instead of the deleted Shelf server.
- `../DartZen/apps/ZenDemo/dartzen_demo_contracts` → `proto/zen/v1/*.proto` (the 7 contract
  files become proto messages, consumed via generated Dart clients).
- `dartzen_demo_server` is **deleted**, not ported — the Quarkus backend is the server now.
  The demo endpoints it satisfies are `GET /api/v1/demo/{ping,terms,profile}` plus the
  **WebSocket echo** at `/api/v1/demo/ws`.
- **The WebSocket echo is a first-class product feature**, not a test fixture: jZen ships a
  Quarkus `quarkus-websockets-next` endpoint and drives it from `zen_demo` through
  `zen_transport`'s `ZenWebSocket` (binary Protobuf frames). It is part of what the reference
  app demonstrates and what the e2e stand asserts.
- **End-to-end coverage, asserted:** login/register/logout via Supabase, a round-trip in
  **both** transport modes (`X-Zen-Transport: json` and `protobuf`), a localized surface, the
  WebSocket echo, and at least one error path returning a `ZenError`. No mocks — it hits the
  live stack.
- **Taskfile targets:** `task run:demo` (boot Supabase + server + the demo for a manual
  walkthrough) and `task test:e2e` (headless: bring the stack up, run the demo's
  integration suite, tear down, propagate the exit code). `test:e2e` joins `task test` and
  the CI gate.

## Step 5 — Admin panel ✅

- Split the admin into a reusable framework scaffold (`@jzen/admin-core` in `admin/`:
  data provider, auth provider, login page) and a per-app panel
  (`apps/zen_demo/zen_demo_admin`) that registers domain resources typed off the generated
  `openapi-typescript` schema (ADR-005).
- Real `users` resource (list / show / edit) driven by a framework `AdminUserResource` in
  `zen-identity`; `ra-data-simple-rest` pagination wired to the backend's `Content-Range`
  convention (a bare JSON array body + a declared `AdminUser` proto per element).
- Supabase session auth via the framework endpoints (`POST /auth/login`, `GET /auth/identity`,
  `POST /auth/logout`), httpOnly cookie, admin-role gated.
- The Flutter `dartzen_ui_admin` is confirmed dropped (not migrated).

## Step 6 — Email ✅

> **Shaped during delivery (see [`DECISIONS.md`](./DECISIONS.md) ADR-007).** The framework sends,
> the application speaks: `zen-email` owns the mechanism, each app owns every word a user reads.
> `zen-identity` publishes CDI events instead of sending mail, so it gains no dependency on
> `zen-email` and an app opts in by observing.

- `zen-email` `EmailService` (new) over `quarkus-mailer`, wiring Brevo via `SMTP_HOST` — Brevo is
  only an SMTP host, so nothing in the Java is provider-specific. `send(LocalizedEmail)` resolves
  the locale, renders, sends, and **never throws**: mail is a side effect of a business action and
  must never fail it.
- **Localized from the start (TA / BLUEPRINT "Email"):** per-locale Qute templates
  (`mail/welcome_{en,uk}.html`, `mail/deletion_warning_{en,uk}.html`,
  `mail/final_warning_{en,uk}.html`) with subjects from a Qute `@MessageBundle`
  (`MailMessages` + the `@Localized("uk")` variant); `EmailService` resolves the recipient's locale
  from `users.language`, seeded at registration from `Accept-Language`. The supported set lives once,
  in `zen.core.i18n.ZenLocales` (`{en, uk}`, fallback `en`), which `DemoResource` now also uses.
  BugEater's English-only hardcoded mail strings are not carried forward.
- **On the client, the locale is ambient too:** `ZenClient` takes a `language` callback and emits
  `Accept-Language` on every request beside `X-Request-ID` and `X-Zen-Transport`, so the language
  the user picked in `zen_demo` reaches `POST /auth/register` without any repository growing a
  locale argument (and a per-call `headers:` entry still overrides it). Without this the reference
  app could not actually demonstrate the feature: every registration from the UI would have landed
  as `en`.
- **GDPR data retention**, using the `users` columns the scaffold already carried: `UserRetentionJob`
  + `UserRetentionService` in `zen-identity` warn a dormant account, warn it finally, then anonymise
  it, publishing `AccountDeletionWarning` for the app to localize. **Off by default** (the library's
  own `META-INF/microprofile-config.properties`); `zen_demo_server` enables it in dev, and pins it
  off in `%prod` because an in-process cron cannot work under `--min-instances=0` — see ADR-007 and
  the new STANDARDS "Deployment model" rule. Signing back in clears the warning stamps — the donor
  deleted returning users anyway, which is a bug, not a behaviour.
- **Left open on purpose, and tracked as step 7a below:**
  retention therefore does not yet *run* in production, so the GDPR obligation is not discharged
  there. Step 6 delivers the cycle and proves it; step 7a delivers the guaranteed trigger that
  makes it fire, and closes the related hole where a warning that failed to send still advances the
  clock toward anonymisation.
- **Verified:** `task build:server`, `build:client` (`dart analyze` clean) and `build:apps` green;
  the backend suite is **34 tests, 0 failures** (11 new), and `task test:client` is green with 5 new
  Dart tests pinning the ambient `Accept-Language` (emitted, omitted when unset, re-read per request
  so a mid-session switch applies, overridable per call, and carried by `registerWithEmail`). `WelcomeEmailTest` asserts the Ukrainian subject *and* body for
  `Accept-Language: uk-UA`, English for none or an unsupported tag, that the header seeds
  `users.language`, and that a repeat signup greets nobody twice; `UserRetentionTest` walks the
  whole cycle including the premium exemption and the `anon!_%` escape; `EmailFailureTest` proves
  registration returns 200 with the mail server unreachable. No test touches SMTP — the mailer is
  mocked and `MockMailbox` is what the assertions read. Manually confirmed against live Supabase +
  Quarkus dev: `uk-UA` → `users.language = uk` + "Ласкаво просимо до jZen", `en-US` → `en` +
  "Welcome to jZen".

## Step 7 — Guaranteed scheduled work, deferred packages, framework improvements ☐

The first item is **required before any production deployment that stores personal data**; the
rest are done in isolation, when a consumer needs them (packages) or when the framework earns the
change (improvements).

### 7a — Guaranteed scheduled work (`zen-jobs`) — REQUIRED, not deferred

**Why this is a blocker, not a nice-to-have.** Step 6 shipped the GDPR retention cycle but had to
pin it `off` in `%prod` (ADR-007): Cloud Run runs `--min-instances=0`, so an in-process
`@Scheduled` has no thread alive at the hour it names — see STANDARDS "Deployment model". The
obligation to erase dormant personal data is therefore **not discharged in production today**.
This step is what discharges it. Retention is only the first caller; the mechanism is general.

**The shape is already proven in the donor** — `../DartZen/packages/dartzen_jobs`, where an
external service watches the schedule and calls the application's endpoints:

- Three job types (`.../lib/src/models/job_type.dart`): `endpoint` (event-driven, Cloud Tasks),
  `scheduled` (cron, Cloud Scheduler), `periodic` (interval).
- **The Master Job** (`.../lib/src/master_job.dart`): *one* Cloud Scheduler entry hits
  `/jobs/trigger` every minute; the master reads the enabled periodic jobs, computes which are due
  from `interval` + `lastRun`, and runs them sequentially. One trigger, one container start, N jobs.
- **Job state is persisted, not compiled in** (`.../lib/src/models/job_config.dart`: `enabled`,
  `cron`, `interval`, `lastRun`, `nextRun`, `lastStatus`, `maxRetries`, `startAt`/`endAt`,
  `skipDates`, `dependencies`, `priority`), so a schedule changes or a job is disabled without a
  redeploy.
- The trigger call carries a Google identity token
  (`.../lib/src/cloud_tasks_adapter.dart:48`).

**What jZen keeps, and what it must change:**

- **Due-ness is computed from `last_run_at`, never from "the timer fired."** This single property
  is what turns best-effort into a guarantee: a tick missed while scaled to zero, mid-deploy, or
  during an outage is simply caught up on the next one. Without it there is no compliance story,
  only a hope.
- Persist job state in **Postgres (Flyway + Panache)**, not Firestore — jZen has no Firestore and
  Flyway is the single migration authority.
- **The job body stays a plain callable** so the trigger is a deployment choice rather than a code
  one. `UserRetentionJob.runCycle()` is already written this way and becomes the first registered
  job.
- **One trigger endpoint with master-style batching.** N Cloud Scheduler entries would mean N cold
  starts, which fights the single-instance cost model in STANDARDS.
- **At-least-once, therefore idempotent.** Cloud Scheduler retries; every job must be safe to run
  twice. Retention already is (the stamps guard re-sending), but it becomes a stated contract.
- **Overlap guard.** At `--max-instances=1` an in-process lock is sufficient, by the same reasoning
  that makes in-process state valid; raising `--max-instances` is the trigger to move to a Postgres
  advisory lock.
- **Open design question to settle in an ADR: authenticating the trigger.** Cloud Scheduler sends a
  Google OIDC token, but `mp.jwt.*` is already bound to Supabase's issuer and JWKS. Either add a
  second verification path or use a shared secret from Secret Manager. Decide before building.
- **Dev keeps the in-process cron** (already the case — `%dev` on, `%prod` off), so local work needs
  no GCP. This mirrors the donor's development/production executor split.
- **Observability.** A run records start, outcome, and duration (the donor emits
  `job.started`/`succeeded`/`failed`); jZen has Micrometer and structured logs, and `last_run_at` /
  `last_status` are queryable — and worth surfacing in the admin panel.
- **Close the GDPR correctness hole this step exposed.** The retention cycle currently advances
  `deletion_warning_sent_at` / `final_warning_sent_at` whether or not the message was delivered,
  because `EmailService` is deliberately non-fatal — so a broken relay would anonymise people who
  were never warned. Durable job state gives that fix somewhere to live: record the delivery
  outcome and gate anonymisation on a warning that actually went out.

**Done when:** retention runs in production on a schedule that is provably not best-effort — a tick
missed while scaled to zero is caught up, a run is visible after the fact, and no account is ever
anonymised without a delivered warning.

### Deferred package ports — port only when a consumer needs them
- `dartzen_telemetry` → a Panache-backed store (its `TelemetryStore` is the one clean
  store abstraction in DartZen — `../DartZen/packages/dartzen_telemetry/lib/src/store/telemetry_store.dart:4`).
  Pairs naturally with 7a, which needs somewhere to record job runs.
- `dartzen_executor`, `dartzen_payments`, `dartzen_ai`, `dartzen_cache`,
  `dartzen_storage` (→ Supabase Storage / S3) — no committed target until demanded.

### Framework improvements — deferred but committed to a plan

- **Typed, generated client i18n** (mirrors the server's Qute `@MessageBundle`; see
  [`DECISIONS.md`](./DECISIONS.md) ADR-004). Today `zen_localization` is a hand-rolled service over
  per-locale JSON with runtime **string keys** — the `easy_localization` camp, not idiomatic Flutter.
  Evaluate and migrate to a **typed, generated** approach: Flutter's official `intl` + **ARB** +
  `flutter gen-l10n` (generates a compile-checked `AppLocalizations`), or `slang` (typed accessors
  from JSON/YAML). *Effective Dart*'s "typed over stringly-typed" and consistency with the server
  (`@MessageBundle`) both point here. Scope: decide `zen_localization`'s fate (replace, wrap, or
  retire it), migrate the app clients (`apps/*/*_client`) and the `zen_ui_*` package l10n, keep
  `{en, uk}`, and update the localization docs. A framework-wide change, so it is its own effort,
  not folded into app work.

## Step 8 — Standalone: sever the umbilical ☐

The migration is done; jZen becomes its own product with no trace of its donors.

- **Strip every DartZen and BugEater reference** from source comments, `pom.xml` /
  `pubspec.yaml` prose, `application.properties` comments, and these four docs. No
  `../DartZen/…` or `../BugEater/…` paths, no "ported from", no "donor", no ADR-034
  archaeology — anything a reader needs must be explained on jZen's own terms.
- **Rewrite the docs to stand alone.** `MANIFESTO` states jZen's philosophy without
  "DartZen re-engineered"; `BLUEPRINT` describes the architecture as-built; the TA section
  (which only ever documented migration gaps) is deleted or folded into `STANDARDS` as
  plain rules. Delete the MANIFESTO "Provenance, and its expiry" note — it will have
  expired.
- **Rename any lingering `DZ_*` / `dartzen_*` / `zen-*`-vs-`DartZen` residue** so the
  vocabulary is uniformly jZen.
- **Verification:** `grep -ri "dartzen\|bugeater\|X-DZ" .` (outside git history) returns
  nothing.

This step is the reason STANDARDS mandates source citations *now*: they are removable
scaffolding, and this is where the scaffolding comes down.

## Step 9 — Documentation: READMEs ☐ (final step)

Written last, so they describe jZen as-built and in its own voice — no donor references
(Step 8 has already removed them). The `docs/architecture/` set stays the deep reference;
these READMEs are the front door.

- **Root `README.md`** — the entry point for both audiences:
  - *What jZen is* — one-paragraph product description and the philosophy in brief (link
    to `docs/architecture/MANIFESTO.md`).
  - *See it run* — lead with `zen_demo`: `task run:demo` as the fastest way to watch the
    whole product work end to end, framed as both the showcase and the living test stand.
  - *Repository map* — `server/` / `client/` / `admin/` / `proto/` / `supabase/`, one line
    each, linking to their own READMEs.
  - *Quick start (users)* — prerequisites, `task doctor`, `task run:all`, where each
    surface comes up (API, admin panel, demo app) and how to reach them.
  - *Quick start (developers)* — clone → `task deps` → `task build` → `task test`; the
    contract-first workflow (edit `.proto` → `task sync:contracts`); how to add an
    endpoint or a package; the golden rules (generated files are committed, never
    hand-edited; client config is compile-time); `task test:e2e` runs `zen_demo` against
    the real stack as the integration gate.
  - *Deploy* — `task deploy:cloudrun`, the single-instance cost model, required secrets.
  - Badges/licence, contribution pointer, link to `docs/architecture/`.
- **Per-project READMEs**, each self-contained:
  - `server/README.md` — module map (`zen-proto/core/transport/identity/email/app`), the
    dual-mode transport seam, running/testing (Dev Services), the "no rest-jackson" and
    "Jandex on every library module" rules, config reference.
  - `client/README.md` — the pub workspace, package list and responsibilities, the
    compile-time-config / bundle tree-shaking rule and `ZEN_*` build defines, per-platform
    run/build.
  - `client/zen_demo/README.md` — its dual role (product showcase + living e2e test
    stand), what it exercises end to end (auth, both transport modes, localization, an
    error path), `task run:demo` vs `task test:e2e`, and the "no mocks — hits the real
    stack" rule.
  - `admin/README.md` — ReactAdmin app, generated `openapi-typescript` types, dev server
    and proxy, adding a resource.
  - `proto/README.md` — proto is the source of truth, `zen.v1` layout and versioning,
    `task sync:contracts` and the drift gate, how each language consumes the output.
  - `supabase/README.md` — local stack, ports, migrations, auth/JWKS wiring.
- **Verification:** a new contributor can go from clone to a running `task run:all` using
  only the root README; each sub-project README stands on its own; every command shown
  actually runs.

## Hard constraint — the donor repos are read-only

`../DartZen` and `../BugEater` are **reference sources only**. Nothing in this migration
ever modifies, moves, or deletes a single file in either — no edits, no "quick fixes", no
cleanup, not even formatting. All work happens inside `jZen/`. They are studied and copied
from, never touched. (This is also why the citations above are safe: the paths they point
at will not move under us.)

## Explicitly out of scope

Never migrated: `dartzen_server`, `dartzen_firestore` (deleted at step 2); all BugEater
business domain (courses, gamification, quiz, lesson, practice, news, leaderboard); all
136 BugEater Qute `*PageResource` HTML endpoints; `firebase.json` / `.firebaserc`.
