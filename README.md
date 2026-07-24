# jZen

jZen is a **framework/platform for building full-stack products**, not a single deployable
app. `server/` (Java/Quarkus) and `client/` (Dart/Flutter) are reusable **framework libraries**;
`apps/<app>/{<app>_client, <app>_server, <app>_admin}` are the **applications** that assemble
them. Today the only app is `zen_demo`, the reference app, which doubles as the product
showcase and the living end-to-end test stand.

The stack is Quarkus, PostgreSQL, and Supabase on the server; Flutter on the client;
react-admin for administration; and one contract, declared in protobuf, binding all three. The
one mechanism the rest is arranged around is a **dual-mode transport**: a developer defines a
domain model and one request header, `X-Zen-Transport`, negotiates whether it travels the wire
as canonical proto3 JSON or Protobuf binary — over the same typed endpoints, with no branch in
the resource or the caller.

The philosophy is stated in [`docs/architecture/MANIFESTO.md`](docs/architecture/MANIFESTO.md);
the architecture as built is in
[`docs/architecture/BLUEPRINT.md`](docs/architecture/BLUEPRINT.md); the rules that keep it
honest are in [`docs/architecture/STANDARDS.md`](docs/architecture/STANDARDS.md). **Read those
before non-trivial work — they are the source of truth, and this README only points at them.**

## Status — what works, and what does not yet

**The framework is complete and gated; it is not yet production-ready, and the difference is
deliberate.** Everything described below runs today: the transport seam, auth, jobs, email, the
admin surface, the reference app, and the full test and contract-drift gates. What is *not* done
is the last mile to shipping a product:

- **The packages are unpublished.** Everything is `0.1.0` and consumed by **local path** — there
  is no pub.dev, Maven, or npm release yet, so an app outside this repository cannot depend on
  jZen by version.
- **Only the backend has a deploy path**, and it has never actually been run against real GCP.
  The web app and admin panel have no deploy task yet.

The full list, with what "done" means for each, is the appendix in
[`ROADMAP.md`](docs/architecture/ROADMAP.md). Nothing there is a hidden defect — they are stated
boundaries, and this note exists so you meet them here rather than discover them later.

## See it run

The fastest way to watch the whole product work end to end is the reference app:

```bash
task run:demo
```

This boots the local Supabase stack, starts the Quarkus backend, and runs `zen_demo` in Chrome
pointed at it. `zen_demo` is both the showcase and the living test stand: the same flows a
human walks through here are asserted headlessly by `task test:e2e` (the release gate) against
the same real stack, with no mocks. See
[`apps/zen_demo/README.md`](apps/zen_demo/README.md) for what it exercises.

## Repository map

The single most important structural fact: `server/` and `client/` are the **framework
libraries**; `apps/` holds the **applications** that assemble them. The repository root stays
language-neutral — only `Taskfile.yml` lives there; there is no root `pom.xml` or root
`pubspec.yaml`.

| Directory | What it is |
|---|---|
| [`server/`](server/README.md) | Java/Quarkus framework libraries (multi-module Maven): the transport seam, identity, email, jobs. |
| [`client/`](client/README.md) | Dart/Flutter framework libraries (pub workspace): core, transport, identity, and the `zen_ui_*` UI packages. |
| [`apps/`](apps/zen_demo/README.md) | The applications built on the framework. Today: the `zen_demo` reference app (client + server + admin panel). |
| [`admin/`](admin/README.md) | `@jzen/admin-core`, the reusable react-admin scaffold each app assembles into its own panel. |
| [`proto/`](proto/README.md) | The canonical protobuf contract (`zen.v1`) — the source of truth every language generates from. |
| [`supabase/`](supabase/README.md) | Local Supabase stack config (auth, database, ports). |
| [`scripts/`](scripts/README.md) | One-shot dev-loop helpers the `run:*` tasks shell out to. |
| [`docs/architecture/`](docs/architecture/) | MANIFESTO, BLUEPRINT, STANDARDS, ROADMAP, and the DECISIONS log. The deep reference. |

## Orchestration: `task` is the only entry point

[`Taskfile.yml`](Taskfile.yml) ([go-task](https://taskfile.dev), `brew install
go-task/tap/go-task`) is the single orchestrator. It **triggers native tools, never replaces
them** — `mvnw` owns Java, `dart pub` owns Dart, `pnpm` owns TypeScript. Run `task --list` for
the full, always-current set; the commands below are the ones you need first.

It spans three audiences, not just local dev: the `run:*` tasks are the **local** loop; `build`,
`test`, `sync:contracts`, and `verify:docs` are the **CI gates** (wire them into your pipeline);
and `deploy:cloudrun` is **release**. The `desc` in `task --list` tells you which is which.

## Quick start — running it

Prerequisites: JDK 25, Dart, Flutter, pnpm, the Supabase CLI, Docker (running), and gcloud.
Verify them in one shot:

```bash
task doctor
```

Then bring up the backend against a local Supabase stack:

```bash
task run:all
```

`run:all` starts **Supabase and the backend only**; the admin panel is a separate surface you
start on its own. Where each surface comes up:

| Surface | Command | URL |
|---|---|---|
| Backend API (Quarkus dev mode) | `task run:all` / `task run:server` | `http://localhost:8080/api/v1` |
| Reference app (`zen_demo`, in Chrome) | `task run:demo` | backend on `:8085` (see note) |
| Admin panel (react-admin dev server) | `task run:admin` | `http://localhost:5173` (proxies `/api`) |
| Supabase API / DB / Studio | `task run:supabase` | `54321` / `54322` / `54323` |

Note: `task run:demo` and `task test:e2e` run the backend on `ZEN_APP_PORT` (default `8085`),
deliberately, so a leftover stack shadowing `:8080` cannot interfere. `task run:server` and
`task run:all` use the Quarkus dev default `:8080`.

## Quick start — developing on it

```bash
task deps     # resolve deps for every sub-project (native tools do the work)
task build    # sync:contracts, then build server + client + apps + admin
task test     # every suite, including test:e2e (the live release gate)
```

The workflow that makes jZen coherent is **contract-first**, and it flows one direction:

```
proto/zen/v1/*.proto  ──▶ Java DTOs + Dart messages + OpenAPI schemas
Quarkus resources     ──▶ REST paths/verbs/status ──▶ openapi.json ──▶ admin TypeScript types
```

Edit a model in [`proto/`](proto/README.md) or a resource in `server/`, then:

```bash
task sync:contracts
```

This regenerates every cross-language artifact and **fails if any committed generated file
drifted** — the drift gate. Wire it into CI.

The golden rules a new contributor trips over first:

- **Generated files are committed across a toolchain boundary and never hand-edited.** Fix the
  `.proto` or the annotation and regenerate; editing a derived artifact is a defect
  `sync:contracts` will catch. See STANDARDS "Code generation".
- **Client config is compile-time.** The Dart/Flutter client uses `String.fromEnvironment`
  (`ZEN_ENV`, `ZEN_PLATFORM`) and conditional imports so the toolchain can tree-shake native
  code out of the web bundle and web code out of the native binary. Runtime config on the
  client is forbidden. The **server** is the deliberate opposite (runtime MicroProfile config).
- **Nothing swallows a failure.** No task hides a red suite; the client surfaces a `ZenError`
  rather than a null payload on a decode failure. See STANDARDS "Failures surface".

Adding an **endpoint** (a proto message, a resource, the dual-mode wiring, the OpenAPI merge)
and adding a **package** both follow the framework/apps split — see
[`server/README.md`](server/README.md) and [`client/README.md`](client/README.md). `task
test:e2e` runs `zen_demo` against the real stack as the integration gate, so a change is not
"done" until that is green.

`task verify:docs` checks this documentation itself: every `task` name mentioned in any README
resolves in `task --list`, and every module's `LICENSE` is byte-identical to the root one.

## Building your own app on jZen

jZen is a framework, so the deliverable is *your* application, and you build it by **depending on
the libraries as versioned packages** — never by copying their code. That distinction is the
whole point: an app that depends on `zen_transport 0.1.0` moves to `0.2.0` by bumping a version,
the same way you would with any `dart pub add` / Maven / `pnpm add` dependency. A framework you
copy-pasted could not be upgraded at all. The reference app `zen_demo` is the worked example of
the wiring; read it end to end as the tutorial for *how* the pieces fit — not as a template to
duplicate.

A new app is a folder `apps/<app>/` with up to three surfaces, each **consuming** a tier of the
framework:

- **`<app>_server`** — a Quarkus module that inherits `zen-parent` and resolves the framework
  libraries as Maven dependencies. It owns its own domain resources, `proto/` messages,
  `META-INF/openapi.yaml`, and any app-specific Flyway migrations (band 1000+).
- **`<app>_client`** — a Flutter package that depends on `zen_core` / `zen_transport` /
  `zen_identity` / `zen_ui_*`. It composes the screens and owns only its own wiring and wording.
- **`<app>_admin`** (optional) — a react-admin panel depending on `@jzen/admin-core`.

**How that dependency is expressed, and where it's headed.** Today the framework packages are
**unpublished** (all `0.1.0`, `publish_to: none`), so an app inside this repository consumes them
by **local path** — a `path:` dep into `client/`, a `<relativePath>` inheritance for Maven, a
source alias for the admin scaffold. That path dependency *is* the distribution mechanism for now
(STANDARDS "Package modularity"). **The goal is publication** — `zen_*` to pub.dev, the Java
modules to a Maven registry, `@jzen/*` to npm — at which point an external app depends on a
registry version instead of a path, and `0.1.0 → 0.2.0` is a version bump like any other. Until
then, an out-of-repo app points at a local checkout or a private registry; it never vendors the
source.

Register an in-repo app client in `apps/pubspec.yaml`'s workspace and the app server under the
`apps/*/…_server` build, and the same `task build` / `task test` cover it. The framework
resources you inherit for free (auth, admin-user management, the jobs trigger) are in
[`server/README.md`](server/README.md); what each surface assembles is in
[`apps/zen_demo/README.md`](apps/zen_demo/README.md). Testing is the same story as the reference
app: unit suites per surface, plus your own live end-to-end suite modelled on `zen_demo`'s — a
second app gets its *own* e2e gate (ADR-001).

## Deploy

**The backend has a deploy path today; the web and admin surfaces do not yet.** jZen ships one
deploy task — the Quarkus server as a **native image** to Cloud Run:

```bash
task deploy:cloudrun
```

- **Backend — done.** `deploy:cloudrun` builds the native image and pushes it to Cloud Run.
- **Web app and admin panel — planned, not yet wired.** Both are static bundles (`flutter build
  web` for the client, `task build:admin` → a Vite bundle for the panel) and both belong on GCP
  the same way the backend does — a container on Cloud Run, or GCP static hosting. There is no
  `deploy:web` / `deploy:admin` task yet, and the backend container currently serves the API only
  (the web/admin bundles are not baked in, and in local dev they run on their own origins behind
  CORS). Wiring their deployment is open work, not a deliberate exclusion.
- **Native mobile/desktop — later.** App-store / notarized-build pipelines are outside what the
  framework automates for now, and that one *is* fine to leave to each app.

> jZen has never actually been deployed or published: no live Cloud Run service, no pub.dev / npm
> package, no production database. The backend deploy path is defined and exercised up to the
> point real GCP credentials are required.

The Cloud Run deploy runs a **single instance by design** (`--max-instances=1`,
`--min-instances=0`, `--concurrency=200`): a deliberate cost floor, not a scaling ceiling.
Because at most one instance ever runs, in-process state (rate limiting, caches, counters) is
valid by construction; the trigger to externalize state is the decision to raise
`--max-instances` above 1. Scale-to-zero means scheduled work is driven from **outside** the
container — one Cloud Scheduler entry calls an authenticated trigger endpoint. The
`deploy:cloudrun` task summary (`task --summary deploy:cloudrun`) lists the required Secret
Manager secrets and the one-time scheduler setup. See STANDARDS "Deployment model".

## Licence and contribution

jZen is licensed under the **Apache License 2.0** — see [`LICENSE`](LICENSE). Each framework
library and application module carries a byte-identical copy in its own directory. The product
is versioned in lockstep: every package and module shares one version (`0.1.0` today), which
*is* the product version (STANDARDS "Versioning").

Decisions that change an earlier architecture document are recorded, with justification, in
[`docs/architecture/DECISIONS.md`](docs/architecture/DECISIONS.md) — an append-only archive.
Before non-trivial work, read the architecture set and follow STANDARDS; that is the whole of
the contribution guide.
