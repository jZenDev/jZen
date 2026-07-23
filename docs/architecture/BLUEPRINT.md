# jZen Blueprint

The concrete architecture, as built. Philosophy is in [`MANIFESTO.md`](./MANIFESTO.md);
sequencing in
[`ROADMAP.md`](./ROADMAP.md). Decisions that change earlier docs are logged, with
justification, in [`DECISIONS.md`](./DECISIONS.md).

## Repository layout

jZen is a **framework**: `server/` and `client/` are the Java and Dart framework
**libraries**; `apps/` holds full-stack **applications** that assemble them (see
[`DECISIONS.md`](./DECISIONS.md) ADR-001).

```
jZen/
├── Taskfile.yml              # the single orchestrator
├── proto/zen/v1/             # CANONICAL models - *.proto (health, common, ...)
├── server/                   # Java FRAMEWORK libraries (multi-module Maven)
│   ├── pom.xml               # zen-parent: parent (BOM/plugin mgmt) AND aggregator, packaging pom
│   ├── zen-proto/            # generated protobuf DTOs; leaf (only protobuf-java)
│   ├── zen-core/             # ZenResult/ZenError, ZenStatus, AcceptLanguage; no Quarkus deps
│   ├── zen-transport/        # dual-mode seam (consumes zen-proto)
│   ├── zen-identity/         # Supabase auth beans, User, RoleAugmentor, + the AuthResource surface
│   ├── zen-email/            # EmailService (new) over quarkus-mailer/Brevo
│   └── zen-jobs/             # guaranteed scheduled work: external trigger + persisted job state
├── client/                   # Dart/Flutter FRAMEWORK libraries (pub workspace)
│   ├── pubspec.yaml          # workspace root
│   └── zen_core/  zen_transport/  zen_identity/  zen_ui_*/
├── apps/                     # APPLICATIONS built on the framework
│   ├── pubspec.yaml          # pub workspace root for the app clients
│   └── zen_demo/             # the reference app (showcase + living e2e test stand)
│       ├── zen_demo_client/  # Flutter client (pub workspace member; deps ../../client/zen_*)
│       ├── zen_demo_server/  # Quarkus reference backend (inherits zen-parent via relativePath)
│       └── zen_demo_admin/   # react-admin panel (assembles @jzen/admin-core)
├── admin/                    # @jzen/admin-core: reusable react-admin scaffold (framework)
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
package `zen.v1` (the same reason Java lives under `zen/…`); `v1` is the API version.

## Backend: why multi-module

A single-module backend cannot express jZen's package boundaries, so the aggregator is
`<packaging>pom</packaging>`, every module is a plain-jar **framework library**, and the
runnable Quarkus app is a *separate* module under `apps/` that assembles them.
`server/pom.xml` (`zen-parent`) is both
the parent (BOM, Java version, plugin/dependency management) and the aggregator that builds
and `install`s the libraries; an app server (e.g. `apps/zen_demo/zen_demo_server`, the only
`quarkus`-packaged module) inherits `zen-parent` across directories via `<relativePath>` and
resolves the libraries from the local repository. See [`DECISIONS.md`](./DECISIONS.md)
ADR-001 for the framework/apps split and its Maven mechanics.

The baseline is **Quarkus 3.32.2 on Java 25**. The Maven wrapper is committed so the build
is reproducible without a system Maven.

| Module | Holds | Notes |
|---|---|---|
| `zen-proto` | generated Java DTOs | Compiles `proto/zen/v1/*.proto`. Leaf module, only `protobuf-java`. Dependency-free so the protobuf plugin never resolves an unbuilt internal jar at generate-sources time. |
| `zen-core` | `ZenResult`/`ZenError`, `ZenStatus`, `AcceptLanguage`, `ZenLocales` | No JAX-RS, no Panache, no Quarkus. That isolation is the module's most valuable property. |
| `zen-transport` | the negotiation seam (below) | Consumes `zen-proto`. Carries a Jandex index so its providers are discovered. |
| `zen-identity` | Supabase JWT, `User` entity, role augmentor, `AuthResource`, `AdminUserResource` | Auth is framework-side, so every app inherits the surface. |
| `zen-email` | `EmailService` over `quarkus-mailer` | The mechanism only; applications own every word. |
| `zen-jobs` | the master tick and persisted job state | Guaranteed scheduled work. See "Scheduled work" below. |

## The dual-mode transport seam

The core mechanism. The design goal: **a developer defines a domain model and nothing
else** — the framework negotiates the wire format.

The negotiation header is **`X-Zen-Transport`**, with two values, `json` and `protobuf`,
parsed case-insensitively. Negotiation order is **header → content-type sniff → default
JSON**, and an unparseable header value falls through rather than failing, so a client that
sends nonsense gets JSON rather than an error.

There is **no request/response envelope**. HTTP status carries the status, the `X-Request-ID`
header carries the request id, and a shared `ZenError` proto (`proto/zen/v1/common.proto`)
carries the error; endpoints return typed proto messages directly. An envelope would be a
second, redundant status channel that has to be kept agreeing with the first.

### Quarkus implementation

1. **`ZenTransportFilter`** — a `@PreMatching ContainerRequestFilter` in `zen-transport`.
   Reads `X-Zen-Transport`, and rewrites `Accept`/`Content-Type` to
   `application/x-protobuf` or `application/json`. Scoped to `api/` paths so it never
   rewrites `Accept` on `/openapi`, `/q/health`, or static assets.
2. Standard JAX-RS content negotiation then dispatches to one of two body writers
   registered for `com.google.protobuf.Message`:
   - **`ProtobufMessageBodyWriter/Reader`** — `message.writeTo(out)` / `parseFrom(in)`.
   - **`ProtoJsonMessageBodyWriter/Reader`** — `JsonFormat` from `protobuf-java-util`.
     This is required: stock Jackson serializes protobuf-generated classes into their
     builder internals. Canonical proto3 JSON is a spec that Dart's `protoc_plugin` and
     `openapi-typescript` also emit, so all three languages agree on the JSON shape.
3. Resources return proto messages; **MapStruct** maps Panache entity ⇄ proto message.
4. The response echoes `X-Zen-Transport`, so a caller can confirm which format it got.

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

Supabase owns authentication. Landed in ROADMAP step 3.

- `SupabaseAuthClient` — a `@RegisterRestClient` interface with `@CircuitBreaker`/
  `@Retry`/`@Timeout` per call, against Supabase Auth (GoTrue) REST: `POST /token` (login
  and refresh, by `grant_type`), `/signup`, `/recover`, `PUT /user`. A Supabase 4xx skips the
  breaker and aborts retries (a real client error is not a transient fault); timeouts and 5xx
  trip it.
- JWT verified against Supabase JWKS with ES256.
- **Role loaded from the `users` table by a `SecurityIdentityAugmentor`, not from the JWT.**
  Roles are application data, so revoking one must not wait for a token to expire.
- The `User` entity is the application profile only (see **Persistence** for the
  cross-cutting columns it carries).

**REST surface.** `AuthResource` lives in `zen-identity` — a reusable **framework** resource, so
every jZen app inherits the auth surface just by depending on the module (see
[`DECISIONS.md`](./DECISIONS.md) ADR-001; this reverses the earlier "auth lives in the app"
decision). zen-identity is a Jandex-indexed library of the auth beans, the `User` entity, the
MapStruct `User` → `Identity` mapper, **and** the `AuthResource`/`AuthExceptionMapper`; Quarkus
discovers the JAX-RS resource from the jar via the Jandex index. The app module still runs SmallRye
OpenAPI and supplies the referenced component schemas through its static `META-INF/openapi.yaml`
(paths from the library, schemas from the app). The endpoints back the client's
`IdentityRepository` contract: `POST /api/v1/auth/{login,register,restore-password,logout,refresh}` and
`GET /api/v1/auth/identity`. Each returns a typed proto (`Response` + `@Schema(ref=...)`);
errors return the shared `ZenError` proto via an exception mapper.

**Session cookies and refresh.** Login/register/refresh set `zen_access_token` (httpOnly,
1 h) and `zen_refresh_token` (httpOnly, 7 d), plus a JS-readable `XSRF-TOKEN`. SmallRye JWT
reads the access cookie directly (`mp.jwt.token.cookie`, `proactive=true`), so an
authenticated request is a plain cookie request; `POST /auth/refresh` exchanges the refresh
cookie via Supabase (`grant_type=refresh_token`) and re-issues the cookies.

**Why each token gets its own cookie.** jZen serves Cloud Run directly, so nothing strips or
renames cookies in transit, and the standard SmallRye-JWT path works as designed: normally-named
cookies, `mp.jwt.token.cookie`, and `proactive=true`, with no session filter and nothing to
unpack. That simplicity is a dependency, not a given — see [`STANDARDS.md`](./STANDARDS.md)
"Deployment model" for what putting a cookie-stripping edge in front would cost.

## Email

`EmailService` (`zen-email`) sits over `quarkus-mailer`. Brevo is used purely as an SMTP
relay, so nothing in the Java is provider-specific and moving providers means changing
`SMTP_HOST`, nothing more. `send(...)` **never throws**: mail is a side effect of a business
action and must never be able to fail it, so a missing template, a render error, or an
unreachable relay returns `false` and logs.

**Localized templates (ROADMAP step 6).** Email is user-facing, so it is localized from
the start — an English-only template is a limitation the framework exists to make impossible.
`EmailService.send(...)` resolves the recipient's locale from the `users.language` column (email
has no request to read `Accept-Language` from), then renders a per-locale Qute template —
`@Localized` template variants (e.g. `templates/mail/welcome_en.html`, `welcome_uk.html`) with
subject lines from a Qute `@MessageBundle` (as built: `MailMessages` + `MailMessagesUk`, owned by
the application — see [`DECISIONS.md`](./DECISIONS.md) ADR-007). `SUPPORTED` locales start at
`{en, uk}` and grow with the message bundles, no code change per template.

## Client localization

Typed and generated, mirroring the server's `@MessageBundle` (ADR-002) — the two stacks make the
same choice, which is the whole point of ROADMAP step 7b. See
[`DECISIONS.md`](./DECISIONS.md) ADR-009.

```
lib/src/l10n/identity_{en,uk}.arb  ──flutter gen-l10n──▶  IdentityLocalizations (+ delegate)
lib/src/l10n/navigation_{en,uk}.arb                    ▶  NavigationLocalizations
lib/src/l10n/demo_{en,uk}.arb                          ▶  DemoLocalizations
```

- **The ARB files are the source and are tracked; the generated classes are not.** `flutter
  gen-l10n` ships inside the Flutter SDK, so unlike the `.pb.dart` messages there is no toolchain
  boundary to carry output across — see STANDARDS "Code generation". `task generate:l10n` produces
  them, `build:client` / `test:client` run it first, and `sync:contracts` fails if any generated
  localization is ever *committed*.
- **Every localized package owns its own strings**, generates its own accessors, and ships a
  delegate; an application composes the delegates in `MaterialApp.localizationsDelegates` and
  supplies **no wording**. A framework screen calls `IdentityLocalizations.of(context)` rather than
  taking a messages argument, so a locale change is one rebuild.
- **`ZenLocales` (in `zen_core`) is the client's single declaration of the supported set**,
  mirroring the server's `zen.core.i18n.ZenLocales`: `{en, uk}`, fallback `en`. Each package tests
  its generated `supportedLocales` against it, so an ARB set cannot drift from what the server can
  answer in.
- **The locale is app state, not config.** A single `Locale` provider is both `MaterialApp.locale`
  (so `Localizations` re-renders the typed strings) and the value `ZenClient` reads per request for
  `Accept-Language` (ADR-007) — so the language a user picks reaches `POST /auth/register`, seeds
  `users.language`, and every later localized email follows from it. This *strengthens* the
  compile-time-config rule rather than bending it: the strings are Dart constants that
  tree-shake, and there is no runtime asset path at all. The locale is app *state*, not config,
  which is exactly why it stays runtime-selectable while config does not.

## Persistence

PostgreSQL via Hibernate Panache, **active-record: entities extend `PanacheEntityBase` and
there are no repository classes.** Flyway migrates at start and is the single migration
authority — `supabase/migrations/` stays empty so there is never a second migration system on
one database. `zen-identity` ships `V1__init_identity.sql` (the `users` table) and
`V2__row_level_security.sql`; each framework library owns a reserved version band
(STANDARDS "Database migrations").
The local database is the Supabase stack on port 54322 (`supabase/config.toml`).

**Reconciling with Supabase `auth.users`.** Supabase owns authentication (`auth.users`);
the jZen `users` table is the application profile, keyed by the same id (the JWT `sub`),
upserted on first login. It carries **no** foreign key to `auth.users`: the `@QuarkusTest`
Dev Services database is plain PostgreSQL with no `auth` schema, and Supabase owns that
table's lifecycle. For the same reason the RLS migration (`auth.uid()` and the `auth` schema
exist only on Supabase) is guarded on `to_regprocedure('auth.uid()')` — it enables RLS and
the owner policy on Supabase, and is a no-op on plain PostgreSQL so tests still migrate.

**Compliance columns are first-class.** The `users` table has zero learning-domain columns,
but it deliberately keeps two cross-cutting product concerns: **payment**
(`is_premium`) and **GDPR / data retention** (`analytics_consent`, `deletion_warning_sent_at`,
`final_warning_sent_at`). The retention columns are written by `UserRetentionService` as of step 6.
`is_premium` is **already load-bearing** - it exempts an account from the retention cycle and is
administered through `AdminUserResource` - but a **payment flow is application work, not framework
work** (see [`DECISIONS.md`](./DECISIONS.md) ADR-010): an application that sells something
implements checkout in its own server, so no step of this roadmap delivers one. The column stays
because the exemption needs it, and keeping it from the start avoided a schema migration.

## Scheduled work

Exists for one constraint: on a scale-to-zero runtime there is no thread alive at the hour a
schedule names. Landed in ROADMAP step 7a; see [`DECISIONS.md`](./DECISIONS.md) ADR-008 for the decisions.

```
Cloud Scheduler ──POST /api/v1/jobs/trigger (X-Zen-Job-Token)──▶ JobTriggerResource
                                                                      │
                        overlap guard ──▶ enabled rows in zen_jobs ───┤
                                                                      ▼
                       due? = last_run_at + interval <= now   ──▶ run sequentially
                                                                      │
                                          record last_run_at / last_status / duration / error
```

- **Due-ness comes from `last_run_at`, not from a timer having fired**, so a tick missed while
  scaled to zero is caught up rather than lost. A job overdue by N intervals runs **once**.
- **Job state is persisted** (`zen_jobs`, Flyway `V100` + Panache), so a schedule change or an
  emergency stop is an `UPDATE`, not a redeploy. A job carries an interval, an enabled flag,
  and its run outcome, and nothing more: retries come from the scheduler's at-least-once
  delivery plus the next tick.
- **One trigger, one container start, N jobs.** N scheduler entries would mean N cold starts,
  which fights the single-instance cost model.
- **An application implements `ZenJob` and registers nothing else.** `zen-identity` does *not*
  depend on `zen-jobs`: it offers `UserRetentionJob.runCycle()` as a plain callable, and the app
  joins the two (`zen.demo.jobs.UserRetentionZenJob`), the same split ADR-007 drew for email.
- **The trigger's credential is a shared-secret header**, not the Supabase session and not Google
  OIDC, and it **fails closed** when unconfigured. The service is served
  `--allow-unauthenticated`, so this endpoint is internet-reachable.
- **GDPR retention is gated on delivery.** The cycle finds due accounts, fires
  `AccountDeletionWarning` synchronously, and stamps the timestamp only when an observer confirms
  the message went out — so no account is anonymised on the strength of a warning that failed to
  send, and `zen-identity` still names nothing in `zen-email`.

## Deployment

Cloud Run, native image, via `task deploy:cloudrun` and `Dockerfile.native-micro`. Runs a
**single instance by design** (`--max-instances=1`, `--min-instances=0`,
`--concurrency=200`): a cost floor, not a scaling ceiling — the native server serves the
target load on one instance, and scale-to-zero means no warm instance to pay for. See
[`STANDARDS.md`](./STANDARDS.md) → "Deployment model" for why one instance also makes
in-process state valid.
