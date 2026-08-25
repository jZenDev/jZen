# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

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
request header (values `json`/`protobuf`) selects the **response** codec; negotiation order is
header → content-type sniff → default JSON. `ZenTransportFilter` (a `@PreMatching` filter in
`zen-transport`) rewrites only `Accept` to the negotiated media type, so JAX-RS dispatches to the
matching `Protobuf*` or `ProtoJson*` `MessageBodyWriter` registered for `com.google.protobuf.Message`.
The **request** body's parser is selected independently, by the client's own `Content-Type` via
`@Consumes` — `X-Zen-Transport` never steers which reader parses an inbound body. Resources return
proto messages; **MapStruct** maps Panache entity ⇄ proto. The response echoes `X-Zen-Transport`.

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
relative source paths. Baseline: **Quarkus 3.38.0 on Java 25**.

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

**The client talks to one server, and it is ours.** No client package may call Supabase (or any
third party) directly — not with `supabase_flutter`, not with a hand-rolled call. Supabase is
reached only by the server, via `SupabaseAuthClient`; `SUPABASE_URL`/`SUPABASE_KEY` are
server-side config and are never shipped to a client. This fails *silently* if broken — the app
would authenticate and every suite would still pass, while the backend stopped being the only
place a session is minted and the only place roles are resolved. `task verify:boundaries` (first
in `task test`) enforces it; STANDARDS "The client talks to one server" explains it. Note
`SupabaseIdentityRepository` is named for the provider *behind* the backend and calls
`/api/v1/auth/*` — do not "fix" it by adding the SDK.

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

**Never commit onto `main`** — branch first, even with approval in hand, and especially right
after a PR merge, when the working copy has just landed back on `main`.

Both rules, and the 50-character subject limit, are enforced by `.Codex/hooks/git_guard.py`
rather than by memory. A fresh clone has no git-side guard until
`sh .Codex/hooks/install-git-hooks.sh` runs, because `.git/hooks` is not tracked.
`.Codex/hooks/skill_guard.py` delivers a skill's rules the first time a file it governs is
edited in a session; the path-to-skill mapping is `.Codex/hooks/skill-map.json`.

Two more guards close the gap between "a rule exists" and "a rule fires":
`.Codex/hooks/verify_guard.py` runs on `Stop` and refuses to end a turn that changed source
without running a suite (config: `verify-rules.json`; docs, `.Codex/` and generated output are
exempt, and it never fires twice in a row). `skill_guard.py` also matches **commands**, not just
paths — so `long-job` arrives on the first slow build and `deploy` on the first `gcloud`, which
are skills no file edit could ever have summoned.

**Branch names are `<type>/<slug>`** — `feature/`, `fix/`, `docs/`, `security/`, `orchestration/`.

**Deploy commands are prepared, not run.** Produce the exact command and say what it will change;
the user runs it and brings back the output. See the `deploy` skill, which also carries the
describe-or-create rule for one-time regional resources.

**When a command fails twice with the same error, escalate instead of retrying** — hand over the
exact command for the user to run with the `!` prefix. Interactive authentication is never a
retry problem.

### What is in `.Codex/`

| | Purpose |
|---|---|
| `skills/add-adr` | record a decision in `DECISIONS.md` (append-only) |
| `skills/add-endpoint` | add a REST endpoint contract-first (OpenAPI merge, Jandex, no-Jackson) |
| `skills/sync-contracts` | the proto → Java/Dart/TS regeneration loop and its drift gate |
| `skills/run-demo` | boot the stack locally |
| `skills/deploy` | Cloud Run deploy; who runs it, and the one-time-resource rule |
| `skills/long-job` | how to wait on a slow command, with this repo's measured durations |
| `agents/visual-verify` | drive a change in a real browser; returns pass/fail + screenshots |
| `agents/regression-guard` | review a diff for what it broke and what it duplicated |
| `hooks/` | the guards above, their config, and their tests |

Run the hook tests with `python3 .Codex/hooks/test_git_guard.py`,
`python3 .Codex/hooks/test_skill_guard.py` and `python3 .Codex/hooks/test_verify_guard.py`.

`.Codex/tools/session-metrics.py` measures whether any of this is working. It parses the
Codex transcripts for all three repos and reports the rates the guards exist to move —
over-long commit subjects, commits on a protected branch, foreground sleeps, skill loads, and
how often each guard actually blocked something. `--compare` diffs against
`session-metrics-baseline.json`, stamped from the window before the guards existed. Re-run it
every few weeks; it is read-only and writes nothing outside `.Codex/tools/`.

Permissions are prefix rules in the tracked `.Codex/settings.json` (read-only git, inspection
tools, this repo's own build and test entry points). `settings.local.json` is for genuine
one-offs; it is gitignored and never the place for a rule everyone needs. `task deploy:*` is
deliberately **not** pre-allowed — and an entry there that pre-approves a real deploy
contradicts the rule above, so prune those on sight. Entries accrete: periodically drop the ones
already covered by a wildcard in the same file, and the ones naming ports, PIDs or scratch paths
that no longer exist.


## The working tree is shared

The user edits files in this repository while a session runs. A session that
assumes it is alone commits their work by accident.

**Stage by explicit path, and check the index before committing.** `git add -A`
and `git add .` sweep up whatever is there. Even explicit paths are not enough
on their own: run `git diff --cached --name-only` immediately before `git
commit` and confirm every entry is a file you wrote. A file can already be
staged when you arrive.

**Never switch branches while files you did not touch are modified.** A switch
either aborts or carries someone else's work onto another branch, and a stash
taken to get around it pops straight back onto the branch you were leaving.
Use a worktree, which needs no stash and leaves this tree untouched:

    git worktree add -b <branch> <dir> origin/main
    # work, commit, push from <dir>
    git worktree remove <dir>

This applies to `git checkout -b <branch> <start-point>` too: git aborts that
whenever a modified file differs between HEAD and the start point.

**Leave what is not yours exactly as you found it.** If you have to undo your
own commit, verify afterwards that their files are still modified and still
theirs.

`.Codex/hooks/worktree_guard.py` enforces all of this: it recovers the files
this session wrote from the transcript, refuses a commit whose index holds
anything else, and refuses a branch switch under foreign changes. Prefix a
command with `ALLOW_FOREIGN=1` when the foreign files genuinely belong in the
commit.
