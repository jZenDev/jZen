# jZen Blueprint

The concrete architecture. Every decision below cites the legacy file it derives from.
Philosophy is in [`MANIFESTO.md`](./MANIFESTO.md); sequencing in
[`ROADMAP.md`](./ROADMAP.md). Decisions that change earlier docs are logged, with
justification, in [`DECISIONS.md`](./DECISIONS.md).

## Repository layout

jZen is a **framework**: `server/` and `client/` are the Java and Dart framework
**libraries**; `apps/` holds full-stack **applications** that assemble them (see
[`DECISIONS.md`](./DECISIONS.md) ADR-001).

```
jZen/
├── Taskfile.yml              # the single orchestrator (replaces DartZen's Melos)
├── proto/zen/v1/             # CANONICAL models - *.proto (health, common, ...)
├── server/                   # Java FRAMEWORK libraries (multi-module Maven)
│   ├── pom.xml               # zen-parent: parent (BOM/plugin mgmt) AND aggregator, packaging pom
│   ├── zen-proto/            # generated protobuf DTOs; leaf (only protobuf-java)
│   ├── zen-core/             # ZenResult/ZenError, ZenStatus, AcceptLanguage; no Quarkus deps
│   ├── zen-transport/        # dual-mode seam (consumes zen-proto)
│   ├── zen-identity/         # Supabase auth beans, User, RoleAugmentor, + the AuthResource surface
│   └── zen-email/            # EmailService (new) over quarkus-mailer/Brevo
├── client/                   # Dart/Flutter FRAMEWORK libraries (pub workspace)
│   ├── pubspec.yaml          # workspace root
│   └── zen_core/  zen_transport/  zen_identity/  zen_localization/  zen_ui_*/
├── apps/                     # APPLICATIONS built on the framework
│   ├── pubspec.yaml          # pub workspace root for the app clients
│   └── zen_demo/             # the reference app (showcase + living e2e test stand)
│       ├── zen_demo_client/  # Flutter client (pub workspace member; deps ../../client/zen_*)
│       └── zen_demo_server/  # Quarkus reference backend (inherits zen-parent via relativePath)
├── admin/                    # ReactAdmin + Vite + openapi-typescript
├── supabase/                 # config.toml, migrations
└── docs/architecture/        # these documents (+ DECISIONS.md)
```

Folder names are industry-standard by role. Framework libraries sit flat within `server/`
and `client/`; applications live under `apps/<app>/{<app>_client, <app>_server}`. The
repository **root stays language-neutral** — only `Taskfile.yml` lives there; there is no
root `pom.xml` or root `pubspec.yaml` (each stack roots its build inside its own folder).
The backend is a single Maven reactor of libraries whose app modules inherit `zen-parent`
across directories; the two pub workspaces (`client/` libs, `apps/` clients) resolve
independently, app clients path-depending into `client/`. `proto/zen/v1/` mirrors the proto
package `zen.v1` (the same reason Java lives under `dev/zen/…`); `v1` is the API version.

## Backend: why multi-module

BugEater is a **single** Maven module — one `pom.xml` with `<packaging>quarkus</packaging>`
at the root (`../BugEater/bugeater-quarkus/pom.xml`). That layout cannot express jZen's
package boundaries, so jZen inverts it: the aggregator is `<packaging>pom</packaging>`,
every module is a plain-jar **framework library**, and the runnable Quarkus app is a
*separate* module under `apps/` that assembles them. `server/pom.xml` (`zen-parent`) is both
the parent (BOM, Java version, plugin/dependency management) and the aggregator that builds
and `install`s the libraries; an app server (e.g. `apps/zen_demo/zen_demo_server`, the only
`quarkus`-packaged module) inherits `zen-parent` across directories via `<relativePath>` and
resolves the libraries from the local repository. See [`DECISIONS.md`](./DECISIONS.md)
ADR-001 for the framework/apps split and its Maven mechanics.

The baseline versions are inherited from BugEater's verified setup: **Quarkus 3.32.2 on
Java 25** (`../BugEater/bugeater-quarkus/pom.xml`, properties `quarkus.platform.version`
and `maven.compiler.release`). The Maven wrapper is copied from the donor so the build
is reproducible without a system Maven.

| Module | Ports from | Notes |
|---|---|---|
| `zen-proto` | (generated) | Compiles `proto/zen/v1/*.proto` to Java DTOs. Leaf module, only `protobuf-java`. Dependency-free so the protobuf plugin never resolves an unbuilt internal jar at generate-sources time. |
| `zen-core` | `../DartZen/packages/dartzen_core` | `ZenResult`/`ZenError`/logging. No JAX-RS, no Panache — mirrors dartzen_core's `meta`-only isolation. |
| `zen-transport` | `../DartZen/packages/dartzen_transport` | The negotiation seam (below); consumes `zen-proto`. Carries a Jandex index so its providers are discovered. |
| `zen-identity` | `../BugEater/.../auth/`, `.../application/security/`, `.../user/User.java` | Supabase JWT, `User` entity, role augmentor. |
| `zen-email` | `../BugEater/.../user/UserCleanupService.java` + mail templates | The service interface is **new**; see below. |
| `zen-app` | `../BugEater/.../application/**` | Filters, exception mappers, health, REST resources, SmallRye OpenAPI. |

## The dual-mode transport seam

This is the mandate's core mechanism and DartZen's crown jewel. The design goal: **a
developer defines a domain model and nothing else** — the framework negotiates the wire
format.

### What already exists in DartZen

- The negotiation header `X-DZ-Transport`
  (`../DartZen/packages/dartzen_transport/lib/src/zen_transport_header.dart:4`).
- A two-value format enum (`json`, `msgpack`) with a case-insensitive `parse`
  (same file).
- Server-side negotiation order — header → content-type sniff → default JSON — in
  `../DartZen/packages/dartzen_server/lib/src/middleware/transport_middleware.dart:75-99`.

### What changes

**The header is renamed `X-DZ-Transport` → `X-Zen-Transport`** ("DZ" meant DartZen). The
negotiation order is preserved.

The binary codec goes from hand-written MessagePack
(`../DartZen/packages/dartzen_transport/lib/src/codecs/msgpack_encoder.dart`, 189 LOC)
to **Protobuf**. This is a replacement, not a port: MessagePack there is schemaless and
self-describing, carrying an untyped `Object? data`
(`../DartZen/packages/dartzen_transport/lib/src/zen_request.dart:23`); Protobuf requires
a declared message per payload (see **TA-2**).

The `{id, status, data, error}` request/response envelope
(`zen_request.dart:26`, `zen_response.dart:41`) is **dropped**. It is already redundant:
DartZen's own `ZenClient` never parses it — the server envelope lands whole inside
`ZenResponse.data` (`../DartZen/packages/dartzen_transport/lib/src/internal/client/zen_client.dart:161`).
In jZen, HTTP status carries `status`, the `X-Request-ID` header carries `id`, and a
shared `ZenError` proto (`proto/zen/v1/common.proto`) carries `error`. Endpoints return
typed proto messages directly.

### Quarkus implementation

1. **`ZenTransportFilter`** — a `@PreMatching ContainerRequestFilter` in `zen-transport`.
   Reads `X-Zen-Transport`, and rewrites `Accept`/`Content-Type` to
   `application/x-protobuf` or `application/json`. Negotiation order ported from
   `transport_middleware.dart:75-99`.
2. Standard JAX-RS content negotiation then dispatches to one of two body writers
   registered for `com.google.protobuf.Message`:
   - **`ProtobufMessageBodyWriter/Reader`** — `message.writeTo(out)` / `parseFrom(in)`.
   - **`ProtoJsonMessageBodyWriter/Reader`** — `JsonFormat` from `protobuf-java-util`.
     This is required: stock Jackson serializes protobuf-generated classes into their
     builder internals. Canonical proto3 JSON is a spec that Dart's `protoc_plugin` and
     `openapi-typescript` also emit, so all three languages agree on the JSON shape.
3. Resources return proto messages; **MapStruct** maps Panache entity ⇄ proto message.
4. The response echoes `X-Zen-Transport`, matching DartZen's server behavior
   (`transport_middleware.dart` sets it on the way out).

### The WebSocket surface (a first-class product feature)

Alongside the request/response HTTP surface, jZen serves a **WebSocket** endpoint as a
first-class part of the product, not a test fixture. The client side is `zen_transport`'s
`ZenWebSocket`, which sends and receives typed proto messages via `ZenProtoCodec`; the server
side is a Quarkus `quarkus-websockets-next` endpoint (landed with `zen_demo` in ROADMAP step 4
as `/api/v1/demo/ws`). Unlike the HTTP surface, the socket is **single-format**: frames are
binary Protobuf on every platform (the demo constructs `ZenWebSocket` with
`ZenTransportFormat.protobuf`), so the server handler stays simple. The dual JSON/Protobuf
negotiation is an HTTP concern; the socket carries one wire format. `zen_demo` demonstrates it
and `task test:e2e` asserts it end to end.

### Removed in the port (dead weight in DartZen)

- The duplicated `transport_middleware.dart` — it exists twice, near-verbatim
  (`../DartZen/packages/dartzen_transport/lib/src/internal/server/transport_middleware.dart`
  and the `dartzen_server` copy); only the server copy is ever wired up.
- The identical `internal.dart` / `framework_internal.dart` export lists — one is dead.
- The `ZenTransport` / `TransportDescriptor` facade, whose `_CloudTransportExecutor` is a
  self-declared placeholder that performs no I/O
  (`../DartZen/packages/dartzen_transport/lib/src/executors/cloud_executor.dart:13-15`),
  despite the README calling it "the single public entry point."

## Contract lineage (source of truth)

```
proto/zen/v1/*.proto
  ├─ protoc ─────────────▶ Java DTOs      (protobuf-maven-plugin, in zen-proto)
  ├─ protoc ─────────────▶ Dart messages  (protoc_plugin, via Taskfile)
  └─ protoc ─────────────▶ model schemas ─┐
                                          ├─▶ merged openapi.json ─▶ openapi-typescript
  Quarkus resources + SmallRye ── paths ──┘                          ─▶ admin types
```

Proto is upstream for **models**; SmallRye OpenAPI is authoritative for the **REST
surface** (paths, verbs, status) that proto cannot express. Nothing downstream is
hand-edited. `task sync:contracts` regenerates everything and fails the build if a
committed generated file changed — the gate that blocks out-of-sync bugs.

## Authentication

Ported from BugEater, which already runs Supabase JWT. Landed in ROADMAP step 3.

- `SupabaseAuthClient` — a `@RegisterRestClient` interface with `@CircuitBreaker`/
  `@Retry`/`@Timeout` per call (`../BugEater/.../auth/SupabaseAuthClient.java`),
  re-pointed at Supabase Auth (GoTrue) REST: `POST /token` (login and refresh, by
  `grant_type`), `/signup`, `/recover`, `PUT /user`.
- JWT verified against Supabase JWKS with ES256
  (`../BugEater/.../application.properties:64-69`).
- Role loaded from the `users` table by a `SecurityIdentityAugmentor`, not from the JWT
  (`../BugEater/.../application/security/RoleAugmentor.java`).
- The `User` entity is adopted from `../BugEater/.../user/User.java` — its `users` table
  has zero learning-domain columns (see **Persistence** for the compliance columns it does
  keep).

**REST surface.** `AuthResource` lives in `zen-identity` — a reusable **framework** resource, so
every jZen app inherits the auth surface just by depending on the module (see
[`DECISIONS.md`](./DECISIONS.md) ADR-001; this reverses the earlier "auth lives in the app"
decision). zen-identity is a Jandex-indexed library of the auth beans, the `User` entity, the
MapStruct `User` → `Identity` mapper, **and** the `AuthResource`/`AuthExceptionMapper`; Quarkus
discovers the JAX-RS resource from the jar via the Jandex index. The app module still runs SmallRye
OpenAPI and supplies the referenced component schemas through its static `META-INF/openapi.yaml`
(paths from the library, schemas from the app). The endpoints back DartZen's `IdentityRepository`
(TA-5): `POST /api/v1/auth/{login,register,restore-password,logout,refresh}` and
`GET /api/v1/auth/identity`. Each returns a typed proto (`Response` + `@Schema(ref=...)`);
errors return the shared `ZenError` proto via an exception mapper.

**Session cookies and refresh.** Login/register/refresh set `zen_access_token` (httpOnly,
1 h) and `zen_refresh_token` (httpOnly, 7 d), plus a JS-readable `XSRF-TOKEN`. SmallRye JWT
reads the access cookie directly (`mp.jwt.token.cookie`, `proactive=true`), so an
authenticated request is a plain cookie request; `POST /auth/refresh` exchanges the refresh
cookie via Supabase (`grant_type=refresh_token`) and re-issues the cookies.

**Simplified on the way in (TA-4):** BugEater packs `"access|refresh"` into a single
`__session` cookie, sets `quarkus.http.auth.proactive=false`, and carries a manual
`SessionFilter` to unpack and refresh it (`application.properties:70-77`). All three exist
*only* because Firebase Hosting strips every cookie except `__session` at the CDN edge (its
ADR-034). jZen serves Cloud Run directly with no Firebase Hosting, so it uses normally-named
cookies (`zen_access_token`), `mp.jwt.token.cookie`, and `proactive=true` — the standard
SmallRye-JWT path. The `SessionFilter` is therefore **not ported**; SmallRye JWT authenticates
from the cookie, and the `RoleAugmentor` loads the role straight from the `users` table.

## Email

There is **no `EmailService` in BugEater to port** — the interface is new code. Exactly
one Java file sends mail: `../BugEater/.../user/UserCleanupService.java:197` injects
`io.quarkus.mailer.Mailer` directly. Brevo is used only as a plain SMTP relay (the
string `smtp-relay.brevo.com` appears once, in `../BugEater/.../scripts/build-prod.sh:33`,
written into a GCP secret); nothing in the Java code is Brevo-specific. jZen adds a clean
`EmailService` (`zen-email`) over `quarkus-mailer`, portable to any SMTP provider by
changing `SMTP_HOST`. Brevo is the transport and is locale-agnostic. The mailer config
block (`application.properties:161-169`) is the genuinely reusable part.

**Localized templates (ROADMAP step 6).** Email is user-facing, so it is localized from
the start — Quarkus supports this natively, and Brevo (being just SMTP) imposes nothing.
`EmailService.send(...)` resolves the recipient's locale from the `users.language` column
(the same source `../BugEater/.../i18n/LocaleFilter.java` uses), then renders a per-locale
Qute template — `@Localized` template variants (e.g. `templates/mail/welcome_en.html`,
`welcome_uk.html`) with subject lines from a Qute `@MessageBundle` (`AppMessages` +
`AppMessagesUk`), the same mechanism BugEater already uses for its HTML i18n. BugEater's
own two mail templates are English-only hardcoded strings — jZen does not carry that
limitation forward. `SUPPORTED` locales start at `{en, uk}` and grow with the message
bundles, no code change per template.

## Persistence

PostgreSQL via Hibernate Panache (active-record; BugEater has 19 `PanacheEntityBase` and
zero repository classes). Flyway migrates at start
(`../BugEater/.../application.properties:44-45`) and is the single migration authority —
`supabase/migrations/` stays empty so there is never a second migration system on one
database. Only BugEater's infrastructure migrations are relevant — its `V1__init.sql`
(the `users` table) and `V9__enable_rls.sql`. The other migrations (V2–V27) are a mix, not
one block of content: most add or seed learning-domain schema (courses, lessons, quizzes,
challenges, news, wishlist), but a few alter the `users` table itself — `V2` adds
`analytics_consent`, `V18` adds `is_premium` and the deletion-warning timestamps. jZen
carries none of them wholesale; it folds the users-table columns (including those later
compliance additions, see below) into its own consolidated
`zen-identity/db/migration/V1__init_identity.sql`, with RLS in `V2__row_level_security.sql`.
The local database is the Supabase stack on port 54322 (`supabase/config.toml`).

**Reconciling with Supabase `auth.users`.** Supabase owns authentication (`auth.users`);
the jZen `users` table is the application profile, keyed by the same id (the JWT `sub`),
upserted on first login. It carries **no** foreign key to `auth.users`: the `@QuarkusTest`
Dev Services database is plain PostgreSQL with no `auth` schema, and Supabase owns that
table's lifecycle. For the same reason the RLS migration (`auth.uid()` and the `auth` schema
exist only on Supabase) is guarded on `to_regprocedure('auth.uid()')` — it enables RLS and
the owner policy on Supabase, and is a no-op on plain PostgreSQL so tests still migrate.

**Compliance columns are first-class.** The `users` table has zero learning-domain columns,
but it deliberately keeps two cross-cutting product concerns from the donor entity: **payment**
(`is_premium`) and **GDPR / data retention** (`analytics_consent`, `deletion_warning_sent_at`,
`final_warning_sent_at`). These are defaulted/nullable now and their behavior is wired in
later steps (email deletion warnings in step 6, payments in step 7); keeping the columns from
the start avoids a schema migration when that behavior lands.

## Deployment

Cloud Run, native image. Ports `../BugEater/.../scripts/build-prod.sh` and
`Dockerfile.native-micro` into `task deploy:cloudrun`, dropping the `firebase deploy`
step. Runs a **single instance by design** (`--max-instances=1`, `--min-instances=0`,
`--concurrency=200`): a cost floor, not a scaling ceiling — the native server serves the
target load on one instance, and scale-to-zero means no warm instance to pay for. See
[`STANDARDS.md`](./STANDARDS.md) → "Deployment model" for why one instance also makes
in-process state valid.

---

## Technical Assessments

Each states the gap and an **explicit resolution** with the step that implements it. TA-1
and TA-4 are already resolved in code; the rest are specified and land with their package.

### TA-1 · SmallRye OpenAPI cannot cleanly introspect protobuf classes — RESOLVED (ROADMAP step 1)
Protobuf-generated Java classes expose builder internals; SmallRye would document those
as schema fields. Confirmed empirically: a resource returning a bare `HealthStatus`
produced **130+ garbage schemas** (`UnknownFieldSet`, `ParserHealthStatus`,
`descriptorForType`, …) plus a `HealthStatus` full of builder internals.

**Resolution, now proven:** the resource returns `jakarta.ws.rs.core.Response` (opaque to
SmallRye's introspector) annotated with `@APIResponse(... @Schema(ref = "HealthStatus"))`;
the clean `HealthStatus` component is supplied by a static `META-INF/openapi.yaml`, and
SmallRye merges its annotation-scanned *paths* over that base. Result: `openapi.json` with
exactly **1 clean schema**, which `openapi-typescript` turns into a usable TS type. In the
finished system the static `META-INF/openapi.yaml` is generated from `.proto` by a
protoc→OpenAPI step in `task generate:api` (hand-authored for the skeleton to prove the
merge). See `server/zen-app/src/main/java/dev/zen/app/health/HealthResource.java` and
`server/zen-app/src/main/resources/META-INF/openapi.yaml`.

Two implementation facts the spike established, both now load-bearing:

- **No server-side `quarkus-rest-jackson`.** Its JSON `MessageBodyWriter` uses a
  build-time-optimized path that greedily claims `application/json` and bypasses normal
  `MessageBodyWriter` priority — it serializes the proto's builder internals and 500s,
  and `@Priority(1)` on a custom writer does not beat it. Since jZen is proto-first and
  every response body is a proto message whose JSON is canonical proto3 JSON from
  `JsonFormat`, the server Jackson writer is removed entirely (see the note in
  `server/zen-transport/pom.xml`). The custom `ProtoJson`/`Protobuf` writers own
  serialization.
- **Library modules need a Jandex index.** The transport filters and body writers live
  in `zen-transport`, a dependency jar of `zen-app`. Quarkus only discovers `@Provider`
  classes from dependencies that carry `META-INF/jandex.idx`; without it the entire seam
  silently does nothing (no 500 — just no negotiation). `zen-transport` runs the
  `jandex-maven-plugin`. Every jZen library module contributing beans or providers must
  do the same — see STANDARDS.md.

### TA-2 · Protobuf needs a schema where MessagePack needed none
Today `ZenRequest.data` is `Object?` and the msgpack codec has no extension types
(`codecs/msgpack_encoder.dart`), so there is nowhere to hang a type tag. Protobuf requires
a declared message per payload.

**Resolution (per endpoint, from ROADMAP step 3 on):** for each endpoint, declare its
request and response messages in `proto/zen/v1/<domain>.proto`; there is no generic
payload type and no envelope. Cross-cutting shapes live once in
`proto/zen/v1/common.proto` (`ZenError`, `PageRequest`). `task sync:contracts` regenerates
the Java/Dart/TS bindings; **MapStruct** maps the Panache entity ⇄ the proto message so the
resource method only ever names the domain model. This is not a mechanical port of the
untyped envelope — it is accepted, bounded cost paid once per endpoint, and it is what buys
the contract-first guarantee.

### TA-3 · `dartzen_localization` drags in the Flutter SDK
It declares `flutter` as a dependency (`../DartZen/packages/dartzen_localization/pubspec.yaml`)
yet is consumed by Dart-only server packages.

**Resolution:** keep its existing
conditional-import pattern (`loader_flutter.dart` / `loader_io.dart` / `loader_stub.dart`)
and move `flutter` to a dev-only dependency so `zen_localization` is Dart-pure.

### TA-4 · Dropping Firebase Hosting deletes two hacks
BugEater packs `"access|refresh"` into a single `__session` cookie and sets
`quarkus.http.auth.proactive=false` (`application.properties:70-77`) — both only because
Firebase Hosting strips every cookie except `__session` at the CDN edge (its ADR-034).

**Resolution (done, `application.properties`; wired at ROADMAP step 3):** jZen serves
Cloud Run directly, no Firebase Hosting. Use a normally-named cookie `zen_access_token`
with `mp.jwt.token.cookie=zen_access_token` and `quarkus.http.auth.proactive=true` — the
standard SmallRye-JWT path. Both hacks are gone, and STANDARDS forbids reintroducing a
cookie-stripping edge without also reintroducing the packing.

### TA-5 · `IdentityRepository` has no implementation
`../DartZen/packages/dartzen_identity/lib/src/identity_contracts.dart:154` declares the
interface; `FirestoreIdentityRepository`
(`../DartZen/packages/dartzen_identity/lib/src/identity_repository.dart:10`) does **not**
implement it and has a disjoint method set.

**Resolution (ROADMAP step 3):** write a `SupabaseIdentityRepository` in `zen_identity`
that `implements IdentityRepository` exactly as declared (`getCurrentIdentity`,
`loginWithEmail`, `registerWithEmail`, `restorePassword`, `logout`), backed by the
`zen-identity` Supabase endpoints. Discard the `FirestoreIdentityRepository` method set —
it is Firestore drift, not the contract.

### TA-6 · `ZenClient` ignores `selectDefaultCodec()` and swallows decode errors
It hardcodes `format = ZenTransportFormat.json`
(`../DartZen/packages/dartzen_transport/lib/src/internal/client/zen_client.dart:43`) and
silently sets decoded data to `null` on failure (same file, ~line 178).

**Resolution (ROADMAP step 2, porting `zen_transport`):** the client's default format
comes from `selectDefaultCodec()` (the compile-time platform selector — see TA-7), not a
hardcoded literal; a decode failure returns a `ZenError` (`common.proto`) rather than
`null`, so callers see the failure instead of a silent empty result. Both are fixed on
port, covered by tests.

### TA-7 · Config is compile-time — and the client MUST keep it that way
All `dz*` config is compile-time `String.fromEnvironment`
(`../DartZen/packages/dartzen_core/lib/src/dartzen_constants.dart`). This is **deliberate
and load-bearing, not a limitation**: combined with the conditional imports
(`if (dart.library.io)` / `if (dart.library.html)`), compile-time constants like `dzIsDev`
let the toolchain **tree-shake the wrong platform's code out of each bundle** — the
MessagePack/native path is dropped from the JS/Wasm web bundle, and web-only code is
dropped from the AOT-native binary. No native code may leak into a web bundle, and vice
versa. Runtime config would defeat that and bloat every bundle.

**Resolution (explicit split):**
- **Client (Dart/Flutter) keeps compile-time config.** Preserve `String.fromEnvironment`
  and the conditional-import selectors when porting `zen_core`/`zen_transport`. The build
  matrix stays per-`ZEN_ENV`/`ZEN_PLATFORM` (renamed from `DZ_*`). This is a hard rule.
- **Server (Quarkus) uses runtime config.** MicroProfile Config / `application.properties`,
  because one server binary serves both native and web clients and must switch behavior at
  runtime, not build time. It has no bundle to tree-shake.

This is the one client/server asymmetry the architecture mandates on purpose.
