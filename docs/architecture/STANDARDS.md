# jZen Standards

The rules that keep the monorepo honest. Philosophy is in
[`MANIFESTO.md`](./MANIFESTO.md); the structure they apply to is in
[`BLUEPRINT.md`](./BLUEPRINT.md).

## Orchestration

- **`Taskfile.yml` is the only orchestrator.** It triggers native tools; it never
  replaces them. `mvnw` owns Java resolution, `dart pub` owns Dart, `pnpm` owns
  TypeScript. A task that reimplements what a package manager already does is a bug.
- This replaces DartZen's Melos (`../DartZen/melos.yaml` + ~170 lines of `melos.scripts`
  in `../DartZen/pubspec.yaml:46-217`). Do not reintroduce Melos, Gradle-as-orchestrator,
  or any second build driver.
- Run `task doctor` after cloning. It distinguishes tools the Java build needs from the
  extra tools (`protoc`, `protoc-gen-dart`) that only Dart proto codegen needs — the
  Java build resolves `protoc` from Maven Central and needs no system install.

## Code generation

- **No custom magic.** Only industry-standard, inspectable generators:
  protoc / MapStruct / Panache (Java); Freezed / json_serializable / protoc_plugin
  (Dart); openapi-typescript / react-admin (TS). No bespoke DSLs or frameworks.
- **Generated output is committed across a toolchain boundary, regenerated within one.**
  An artifact is tracked in git exactly when the toolchain that consumes it cannot produce
  it, so no consumer needs a tool it would not otherwise install:
  - **Tracked** — the Dart messages (`client/zen_transport/lib/src/generated/**`) and the
    admin TypeScript (`apps/*/*_admin/src/api/schema.generated.ts`). Regenerating the first
    needs a *system* `protoc` plus `protoc-gen-dart` (which is why `task doctor` lists them
    apart, as tools the Java build does not need); the second needs a full Quarkus build.
    Neither is something a Flutter or frontend developer should have to install before the
    package will compile.
  - **Not tracked** — the Java DTOs (`server/zen-proto/target/generated-sources/`) and the
    merged `openapi.json` (`target/openapi/`). `protobuf-maven-plugin` resolves the `protoc`
    binary from Maven Central, so `./mvnw` alone regenerates the DTOs hermetically, and
    `openapi.json` is an intermediate whose only consumer is the TypeScript generator.

  The exit condition is publishing: once a package ships to pub.dev or npm, its archive
  carries its own generated code and the repository can stop tracking it. Until then the
  path dependency *is* the distribution mechanism.
- **A tracked generated file is never hand-edited.** Fix the source (`.proto` or an
  annotation) and regenerate. Its diff is reviewed like any other code — and is the one
  place a wire change surfaces *as* a change: a new header parameter on a resource is three
  lines in `schema.generated.ts` and easy to miss in the Java diff that caused it. They are
  marked `linguist-generated` in `.gitattributes`, which collapses them by default in review
  without hiding them from `git diff` or from the gate below.
- **`task sync:contracts` is the gate.** It regenerates every cross-language artifact and
  fails if a committed generated file changed. Wire it into CI as a required check. A red
  `sync:contracts` means the contract and its generated clients have drifted — the exact
  bug class the gate exists to stop. Note this is *why* the boundary artifacts are tracked:
  the gate is `git status` over those paths, and git cannot report a file it is not tracking.

## Backend (Quarkus) multi-module rules

Two rules the walking skeleton established, both mandatory for every backend module:

- **Every library module that contributes CDI beans or JAX-RS providers must run the
  `jandex-maven-plugin`.** Quarkus discovers `@Provider`/bean classes from a dependency
  jar only if it carries `META-INF/jandex.idx`. Omit it and the module's filters,
  `MessageBodyWriter`s, exception mappers, and augmentors silently do nothing — no error,
  no negotiation. `zen-transport` is the reference (`server/zen-transport/pom.xml`).
- **No server-side `quarkus-rest-jackson`.** jZen is proto-first: every response body is
  a proto message, and its JSON is canonical proto3 JSON from `JsonFormat` via
  `ProtoJsonMessageBodyWriter`. The server Jackson writer greedily claims
  `application/json` through a build-time path that ignores writer priority, so it must
  be absent, not merely out-prioritized. (Client-side `quarkus-rest-client-jackson` in
  `zen-identity` is fine — it serializes outbound Supabase calls, which are not proto.)

## Source of truth

- `.proto` files under `proto/zen/v1/` are canonical for **models**.
- SmallRye-annotated Quarkus resources are canonical for the **REST surface** (paths,
  verbs, status codes).
- Everything else — Java DTOs, Dart messages, `openapi.json`, TS types — is **derived**.
  Editing a derived artifact by hand is a defect, and `sync:contracts` will catch it.

## Package modularity (hybrid, not monolith)

jZen is a monorepo of **first-class versioned packages**, not one deployable blob. It is a
**framework**: `server/` + `client/` are the reusable libraries; `apps/<app>/{<app>_client,
<app>_server}` are applications that assemble them (see [`DECISIONS.md`](./DECISIONS.md)
ADR-001). The repository root is language-neutral (only `Taskfile.yml`).

- **Dart:** relative-path deps in `pubspec.yaml` with `resolution: workspace`. `client/` and
  `apps/` are two workspaces; app clients path-depend into `client/` libraries. Each package
  shares the product version — see Versioning.
- **Java:** multi-module Maven. `server/pom.xml` (`zen-parent`) is the parent (GAV managed in
  its `dependencyManagement`) and the aggregator that `install`s the framework libraries; an
  app server inherits `zen-parent` across directories via `<relativePath>` and resolves the
  libraries from the local repository — never by relative source paths.
- A new project or external consumer must be able to depend on a package by local path or
  private registry without pulling the whole monorepo — which is exactly how `apps/*` consume
  the framework.

## Versioning — fixed/lockstep, one product version

jZen is a **product**, not a loose bag of libraries, so it uses **unified (lockstep)
versioning**: every package and module — Java, Dart, TypeScript — carries the same version,
which *is* the product version. jZen 2.3.1 means `zen_core`, `zen_transport`, `zen-app`,
`@jzen/admin-core` are all 2.3.1. This is the industry norm for a coherent product (Angular, Nx,
Spring Boot's BOM) and the reason is exactly the confusion to avoid: users and external
developers must never have to reconcile "jZen v2" with "zen_core 1.2.1, zen_transport 2.0.0".

- **The product version is the SemVer contract, not each package.** A major bump means a
  breaking change exists *somewhere in the product*; `feat:` → minor, `fix:` → patch across
  the whole repo. A package may ride a major it did not itself break — that is expected and
  fine; its `CHANGELOG.md` records whether it actually changed. The SemVer guarantee is at
  the product level.
- **This is what the backend already does.** Every Maven module inherits `zen-parent`'s
  version (`server/pom.xml`); lockstep simply extends that to the Dart and TS sides. One
  release command bumps everything together.
- **Product version ≠ API/wire version.** They are independent axes. The wire contract is
  versioned in the proto package path (`proto/zen/v1/` → `zen.v1`) and evolves on its own
  schedule: the product can go 1.x → 2.0 while the API stays `zen.v1` (still
  backward-compatible), or a breaking API change introduces `zen.v2` protos *alongside*
  `v1` without forcing a product major. Never conflate "jZen 2.0" with "API v2".
- **Atomic upgrades still hold.** A change to a shared package must be testable in
  isolation — `task test:server`, `task test:client`, `task test:admin` each run one
  language's suite. Never the "clone-and-modify" anti-pattern: fix the shared package,
  release the product, let consumers pick up the new version.

## Fidelity to the source

- **The donor repos are read-only.** `../DartZen` and `../BugEater` are reference sources.
  Never modify, move, delete, or even reformat a file in either — all work happens inside
  `jZen/`. They are studied and copied from, never touched.
- **Cite the source — for now.** During the migration every ported decision names the
  legacy file it came from; unsourced logic is suspect ("logic not found"). These
  citations are deliberate, removable scaffolding: ROADMAP step 8 strips every DartZen /
  BugEater reference and makes jZen a standalone product with its own docs.
- **Do not carry over donor bugs.** Named examples, all documented in
  [`BLUEPRINT.md`](./BLUEPRINT.md): DartZen's `test` script swallows Flutter failures
  with `|| true` (jZen's `task test:client` does not); `ZenClient` swallows decode errors
  (**TA-6**, fix on port); the `__session` cookie packing is a Firebase-Hosting
  workaround (**TA-4**, dropped).

## Client config is compile-time (non-negotiable)

- The Dart/Flutter client **keeps compile-time config** (`String.fromEnvironment`) and the
  `if (dart.library.io)` / `if (dart.library.html)` conditional-import selectors. This is
  what lets the toolchain tree-shake native-only code (e.g. the Protobuf binary path) out
  of the JS/Wasm web bundle and web-only code out of the AOT-native binary. No native code
  in a web bundle, and vice versa. Runtime config on the client is forbidden — it defeats
  tree-shaking. See **TA-7**.
- The **server** uses runtime config (MicroProfile / `application.properties`): one binary
  serves both native and web clients, and it has no bundle to shrink.

## Deployment model

- **Single instance by design, for cost.** Prod runs at `--max-instances=1`,
  `--min-instances=0`, `--concurrency=200`. This is a deliberate cost floor, not a
  scaling limit: the native-image server is fast and small enough to serve the target
  load (~2K MAU) on one instance, and `min=0` means there is no always-warm instance to
  pay for — cold starts are accepted as the cost/latency trade. A native image's
  sub-second start makes that acceptable.
- **One instance makes in-process state valid.** Because at most one instance ever runs,
  in-process state — rate limiting, in-memory caches, login-attempt counters — is correct
  by construction. This is a feature of the deployment model, not a hazard. **The trigger
  to externalize state (Postgres/Redis) is the decision to raise `--max-instances` above
  1**, e.g. a login counter shared across instances. Until then, keep it simple and
  in-process.
- **No Firebase Hosting.** jZen serves Cloud Run directly. This is load-bearing: it is
  why normal cookie names and proactive auth work (**TA-4**). Do not reintroduce a
  cookie-stripping edge without also reintroducing the `__session` hack.
- **Native prod builds.** Prod ships a native image (`task build:server:native` →
  `Dockerfile.native-micro`). Container builds are pinned to `linux/amd64` so the image
  matches Cloud Run regardless of the developer's machine. The native image is also what
  makes the single-instance / scale-to-zero cost model work: fast cold start, small
  memory footprint (`--memory=256Mi`, `--cpu=1`).

## Frontend split

- **Product UI:** the DartZen Flutter packages, for mobile / desktop / web.
- **Admin UI:** a `react-admin` framework scaffold (`@jzen/admin-core` in `admin/`:
  data provider, auth provider, login page) that each app assembles into its own panel
  under `apps/<app>/<app>_admin` (ADR-005), consuming the same OpenAPI-documented REST
  API via generated `openapi-typescript` types. Scaffolded clean — nothing in BugEater's
  three React apps used react-admin or had an admin screen, and their conventions conflict
  three ways across React 18/19.
- Admin always speaks `X-Zen-Transport: json`; Protobuf binary is for native apps only.
