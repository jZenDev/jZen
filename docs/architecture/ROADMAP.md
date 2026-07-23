# jZen Roadmap

The build order, from the first skeleton to the finished framework. Each step
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
- **The OpenAPI/protobuf problem spiked and resolved.** A bare-proto return type produced 130+
  garbage schemas;
  the `Response` + static-merge approach yields exactly 1 clean `HealthStatus` schema,
  which `openapi-typescript` turns into a usable TS type. Two findings folded into
  BLUEPRINT.md / STANDARDS.md: drop server-side `quarkus-rest-jackson`, and every library
  module needs a Jandex index.
- The negotiation header is `X-Zen-Transport`.
- **Verified:** a `@QuarkusTest` (`HealthResourceTest`, Dev Services Postgres) asserts
  both modes green; a live server confirmed the exit test —
  `curl -H "X-Zen-Transport: protobuf"` returns 20 bytes of parseable protobuf,
  `-H "X-Zen-Transport: json"` returns `{"status":"ok","service":"zen-app",...}` canonical
  proto3 JSON, both echoing the negotiated `X-Zen-Transport` header; no header defaults to
  JSON.

## Step 2 — Core Dart packages ✅

Port the foundation, Firestore-free.

- `zen_core`: the result types, logging, value objects, guards, and the compile-time
  `ZEN_*` env/platform constants. No GCP or Firebase constants.
- `zen_localization`, a runtime string-key localization service. *(Retired in step 7b —
  see below and [`DECISIONS.md`](./DECISIONS.md) ADR-009.)*
- `zen_transport`: the `X-Zen-Transport` negotiation, a generated-protobuf binary codec, and
  no envelope. `ZenClient` takes its default format from `selectDefaultCodec()` and surfaces a
  `ZenError` on a decode failure rather than a silent null.
- **Compile-time config (`String.fromEnvironment`) and conditional-import selectors** —
  they tree-shake native/web code out of the wrong bundle and are mandatory for the client.
- Land packages flat under `client/` and add each to `client/pubspec.yaml`'s `workspace:`
  list as it arrives.
- **Verified:** all three landed flat under `client/` and registered in the workspace at
  `0.1.0`. The `X-Zen-Transport` header, the Protobuf
  binary codec (generated Dart messages committed under
  `client/zen_transport/lib/src/generated/`, `writeToBuffer`/`toProto3Json`), and the
  compile-time `selectDefaultCodec()` selector are all in place; the `ZenTransport` facade,
  the envelope are gone. Both client invariants hold (default codec via `selectDefaultCodec`;
  a decode failure surfaces a `ZenError` from `common.proto`, never `null`).
  `task doctor` is green; `task build:client` analyzes
  clean; `task test:client` passes 179 tests (`zen_core` 85, `zen_localization` 55,
  `zen_transport` 39); `task test:client:matrix` proves the codec selector per
  `ZEN_ENV`/platform (dev→json, prd-native→protobuf, web→json); `task sync:contracts`
  reports "Contracts in sync" and its drift gate rejects a hand-edited generated file.

## Step 3 — Identity on Supabase ✅

- Backend: port `SupabaseAuthClient` (re-pointed at Supabase Auth / GoTrue REST),
  `SessionService` (one normally-named `zen_access_token` cookie per token, no packing and no
  session filter), `RoleAugmentor` (role loaded from the `users` table, not the
  JWT), and the `User` entity into `zen-identity`. A `MapStruct` mapper maps `User` → the
  `Identity` proto; the `AuthResource` (login, register, restore-password, logout, **refresh**,
  get-current-identity) lives in `zen-app` and returns typed proto, with a `ZenError` error
  path. Flyway `V1__init_identity.sql` + `V2__row_level_security.sql` (the RLS guarded on
  `auth.uid()` so it is a no-op on the Dev Services database). The `users` table keeps the
  payment (`is_premium`) and GDPR (`analytics_consent`, `deletion_warning_*`) compliance
  columns as first-class scaffold concerns (see [`BLUEPRINT.md`](./BLUEPRINT.md) "Persistence").
- Dart: `zen_identity`, with a `SupabaseIdentityRepository` that implements the declared
  `IdentityRepository` interface exactly over `zen_transport`'s `ZenClient`.
- `zen_ui_navigation` (the adaptive navigation shell) and `zen_ui_identity`
  (provider-agnostic; choosing Supabase is a one-line `identityRepositoryProvider` override in
  the app), plus their two example apps. New proto: `proto/zen/v1/identity.proto`
  (`Identity`, `LoginRequest`, `RegisterRequest`, `RestorePasswordRequest`).
- **Verified:** `task test:server` is green — `AuthResourceTest` round-trips
  login/register/logout as typed proto in **both** transport modes, asserts the cookies
  (`zen_access_token` / `zen_refresh_token`, one token each, nothing packed) and
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

`zen_demo` is not throwaway sample code. It is the breathing minimum: a real end-to-end
system, no mocks, no stubs, no TODOs. It has two first-class jobs, both hard requirements:

1. **Product showcase** — the canonical, runnable demonstration of jZen: the Flutter UI
   packages, Supabase auth, localization, and both transport modes, driving the real
   backend. It is what a newcomer runs first and what the README points to.
2. **Living end-to-end test stand** — it exercises the *real* Quarkus + Supabase stack, no
   stubs, so it is the integration/e2e harness the unit tests can't be. It is wired into
   CI: a green `zen_demo` run is a release gate.

Deliverables:

- `zen_demo_client`, a Flutter app assembling the framework packages against the Quarkus
  server.
- The demo's wire contracts as proto messages in `proto/zen/v1/*.proto`, consumed through
  generated Dart clients.
- The demo endpoints `GET /api/v1/demo/{ping,terms,profile}` plus the **WebSocket echo** at
  `/api/v1/demo/ws`.
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
- Administration is react-admin only; there is no Flutter admin panel.

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
  No mail string is hardcoded English.
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
  the new STANDARDS "Deployment model" rule. Signing back in clears the warning stamps, so an
  account whose owner has demonstrably returned falls out of the deletion pipeline.
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

## Step 7 — Guaranteed scheduled work, deferred packages, framework improvements ✅

The first item was **required before any production deployment that stores personal data** and is
**done** (7a below), as is the one committed framework improvement (7b, typed client i18n). The
candidate-capability list is now **settled rather than open** (7c): every candidate has a
disposition, the verdict on all six remaining ones is "no", and nothing was added. See
[`DECISIONS.md`](./DECISIONS.md) ADR-010. **The step is complete and Step 8 is unblocked.**

### 7a — Guaranteed scheduled work (`zen-jobs`) — REQUIRED, not deferred ✅

> **Shaped during delivery (see [`DECISIONS.md`](./DECISIONS.md) ADR-008).** An external scheduler
> calls one authenticated endpoint; the framework runs whatever is due, deciding due-ness from each
> job's persisted `last_run_at` rather than from a timer having fired. Retention is the first job;
> the mechanism is general.

**Delivered.**

- `server/zen-jobs` framework library: `ZenJob` (all an app implements), `JobState` (Panache over
  the `zen_jobs` table, Flyway `V100`), `JobSchedule` (the pure due-ness rule), `JobScheduler` (the
  master tick — sequential execution, per-run outcome recording, in-process overlap guard), and
  `JobClock` (an injected `Clock` so scheduling is tested against a driven clock, never a sleep).
- One authenticated trigger, `POST /api/v1/jobs/trigger` (`JobTriggerResource`, a framework
  resource discovered from the Jandex-indexed jar like `AuthResource`). Its credential is a
  shared-secret header (`X-Zen-Job-Token`), compared in constant time and **failing closed** when
  unconfigured; the service is served `--allow-unauthenticated`, and a Supabase session — admin
  included — is deliberately not sufficient.
- `UserRetentionJob.runCycle()` is registered as the first job by the application
  (`zen.demo.jobs.UserRetentionZenJob`). `zen-identity` gained **no** dependency on `zen-jobs`; its
  `@Scheduled` binding and `quarkus-scheduler` dependency were **removed**, and the
  `zen.identity.retention.cron` property deleted.
- **The GDPR correctness hole ADR-007 accepted is closed:** the retention cycle now finds due
  accounts, fires `AccountDeletionWarning` **synchronously**, and stamps the timestamp only when an
  observer confirms the warning's `DeliveryReceipt` — so no account is anonymised on the strength of
  a warning that failed to send, and the modules stay decoupled.
- `%dev` keeps an in-process cron that drives **the same** `JobScheduler.tick()`; `%prod` relies on
  Cloud Scheduler. `deploy:cloudrun` documents the one-time secret + scheduler-entry setup and wires
  `ZEN_JOBS_TRIGGER_TOKEN` into the deploy.
- **Migration ownership settled** (STANDARDS "Database migrations"): each framework library owns a
  reserved Flyway version band (`zen-identity` 1-99, `zen-jobs` 100-199, apps 1000+).

**Verified.** `task build:server` / `build:client` (`dart analyze` clean) / `build:apps` green.
Backend suite **50 tests, 0 failures** (was 34) plus **10 new `zen-jobs` framework unit tests** —
the first tests `task test:server` has ever run. Over a driven clock: `JobScheduleTest` (6) and
`JobSchedulerTest` (7) prove due-ness, that nine ticks missed while scaled to zero are caught up by
**exactly one** run, that a disabled job never runs however overdue, that a failure is recorded
without aborting the tick and does not spin, and that an overlapping tick is refused (by re-entering
the scheduler from inside a job — no threads, no sleeps). `JobTriggerResourceTest` (5) proves a
valid secret runs retention end to end while an absent secret, a wrong secret, and an authenticated
admin session are each rejected with a `ZenError`. `RetentionDeliveryGateTest` (3) proves an account
whose warning could not be sent is never stamped and never anonymised however many cycles run, while
one warned before the outage still is. `UserRetentionTest` adds the idempotency the contract
requires. `task test:client` green (309), `task test:admin` green, `task sync:contracts` regenerates
`jobs.proto` into stable Dart + TS with no schema garbage. `task test:e2e` is **10/10** against live
Supabase + Quarkus (was 8/8), the two new cases asserting the trigger is refused without the secret
and runs a real tick with it. Manually against live dev: an unauthenticated and a wrong-secret
`POST /jobs/trigger` return `401` + `ZenError`; the authenticated call returns the `JobTickResult`
and moves `last_run_at`/`last_status`/`run_count`; a 9-day-stale row is caught up by a single run
(`run_count` 1 → 2, not 1 → 10); a second immediate call finds nothing due.

**The GDPR obligation is now discharged in production:** retention runs on a schedule that is
provably not best-effort — a tick missed while scaled to zero is caught up, every run is visible
after the fact in `zen_jobs`, and no account is ever anonymised without a delivered warning.

### 7b — Typed, generated client i18n ✅

> **Shaped during delivery (see [`DECISIONS.md`](./DECISIONS.md) ADR-009.)** The client now makes
> the same choice the server made in ADR-002: the platform's own typed, generated message
> mechanism. `@MessageBundle` (Quarkus) ↔ `flutter gen-l10n` (Flutter). The two stacks agree.

**Delivered.**

- **`flutter gen-l10n` (intl + ARB), not `slang`** — the tie-breaker being ADR-002's own reasoning:
  the server picked the *platform's* typed mechanism, so the client picks Flutter's. No third-party
  dependency in a framework package, and a runtime locale switch re-renders through
  `MaterialApp.locale` / `Localizations` rather than a global mutable setting.
- **`zen_localization` is retired** — out of `client/pubspec.yaml`'s workspace, out of all four
  consuming pubspecs, deleted with its 12 test files (they asserted a string key reached a lookup
  table; there is no lookup table). The runtime JSON load, the dev/prod merged-bundle split, the
  cache, and the conditional-import loader are gone. The loader existed so a Dart-only *server*
  package could load translations, and jZen's server is Java, so it never had a consumer.
- **Per-package generation.** `zen_ui_identity` → `IdentityLocalizations`, `zen_ui_navigation` →
  `NavigationLocalizations`, `zen_demo_client` → `DemoLocalizations`, the navigation example →
  `ExampleLocalizations`; the app composes delegates in `MaterialApp` and supplies **no wording**.
  Screens call `IdentityLocalizations.of(context)` instead of taking a `messages:` argument, which
  deleted the threading layer in `app.dart` / `HomeShell` / `AuthFlow` / both examples. This also
  removed the ~28 identity and navigation keys `zen_demo` had **hand-duplicated** into its merged
  bundles.
- **`{en, uk}` parity is real.** `zen_ui_identity` and `zen_ui_navigation` shipped English only,
  while their Ukrainian wording sat copied inside `zen_demo`'s `uk.json`; both now ship both, from
  those strings verbatim, and so does the navigation example (which gained a language toggle).
  **`ZenLocales` in `zen_core`** mirrors the server's `zen.core.i18n.ZenLocales`, and each package
  asserts its generated `supportedLocales` against it.
- **The output is built, not committed** (STANDARDS "Code generation"): `flutter gen-l10n` is in the
  Flutter SDK every consumer already has, so there is no toolchain boundary. `task generate:l10n`
  produces it, `build:client` / `build:apps:client` / `test:client` / `test:apps:client` run it
  first, `**/l10n/generated/` is gitignored, and `sync:contracts` gained the **mirror-image
  check** — it fails if any of that output is *tracked*.
- **The ambient locale (ADR-007) is preserved and simplified.** One `Locale` provider is both
  `MaterialApp.locale` and the value `ZenClient` reads per request for `Accept-Language`, so a
  mid-session language switch re-renders the UI *and* reaches `POST /auth/register`. This
  **reinforces the compile-time-config rule**: strings are now constants that tree-shake, the runtime asset
  path is gone, and `zen_demo` lost its localization boot spinner because there is nothing to fetch.

**Verified.** `task doctor` clean. `task build:client` / `build:apps:client` analyze clean;
`task build:apps:server` and `task test:apps:server` green (**50 tests, 0 failures**, unchanged —
the server side was not touched). `task test:client` **262 tests, 0 failures** (`zen_core` 88,
`zen_identity` 45, `zen_transport` 47, `zen_ui_identity` 39, `zen_ui_navigation` 41, navigation
example 2) and `task test:apps:client` **11**. The typed behaviour is proven where the string-key
tests used to be: `identity_localizations_test.dart` pumps a real `LoginScreen` in English, pumps
the same tree at `uk`, and asserts every string re-rendered and none of the English survived;
`navigation_mobile_test.dart` does the same for the overflow label; `demo_localizations_test.dart`
proves one `Locale` change re-renders **all three packages at once** *and* that the same provider
read is what `ZenClient` sends as `Accept-Language`. `task test:admin` green.
`task sync:contracts` green including the new tracked-localizations check, and that check was
proven to reject a generated localization file added to the index. `task test:e2e` is **10/10**
against live Supabase + Quarkus with the **"the surface is localized (en vs uk)" case passing
unchanged** — the picked locale still reaches the server. `grep` for `ZenLocalizationService` returns nothing;
`zen_localization` survives only as prose recording its retirement.

Manually verified against live Supabase + Quarkus (`task run:demo`, the reference app in Chrome):
the app boots straight to the login screen with **no localization spinner**; registering seeds
`users.language = en`; picking Ukrainian from the language menu re-renders the whole surface in one
frame with no reload - `zen_demo`'s own strings (`Демо jZen`, `Пінг сервера (обидва режими
транспорту)`, the interpolated `Статус: …`), `zen_ui_navigation`'s tab labels via the app
(`Головна / Умови / Профіль`), and `zen_ui_identity`'s own screens (`Профіль`, `Ролі:`, `Вийти`,
and the whole auth flow after logout). Pinging again returns `json: Сервер працює` - the *server's*
Ukrainian wording, and `GET /demo/ping` localizes purely from `Accept-Language`, so that response is
itself proof the switched locale left the client. The ambient path closes the loop: registering a
second account **after** the mid-session switch produced `users.language = uk`, and the server
logged `Sent 'welcome' mail to … in locale 'uk'`. A `flutter build web --release` succeeds with
**zero l10n assets in the bundle**, the used Ukrainian strings of all three packages compiled into
`main.dart.js`, and unused accessors tree-shaken out - something the JSON-bundle approach could
never do.

**Client and server i18n are now consistent: typed and generated on both stacks**, which is the
point of the step. Adding a locale is symmetric and needs no code edit on either side.

### 7c — Candidate capabilities: settled, and nothing added ✅

> **Decided in full (see [`DECISIONS.md`](./DECISIONS.md) ADR-010).** The open-ended "build it when
> a consumer needs it" list is closed. Every candidate capability has a disposition, the verdict on
> all six remaining ones is **no**, and each surviving capability has a trigger written as a testable
> condition. **Nothing was added.**

**Delivered.**

- **The list is complete and closed**, which the old one was not: it was open-ended, and an
  open-ended list is indistinguishable from an undecided one. ADR-010 holds the full census and the
  argument for each verdict; it is the permanent record.
- **The verdicts**, each argued on ADR-001's framework/application axis, and each replaced by a
  trigger rather than a deferral:

  | Capability | Verdict | Reason, and what jZen does instead |
  |---|---|---|
  | telemetry library | **no** | Job runs already live in the `zen_jobs` row (ADR-008); *which* events matter is application content, and per-user event rows would land on the `users.analytics_consent` GDPR obligation. A framework-owned table no framework code writes to is not a mechanism. |
  | work-routing library | **no** | Routing light/medium/heavy work is a single-threaded-runtime concern. A JAX-RS resource already runs on a worker pool, `@Blocking`/`@NonBlocking`/`ManagedExecutor` are platform primitives, and `zen-jobs` owns deferred work. |
  | cache library | **no** | In-process state is *valid by construction* at `--max-instances=1` (STANDARDS "Deployment model"), so the distributed half solves a problem jZen does not have; `quarkus-cache` is the in-memory half, one annotation. |
  | object-storage library | **no** | jZen runs Supabase Storage, reachable with a short `@RegisterRestClient`. A library fronting one implementation would be a passthrough - MANIFESTO: real dependencies are first-class, "not smuggled behind a portability layer that no second implementation will ever justify". |
  | payments library | **no** | A provider, its currencies, its tax treatment, and its webhook contract are product policy, not mechanism. The framework share would be `quarkus-rest-client` plus a table. |
  | AI/model library | **no** | Vendor-specific model clients are the fastest-ageing code there is, and maintained Quarkus extensions already exist. jZen does not write its own. |

- **Every trigger is a testable condition, not a sentiment**: an application defines its own event table in the application migration band and
  promotes it to `server/zen-telemetry` only when a **second** application needs it; an application
  declares its own Supabase Storage / S3 client and promotes to `server/zen-storage` on the same
  second-consumer bar; an application that sells something implements checkout in its own server; an
  application that needs a model uses a maintained Quarkus extension; and raising `--max-instances`
  above 1 is the already-documented trigger to externalize state, answered by
  `quarkus-redis-client`.
- **Micrometer stays in the application.** `quarkus-micrometer-registry-prometheus` remains in
  `apps/zen_demo/zen_demo_server/pom.xml`: a registry binding is a deployment choice, and promoting
  it would force every app to expose Prometheus metrics whether or not its host scrapes them.
- **Two stale promises corrected.** BLUEPRINT "Persistence" and the `User` javadoc both said
  `is_premium` behaviour was "wired in ... payments in step 7". Payments is not coming as framework
  work, so both are reworded; the **column stays and is already load-bearing** (the retention
  premium exemption reads it, `AdminUserResource` exposes it).
- **No structural change:** no framework module created, **no Flyway band claimed** (200-299 stays
  free), no Taskfile target, no new dependency anywhere. Lockstep stays `0.1.0`.

**Verified.** No behaviour changed - the diff is three architecture documents plus one javadoc in
`User.java` - so the verification is that the baseline holds, measured first and re-run after, not
assumed. `task build` exits 0 and `task test` exits 0
at their existing numbers: backend **50 tests, 0 failures**; `task test:client` **262** (`zen_core`
88, `zen_identity` 45, `zen_transport` 47, `zen_ui_identity` 39, `zen_ui_navigation` 41, navigation
example 2); `task test:apps:client` **11**; `task test:e2e` **10/10** against live Supabase +
Quarkus. `task sync:contracts` reports contracts in sync, including the ADR-009 check that generated
localizations stay untracked. Every figure matches what 7b recorded, which is the point.

**Step 8 is unblocked**: no open item points at anything Step 8 would have to delete.

### Framework improvements — remaining, deferred but committed to a plan

None outstanding. Typed, generated client i18n was the item recorded here; it shipped as 7b above.

## Step 8 — Standalone: jZen on its own terms ✅

> **Shaped during delivery (see [`DECISIONS.md`](./DECISIONS.md) ADR-011).** The strip runs over
> everything a reader or a future contributor sees, and stops at the decision log, which is sealed
> as a historical archive rather than rewritten. The gate is scoped to match, and the wording below
> states what is actually enforced.

**Delivered.**

- **Every source-level citation is gone**, across `client/`, `server/`, `apps/`, `proto/`, and
  `supabase/`, and each one's *reason* was rewritten rather than deleted with it: why
  `quarkus-rest-jackson` must be absent, why each auth token gets its own cookie, why the Flyway
  bands exist, why the compliance columns are on `users`, why the codec selector is a conditional
  import. A comment whose only content was provenance was removed; a comment that explained a
  constraint now explains it on jZen's own terms.
- **The three generated `.pb.dart` files were fixed at the source, not by hand.** `protoc` copies
  `.proto` comments verbatim into generated doc comments, so seven references sat inside tracked
  generated files that STANDARDS forbids editing. The fix was to edit `common.proto`, `demo.proto`,
  and `identity.proto` and regenerate. Editing the `.pb.dart` would have been a defect, and
  `sync:contracts` is the gate that catches exactly that.
- **The four docs stand alone.** `MANIFESTO` states jZen's philosophy directly and its
  "Provenance, and its expiry" note is gone, having expired as designed; `BLUEPRINT` describes the
  architecture as built; `ROADMAP` records what each step delivered rather than what it came from.
- **The Technical Assessments section is deleted, and no rule went with it.** It only ever
  documented migration gaps, but three of its seven carried live rules that `STANDARDS` did not yet
  state. Those were folded in as plain rules: the `Response` + `@Schema(ref=…)` + static
  `META-INF/openapi.yaml` merge (now STANDARDS "OpenAPI and the REST surface"); per-endpoint typed
  messages with no generic payload and no envelope (now under "Source of truth"); and the client's
  no-swallowed-failure contract (now "Failures surface; nothing is swallowed"). The rest were
  already carried, already closed, or were migration gaps with nothing to preserve. **The ~45 files
  that referenced a `TA-N` by number were repointed to the rule that now carries it**, so deleting
  the section left no dangling pointer.
- **STANDARDS "Fidelity to the source" is retired**, which is what this step was always for. Its
  one surviving rule generalizes without naming anything external: all work happens inside this
  repository.
- **`CLAUDE.md` was brought into scope**, though it is not one of the four docs. It is the first
  file every future contributor and agent reads, and its "cite the source" rule would have
  instructed them to reintroduce the citations this step removes.
- **`DECISIONS.md` is sealed, not rewritten** (ADR-011). An accepted ADR is not edited after the
  fact; that is the property the log exists to have. The names it carries are historical
  justification, and ADR-011 is the index that keeps its `TA-1`..`TA-7` references resolvable now
  that the section is gone.
- **Vocabulary residue cleared.** The spent build-define and transport-header rename notes are
  deleted: a rename note that has outlived its rename is exactly what this step removes. The
  `zen_localization` retirement prose is gone from `client/pubspec.yaml` too, ADR-009 being its
  permanent record. And the navigation example no longer greets the user, in two languages, with a
  product name that is not jZen's.
- **No behaviour changed.** The diff is comments, prose, and regenerated generated-comments.

**Verification.** A case-insensitive search of every tracked file for the names of the two systems
jZen was built from, and for the superseded transport-header prefix, returns nothing outside
`docs/architecture/DECISIONS.md`. That one exclusion is the subject of ADR-011: the decision log is
a sealed archive whose entries are never retroactively edited, because in several of them the
system named *is* the justification being recorded. Searching tracked files rather than the working
tree is deliberate, so an untracked local file cannot report a failure that no clone would see.

This was run as a check, not installed as a standing gate. Step 8 is terminal: nothing in the
project now produces such references, so a permanent target would guard a failure mode that has
stopped occurring, and it would have to exempt its own definition to avoid matching the pattern it
searches for. The rule it enforced lives in STANDARDS and `CLAUDE.md` instead, where it belongs -
anything a reader needs is explained on jZen's own terms.

## Step 9 — Documentation: READMEs ☐ (final step)

Written last, so they describe jZen as built and in its own voice. Step 8 made this writable:
there is now one vocabulary to write in. The `docs/architecture/` set stays the deep reference;
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

## Explicitly out of scope

Not part of jZen, and not becoming part of it without a decision that supersedes this line:

- **Firebase and Firestore.** PostgreSQL is the database; Supabase owns authentication.
- **A Flutter admin panel.** Administration is `react-admin` (ADR-005).
- **Server-rendered HTML.** jZen serves a REST API; Qute is a mail-templating engine only.
- **The six candidate framework capabilities settled in 7c** - telemetry, work routing, caching,
  object storage, payments, and model clients. Each has a trigger in
  [`DECISIONS.md`](./DECISIONS.md) ADR-010 stating the condition under which it would be
  reconsidered; none of those conditions is met today, and "we might want it" is not one of them.
