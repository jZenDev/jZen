# jZen Architecture Decisions

A running log of architectural decisions and, crucially, where they **change earlier docs** and
why. Plans are intentions; the product evolves, and every drift from a prior decision is recorded
here with its justification so the reasoning is never lost. Newest first.

Each entry: **what changed**, the **docs it supersedes**, and the **justification**.

---

## ADR-001 — jZen is a framework; libraries (`server/`, `client/`) vs applications (`apps/`)

**Date:** 2026-07-19. **Status:** accepted.

### Decision

jZen is a **framework/platform**, not a single product. The repository is organised on that axis:

- **`server/`** — the Java **framework libraries** (`zen-proto`, `zen-core`, `zen-transport`,
  `zen-identity`, `zen-email`): plain-jar modules under the `zen-parent` reactor.
- **`client/`** — the Dart/Flutter **framework libraries** (`zen_core`, `zen_transport`,
  `zen_identity`, `zen_localization`, `zen_ui_*`): a pub workspace.
- **`apps/`** — full-stack **application examples/products** that assemble the framework, each a
  folder holding its client and server: `apps/<app>/{<app>_client, <app>_server}`. Today
  `apps/zen_demo/{zen_demo_client, zen_demo_server}`; next `apps/workspaces/{client, server}`.
- The **repository root stays language-neutral** — only `Taskfile.yml` orchestrates. No root
  `pom.xml`, no root `pubspec.yaml`. There are two Maven build units (framework libs; app servers)
  and two pub workspaces (framework libs; app clients), wired by the Taskfile.

### What this supersedes, and why

1. **"No `apps/` wrapper; a package is a package whether a library or the demo app"**
   (BLUEPRINT "Repository layout"; memory `jzen-migration-project`) → **reversed.**
   *Why:* the client tier is a 1-lib-set : N-apps relationship — `zen_demo`, `workspaces`, … all
   sharing `zen_core`/`zen_transport`/… That is exactly where separating `apps/` from a shared-lib
   `client/` earns its keep (it does not exist on the single-deployable server side), and it makes
   the layout symmetric with the framework.

2. **"`server/` holds `zen-proto/core/transport/identity/email/app`; `zen-app` is the runnable app
   among the libs"** (BLUEPRINT "Backend: why multi-module"; memory) → **changed.**
   `server/` is framework libraries only; the runnable app moved to `apps/zen_demo/zen_demo_server`
   (artifactId `zen-demo-server`, package `dev.zen.demo`). *Why:* the app is an *assembly* of the
   framework and belongs with the applications; this removes the app-among-libs asymmetry and
   mirrors `client`(libs) ↔ `apps`(apps).
   *Maven mechanics ("no root pom"):* `server/pom.xml` remains `zen-parent` (BOM, Java version,
   plugin/dependency management) **and** aggregates + `install`s the libraries. App server modules
   inherit `zen-parent` across directories via `<relativePath>../../../server/pom.xml</relativePath>`
   and resolve the libraries from the local repository. The shared Maven wrapper is invoked with
   `-f` (`server/mvnw -f apps/…/pom.xml`), so no wrapper is duplicated. Verified: framework
   `install` → app `package` produces the runnable jar and passes all tests.
   *Dart mechanics:* `apps/pubspec.yaml` is a second workspace; its members path-depend into
   `client/` libraries that declare `resolution: workspace`. Verified: pub resolves the
   cross-workspace path-dep and imports compile across the boundary.

3. **"`AuthResource` lives in `zen-app`, not `zen-identity`, because zen-app owns the REST surface"**
   (BLUEPRINT "Authentication"; ROADMAP Step 3; memory) → **reversed.**
   The auth REST surface (`AuthResource`, `AuthExceptionMapper`) moved into `zen-identity`, a
   Jandex-indexed framework library. *Why:* jZen is a framework for *all* new apps; auth must be
   reusable so a new product (`workspaces`) inherits login/register/logout rather than reinventing
   it. Quarkus discovers JAX-RS resources from a Jandex-indexed jar; the app module still runs
   SmallRye OpenAPI and supplies the referenced component schemas via its static `openapi.yaml`
   (paths come from the library resource, schemas from the app). Verified: the auth endpoints are
   served from the library and all auth tests pass.

4. **"`dartzen_demo_server` is deleted; the Quarkus backend (`server/`) is the server now"; "zen_demo
   is the Flutter reference app"** (ROADMAP Step 4; memory) → **reframed.**
   `zen-app` was always the reference backend (an assembly of framework libs); it is *relocated*,
   not deleted, to `apps/zen_demo/zen_demo_server`. `zen_demo` is now a folder holding
   `{zen_demo_client, zen_demo_server}`. *Why:* the reference app demonstrates building a full-stack
   app on jZen (client **and** server), and because both sides assemble the framework it is a
   genuine **framework** end-to-end gate.

5. **"A green `zen_demo` run is *the* product release gate"** (ROADMAP Step 4) → **refined.**
   `task test:e2e` proves the *framework* composes end-to-end via the reference app; each product
   app (`workspaces`) gets its own e2e. *Why:* the framework model.

### Consequence

The framework identity is reflected in MANIFESTO/BLUEPRINT wording, the layout sections, and the
Taskfile's `:apps` task group. Lockstep versioning is unchanged: the `apps/` members
(`zen_demo_client`, `zen-demo-server`, `apps/pubspec.yaml`) share the `0.1.0` product version.

---

## ADR-002 — Server i18n uses Qute `@MessageBundle`, not `.properties`

**Date:** 2026-07-19. **Status:** accepted.

**Decision.** Server-side localized messages are typed Qute `@MessageBundle` interfaces
(`DemoMessages` + a `@Localized("uk")` variant), selected per request. The reusable, framework-free
`Accept-Language` → locale resolution lives in `dev.zen.core.i18n.AcceptLanguage` (a pure function,
reused by any module). Localized *documents* (the terms Markdown) stay as classpath `.md` files -
content, not messages.

**Supersedes** the interim Step-4 choice of a hand-rolled `.properties`-backed `DemoMessages` bean.
*Why:* `@MessageBundle` is the Quarkus-idiomatic, typed, generated mechanism and the direction
ROADMAP step 6 (localized email) already commits to; a third, hand-rolled l10n format was needless,
and locale resolution belongs in a shared framework utility, not a demo-local bean.

---

## ADR-003 — HTTP status codes: an extendable constant interface

**Date:** 2026-07-19. **Status:** accepted.

**Decision.** `@APIResponse(responseCode = …)` values reference `dev.zen.core.http.ZenStatus`, an
**interface** of `public static final String` codes that jZen applications may `extends` to add
their own (e.g. `interface AppStatus extends ZenStatus { String PAYMENT_REQUIRED = "402"; }`).
*Reference or `extends` it; never `implements` it* (Effective Java Item 22, the constant-interface
antipattern).

**Supersedes** raw `"200"`/`"204"` literals in the resources. *Why:* centralization and
extensibility for jZen customers. A wrapper deriving the strings from Jakarta's `Response.Status`
is impossible for annotation use: an annotation value must be a *constant expression* (JLS 15.29),
and `String.valueOf(Status.OK.getStatusCode())` is a method call, not a constant (verified: it
fails "element value must be a constant expression"). A literal is the only annotation-legal form,
so these are documented literals; an *extended constant interface* keeps them compile-time constants
(verified to compile as annotation values).

---

## ADR-004 — Client (Flutter) i18n: keep `zen_localization` now, adopt typed/generated later

**Date:** 2026-07-19. **Status:** deferred (revisit as a framework decision).

**Context.** Server i18n went typed and generated (ADR-002, Qute `@MessageBundle`). The Flutter side
currently uses `zen_localization` — a hand-rolled service over per-locale JSON bundles with **string
keys** looked up at runtime. That is the `easy_localization` camp (stringly-typed), *not* the
idiomatic Flutter approach.

**What "idiomatic Flutter" is.** The Flutter/Google-recommended path is the `intl` package + **ARB**
files (`.arb`) + `flutter gen-l10n`, which *generates a typed `AppLocalizations`* class
(compile-checked keys, no runtime string lookups). The popular type-safe third-party alternative is
**`slang`** (generates typed accessors from JSON/YAML). *Effective Dart*'s ethos — typed over
stringly-typed — points the same way. So the consistent end state is **typed + generated on both
stacks**: `@MessageBundle` (Quarkus) ↔ `intl`/`gen-l10n` or `slang` (Flutter).

**Decision (deferred).** Keep `zen_localization` for now. It is a Step-2 **framework library**, so
changing it is a framework-wide decision larger than the app work that surfaced this, and it is not
on the critical path. **Recorded for a future step:** evaluate migrating `zen_localization` (or the
apps that consume it) to `intl`/`gen-l10n` or `slang` for a type-safe, generated client i18n that
mirrors the server's `@MessageBundle`. Not lost — parked here deliberately.
