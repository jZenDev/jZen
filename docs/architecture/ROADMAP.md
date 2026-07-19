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

## Step 4 — the reference app: showcase + living test stand ☐

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

## Step 5 — Admin panel ☐

- Flesh out `admin`: real resources driven by generated `openapi-typescript`
  types; wire `ra-data-simple-rest` pagination to the backend's `Content-Range`
  convention; add Supabase session auth.
- The Flutter `dartzen_ui_admin` is confirmed dropped (not migrated).

## Step 6 — Email ☐

- `zen-email` `EmailService` (new) over `quarkus-mailer`, wiring Brevo via `SMTP_HOST`.
- **Localized from the start (TA / BLUEPRINT "Email"):** per-locale Qute templates
  (`@Localized` variants, e.g. `mail/welcome_en.html` / `welcome_uk.html`) with subjects
  from a Qute `@MessageBundle`; `EmailService` resolves the recipient's locale from
  `users.language`. `SUPPORTED = {en, uk}` initially. BugEater's English-only hardcoded
  mail strings are not carried forward.

## Step 7 — Deferred packages ☐

Port only when a consumer needs them, each in isolation:

- `dartzen_jobs` → Quarkus `@Scheduled` (reference: `../BugEater/.../user/DataRetentionJob.java`).
- `dartzen_telemetry` → a Panache-backed store (its `TelemetryStore` is the one clean
  store abstraction in DartZen — `../DartZen/packages/dartzen_telemetry/lib/src/store/telemetry_store.dart:4`).
- `dartzen_executor`, `dartzen_payments`, `dartzen_ai`, `dartzen_cache`,
  `dartzen_storage` (→ Supabase Storage / S3) — no committed target until demanded.

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
