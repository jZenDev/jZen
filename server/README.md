# server/ — the Java/Quarkus framework libraries

`server/` is the Java side of the jZen **framework**: a multi-module Maven reactor of reusable
**libraries** built on **Quarkus** (they are Quarkus extensions and CDI/JAX-RS providers, not a
hand-rolled stack — the two leaf modules `zen-proto` and `zen-core` are deliberately Quarkus-free
so they stay reusable, but the tier targets Quarkus). It contains no runnable application — the
runnable Quarkus app is a separate module under [`apps/`](../apps/zen_demo/README.md) that
assembles these libraries. This split is
what lets the layout express jZen's package boundaries (see
[`../docs/architecture/DECISIONS.md`](../docs/architecture/DECISIONS.md) ADR-001).

Baseline: **Quarkus 3.32.2 on Java 25**. The Maven wrapper (`./mvnw`) is committed, so the
build is reproducible without a system Maven. The Java namespace is bare `zen` (ADR-006):
`groupId zen`, packages `zen.core` / `zen.transport` / `zen.demo`.

## How the reactor is put together

`server/pom.xml` (`zen-parent`, `packaging pom`) is **both**:

- the **parent** — the BOM, the Java version, and plugin/dependency management every module
  inherits (the Apache-2.0 `<licenses>` block lives here and is inherited too); and
- the **aggregator** — it builds and `install`s the framework libraries into the local Maven
  repository.

An app server (e.g. `apps/zen_demo/zen_demo_server`, the only `quarkus`-packaged module)
inherits `zen-parent` **across directories** via `<relativePath>` and resolves the libraries
from the local repository — never by relative source paths. So the flow is always: install the
libraries here, then the app package resolves them.

## Modules

| Module | Holds | Notes |
|---|---|---|
| `zen-proto` | generated Java DTOs | Compiles `proto/zen/v1/*.proto`. Leaf module, only `protobuf-java`. Dependency-free so the protobuf plugin never resolves an unbuilt internal jar at generate-sources time. |
| `zen-core` | `ZenResult`/`ZenError`, `ZenStatus`, `AcceptLanguage`, `ZenLocales` | No JAX-RS, no Panache, no Quarkus. That isolation is the module's most valuable property. |
| `zen-transport` | the dual-mode negotiation seam (below) | Consumes `zen-proto`. Carries a Jandex index so its providers are discovered. The reference for the two rules below. |
| `zen-identity` | Supabase JWT, `User` entity, role augmentor, and the reusable `AuthResource` + `AdminUserResource` | Auth is framework-side, so every app inherits the auth and admin-user surface just by depending on the module. |
| `zen-email` | `EmailService` over `quarkus-mailer` | The mechanism only; the application owns every word of every template. |
| `zen-jobs` | the master tick and persisted job state | Guaranteed scheduled work under scale-to-zero — due-ness computed from `last_run_at`, not from a timer firing. |

> The module map in an early draft of ROADMAP Step 9 read
> "`zen-proto/core/transport/identity/email/app`". That is stale: `zen-app` was relocated to
> `apps/zen_demo/zen_demo_server` (ADR-001) and `zen-jobs` was added later (ADR-008). The table
> above is the built truth.

## The dual-mode transport seam

The core mechanism: **a developer defines a domain model and nothing else; the framework
negotiates the wire format.**

1. **`ZenTransportFilter`** (`@PreMatching` filter in `zen-transport`) reads the
   `X-Zen-Transport` request header — values `json` / `protobuf`, negotiation order header →
   content-type sniff → default JSON — and rewrites `Accept`/`Content-Type` accordingly. It is
   scoped to `api/` paths so it never rewrites `Accept` on `/openapi` or `/q/health`.
2. Standard JAX-RS content negotiation then dispatches to one of two body writers registered
   for `com.google.protobuf.Message`: `ProtobufMessageBodyWriter/Reader` (binary) or
   `ProtoJsonMessageBodyWriter/Reader` (canonical proto3 JSON via `JsonFormat`).
3. Resources return proto messages; **MapStruct** maps the Panache entity ⇄ the proto message.
4. The response echoes `X-Zen-Transport`, so a caller can confirm which format it got.

There is also a **first-class WebSocket** surface (`quarkus-websockets-next`) — single-format,
always binary Protobuf frames; the dual JSON/Protobuf negotiation is an HTTP-only concern. See
[`../docs/architecture/BLUEPRINT.md`](../docs/architecture/BLUEPRINT.md) "The dual-mode
transport seam".

## Two non-negotiable rules the seam depends on

- **Every library module contributing CDI beans or JAX-RS providers must run
  `jandex-maven-plugin`.** Quarkus discovers `@Provider`/bean classes from a dependency jar
  only if it carries `META-INF/jandex.idx`. Omit it and the module's filters, body writers,
  exception mappers, and augmentors **silently do nothing** — no error. `zen-transport` is the
  reference (`zen-transport/pom.xml`).
- **No server-side `quarkus-rest-jackson`.** jZen is proto-first; its JSON is canonical proto3
  JSON from `JsonFormat`. Jackson's writer greedily claims `application/json` through a
  build-time path that ignores writer priority and serializes proto builder internals (500s),
  so it must be *absent*, not out-prioritized. (Client-side `quarkus-rest-client-jackson` in
  `zen-identity` is fine — outbound Supabase calls are not proto.)

Because SmallRye cannot cleanly introspect protobuf classes, resources return
`jakarta.ws.rs.core.Response` annotated with `@APIResponse(… @Schema(ref = "…"))`, and the
clean component schema is supplied by the app's static `META-INF/openapi.yaml` (paths scanned
from annotations merge over it). See STANDARDS "OpenAPI and the REST surface".

## Building and testing

Everything below runs through the Taskfile, from the repository root:

```bash
task build:server          # install the framework libraries into the local Maven repo
task test:server           # run the framework libraries' own unit tests
task test:apps:server      # run the reference backend's @QuarkusTest suite
```

**Where the backend tests live.** A `@QuarkusTest` needs an assembled application, so the
backend's integration tests live in the app module (`apps/zen_demo/zen_demo_server`), not in a
library. They use **Dev Services Postgres**, so **Docker must be running**. `task
test:apps:server` installs the framework libraries first, then runs the app server's tests.

To run a single backend test:

```bash
cd server && ./mvnw -B -q install -DskipTests \
  && ./mvnw -B -f ../apps/zen_demo/zen_demo_server/pom.xml test -Dtest=AdminUserResourceTest#methodName
```

For live dev with reload, `task run:server` runs the reference backend in Quarkus dev mode on
`:8080`. The native production build is `task build:server:native` (container build, pinned to
`linux/amd64`).

## Configuration

The server uses **runtime** MicroProfile config (`application.properties` in the app server),
because one binary serves every client and has no bundle to shrink — the deliberate opposite of
the client's compile-time rule. Notable keys, all environment-overridable:

| Concern | Keys |
|---|---|
| Supabase | `SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_JWKS_URL` |
| Database | `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` (local default: Supabase Postgres on `54322`) |
| Auth cookies | `zen_access_token` / `zen_refresh_token`, read via `mp.jwt.token.cookie` with `proactive=true` |
| Transport | `zen.transport.header` (`X-Zen-Transport`), `zen.transport.default-format` (`json`) |
| CORS | `CORS_ORIGINS` |
| Email (`%prod`) | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` |
| Jobs trigger | `ZEN_JOBS_TRIGGER_TOKEN` (fails closed when unconfigured) |

Migrations are **Flyway only**, at the classpath location `db/migration`; each framework
library owns a reserved version band (STANDARDS "Database migrations"). `supabase/migrations/`
stays empty so there is never a second migration system on one database.
