# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What jZen is

jZen is a **framework/platform**, not a single deployable app. `server/` (Java) and `client/`
(Dart/Flutter) are reusable **framework libraries**; `apps/` holds full-stack **applications**
that assemble them (`apps/<app>/{<app>_client, <app>_server, <app>_admin}`). Today the only app
is the reference app `zen_demo`, which doubles as a showcase and the living end-to-end test stand.

See `docs/architecture/` — **read these before non-trivial work**; they are the source of truth:
`MANIFESTO.md` (philosophy), `BLUEPRINT.md` (the architecture as built), `STANDARDS.md` (the rules),
`ROADMAP.md` (step-by-step status), `DECISIONS.md` (ADRs — newest decisions supersede earlier docs,
so ADRs win on conflict). `DECISIONS.md` is an append-only archive: add an entry, never edit an
accepted one.

## Orchestration: `task` is the only entry point

`Taskfile.yml` (go-task, `brew install go-task/tap/go-task`) is the single orchestrator. It
**triggers native tools, never replaces them** — `mvnw` owns Java, `dart pub` owns Dart, `pnpm`
owns TypeScript. A task that reimplements a package manager is a bug. There is no Melos/Gradle
orchestrator and no root `pom.xml` or root `pubspec.yaml` — the repo root is language-neutral.

Common commands (`task --list` for all):

| Command | What it does |
|---|---|
| `task doctor` | Verify toolchain (JDK 25, dart, flutter, pnpm, supabase, docker, gcloud; protoc/protoc-gen-dart only needed for Dart proto codegen) |
| `task deps` | Resolve deps for every sub-project |
| `task build` | `sync:contracts` then build everything |
| `task test` | Every suite, **including `test:e2e` (the live release gate)** |
| `task sync:contracts` | Regenerate all cross-language artifacts and **fail if any committed generated file drifted** — the contract-drift gate; wire into CI |
| `task run:server` | Quarkus dev mode (live reload) on `:8080` |
| `task run:demo` | Boot Supabase + backend + zen_demo for a manual walkthrough |
| `task run:admin` | Admin panel dev server on `:5173` (proxies `/api`) |
| `task deploy:cloudrun` | Native build → Artifact Registry → Cloud Run |

### Running tests (and a single test)

- **Backend** (`@QuarkusTest`, uses Dev Services Postgres — Docker must be running): `task test:apps:server`.
  It installs the framework libs first, then runs the app server's tests. A `@QuarkusTest` needs an
  assembled app, so backend tests live in the app module, not the libs. Single test:
  `cd server && ./mvnw -B -q install -DskipTests && ./mvnw -B -f ../apps/zen_demo/zen_demo_server/pom.xml test -Dtest=AdminUserResourceTest#methodName`
- **Dart/Flutter libs**: `task test:client` (iterates workspace members; Flutter packages get
  `flutter test --dart-define=ZEN_ENV=dev --dart-define=ZEN_PLATFORM=<host>`, pure-Dart get `dart test`).
  Single package: `cd client/<pkg> && dart test test/<file>_test.dart`.
- **Transport codec matrix**: `task test:client:matrix` recompiles per `ZEN_ENV`/platform.
- **Admin**: `task test:admin` (`tsc -b` typecheck of the panel + the `@jzen/admin-core` scaffold).
- **E2E**: `task test:e2e` — boots real Supabase + Quarkus, runs zen_demo's pure-Dart integration
  suite (no mocks) on `ZEN_APP_PORT` (default 8085), propagates exit code.

## Contract-first: the source of truth flows one direction

```
proto/zen/v1/*.proto  ──protoc──▶ Java DTOs (zen-proto) + Dart messages + OpenAPI model schemas
Quarkus resources + SmallRye ──▶ REST paths/verbs/status ──▶ merged openapi.json ──▶ TS admin types
```

- `.proto` under `proto/zen/v1/` is canonical for **models**; SmallRye-annotated Quarkus resources
  are canonical for the **REST surface** (paths, verbs, status codes). Everything else — Java DTOs,
  Dart messages, `openapi.json`, TS types — is **derived**.
- **Generated output is committed across a toolchain boundary, regenerated within one.** Tracked:
  the Dart messages and the admin `schema.generated.ts` (a Flutter/frontend dev must not need
  `protoc` or a JDK to compile). Not tracked: the Java DTOs and `openapi.json`, which live under
  `target/` because Maven resolves `protoc` itself. Do not "fix" that by checking `target/` in.
  See STANDARDS "Code generation".
- **A tracked generated file is never hand-edited.** Fix the `.proto` or annotation and
  regenerate; `task sync:contracts` will fail the build if a generated file drifts. Editing a
  derived artifact is a defect.

## The dual-mode transport seam (the framework's core mechanism)

A developer defines a domain model; the framework negotiates the wire format. The `X-Zen-Transport`
request header (values `json`/`protobuf`) selects the codec; negotiation order is header →
content-type sniff → default JSON. `ZenTransportFilter` (a `@PreMatching` filter in `zen-transport`)
rewrites `Accept`/`Content-Type`, then JAX-RS dispatches to `Protobuf*` or `ProtoJson*`
`MessageBodyWriter/Reader` registered for `com.google.protobuf.Message`. Resources return proto
messages; **MapStruct** maps Panache entity ⇄ proto. The response echoes `X-Zen-Transport`.

There is also a **first-class WebSocket** surface (`/api/v1/demo/ws`, `quarkus-websockets-next`) —
single-format, always binary Protobuf frames (dual negotiation is an HTTP-only concern).

Two non-negotiable backend rules this seam depends on (see STANDARDS "Backend multi-module rules"):

- **Every library module contributing CDI beans or JAX-RS providers must run `jandex-maven-plugin`.**
  Quarkus discovers `@Provider`/beans from a dependency jar only if it carries `META-INF/jandex.idx`.
  Omit it and the module's filters/writers/mappers/augmentors **silently do nothing** — no error.
  `zen-transport` is the reference.
- **No server-side `quarkus-rest-jackson`.** jZen is proto-first; its JSON is canonical proto3 JSON
  from `JsonFormat` via `ProtoJsonMessageBodyWriter`. Jackson's writer greedily claims
  `application/json` through a build-time path that ignores writer priority and serializes proto
  builder internals (500s), so it must be *absent*, not out-prioritized. (Client-side
  `quarkus-rest-client-jackson` in `zen-identity` is fine — outbound Supabase calls aren't proto.)

Because SmallRye can't cleanly introspect protobuf classes (a bare-proto return produces 130+
garbage schemas, and 500s at runtime), resources return `jakarta.ws.rs.core.Response` annotated with
`@APIResponse(... @Schema(ref = "..."))`, and the clean component schema is supplied by the app's
static `META-INF/openapi.yaml` (paths scanned from annotations merge over it).

## Backend structure (Maven multi-module)

`server/pom.xml` (`zen-parent`, packaging `pom`) is **both** the parent (BOM, Java 25, plugin/dep
management) **and** the aggregator that builds+`install`s the framework libraries. App servers
(e.g. `apps/zen_demo/zen_demo_server`, the **only** `quarkus`-packaged module) inherit `zen-parent`
across directories via `<relativePath>` and resolve libs from the local Maven repo — never by
relative source paths. Baseline: **Quarkus 3.32.2 on Java 25**.

Library modules: `zen-proto` (generated DTOs, leaf, only `protobuf-java`), `zen-core`
(`ZenResult`/`ZenError`/`ZenStatus`/`AcceptLanguage`, no Quarkus deps), `zen-transport` (the seam),
`zen-identity` (Supabase auth, `User` entity, `RoleAugmentor`, **and** the reusable `AuthResource` +
`AdminUserResource` — auth is framework-side so every app inherits it), `zen-email` (planned, step 6).

**Java namespace is bare `zen`** (ADR-006), not `dev.zen`: `groupId zen`, packages `zen.core` /
`zen.transport` / `zen.demo`, proto emits `java_package "zen.proto.v1"`. Older ADRs saying `dev.zen`
now read as `zen`.

## Client structure (Dart) and the compile-time config rule

Two pub workspaces resolve independently: `client/` (framework libs: `zen_core`, `zen_transport`,
`zen_identity`, `zen_ui_*`) and `apps/` (app clients, path-depending into `client/`). Both share one
product version (lockstep).

**Client i18n is typed and generated** (ADR-009), mirroring the server's Qute `@MessageBundle`.
Every package that renders text owns its own `lib/src/l10n/*.arb` + `l10n.yaml` and generates typed
accessors with `flutter gen-l10n` (`task generate:l10n`); an app composes the delegates in
`MaterialApp.localizationsDelegates` and supplies no wording. Unlike the `.pb.dart` messages this
output is **built, not committed** (`**/l10n/generated/` is gitignored) because gen-l10n ships
in the Flutter SDK; `sync:contracts` fails if any of it is ever tracked. The supported set is
`ZenLocales` in `zen_core` (`{en, uk}`, fallback `en`), mirroring server `zen.core.i18n.ZenLocales`.
The chosen `Locale` is also what `ZenClient` sends as `Accept-Language` (ADR-007).

**The Dart/Flutter client keeps compile-time config** (`String.fromEnvironment`) and
`if (dart.library.io)` / `if (dart.library.html)` conditional imports — this is load-bearing, not a
limitation. It lets the toolchain tree-shake native-only code (the Protobuf binary path) out of the
JS/Wasm web bundle and web-only code out of the AOT-native binary. **Runtime config on the client is
forbidden**. Build defines are `ZEN_ENV` / `ZEN_PLATFORM`. The
**server** is the deliberate opposite — runtime MicroProfile config, because one binary serves all
clients and has no bundle to shrink.

## Admin (react-admin, ADR-005)

Split like everything else: `admin/` is the reusable `@jzen/admin-core` scaffold (data provider,
auth provider, login page — schema-generic); each app assembles it into its own panel under
`apps/<app>/<app>_admin` (today `zen_demo_admin`), which registers domain resources typed off its
generated `openapi-typescript` schema. The panel imports the scaffold **from source** via a
TypeScript `paths` alias + Vite `resolve.alias` (with React dedupe), **not** a pnpm dep edge — the
TS analog of the Dart `path:` dep and Maven `<relativePath>`, keeping the root language-neutral.
Admin always speaks `X-Zen-Transport: json`; list endpoints return a bare JSON array +
`Content-Range` (`ra-data-simple-rest` convention).

## Persistence & auth

PostgreSQL via Hibernate Panache (active-record; no repository classes). **Flyway is the single
migration authority** (`zen-identity/db/migration/`), so `supabase/migrations/` stays empty — never
two migration systems on one DB. Local DB is the Supabase stack on port 54322. Supabase owns
`auth.users`; the jZen `users` table is the app profile keyed by the JWT `sub`, with **no FK** to
`auth.users` (the test DB has no `auth` schema). The RLS migration is guarded on
`to_regprocedure('auth.uid()')` so it's a no-op on plain Postgres and tests still migrate.

Auth: Supabase JWT verified against JWKS (ES256), read from a normal httpOnly cookie
`zen_access_token` (`mp.jwt.token.cookie`, `quarkus.http.auth.proactive=true`). Role is loaded from
the `users` table by a `SecurityIdentityAugmentor`, **not** from the JWT. Each token gets its own
normally-named cookie and there is no session filter — which works because jZen serves Cloud Run
directly, with nothing in front that strips or renames cookies. Do not put such an edge in front
without reading STANDARDS "Deployment model" first; it would break the whole auth path.

## Deployment & operational invariants

Prod ships a **native image** to Cloud Run, **single instance by design** (`--max-instances=1`,
`--min-instances=0`, `--concurrency=200`) — a cost floor, not a scaling limit. Because at most one
instance runs, **in-process state (rate limiting, in-memory caches, login counters) is valid by
construction**; the trigger to externalize state (Postgres/Redis) is raising `--max-instances` above
1. Container builds pin `linux/amd64`.

## Working discipline

- **All work happens inside this repository.** Nothing reaches outside the repo root to modify a
  file; anything jZen depends on arrives as a declared dependency.
- **Nothing swallows a failure.** No task hides a red suite behind `|| true` or a discarded exit
  code, and `ZenClient` surfaces a `ZenError` on a decode failure rather than a null payload. If you
  are about to make a failure quieter, you are about to introduce a bug. See STANDARDS "Failures
  surface; nothing is swallowed".
- **Explain things on jZen's own terms.** A comment earns its place by saying *why* a constraint
  exists, in language a reader with no history here can follow. jZen is a standalone product: it
  does not name other codebases, and nothing here is described as ported, derived, or inherited
  from one. The sole exception is `docs/architecture/DECISIONS.md`, a sealed archive (ADR-011).

## Project-specific working agreement

**Never run `git commit` or `git push` without explicit approval from the user.**
