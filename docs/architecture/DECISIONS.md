# jZen Architecture Decisions

A running log of architectural decisions and, crucially, where they **change earlier docs** and
why. Plans are intentions; the product evolves, and every drift from a prior decision is recorded
here with its justification so the reasoning is never lost. Newest first.

Each entry: **what changed**, the **docs it supersedes**, and the **justification**.

> **This log is a sealed archive (ADR-011).** An accepted entry is never retroactively edited: it
> is the record of what was decided, on the evidence available then. Later thinking arrives as a
> *new* entry that supersedes it, which is why the supersession chains below are readable at all.
> One consequence is deliberate and worth stating: entries written during the project's first phase
> name the systems jZen was originally derived from, because in several cases those systems *were*
> the evidence. Step 8's verification search excludes this file for exactly that reason.

---

## ADR-046 — The orchestration an application needs is extracted into `Taskfile.app.yml`, and jZen consumes it the same way

**Date:** 2026-08-15. **Status:** accepted.

### Decision

`Taskfile.yml` was written when there was exactly one application, and it shows: `DEMO_SERVER_DIR`,
`DEMO_CLIENT_DIR`, `SERVICE_NAME: zen-demo-server`, paths relative to this repository's root. An
application built on jZen could not reuse any of it. It could copy the shapes, or it could
`includes:` the file and get tasks that build **zen_demo** — reuse in appearance only.

**The application-facing half moves into `jZen/Taskfile.app.yml`**, written against variables
rather than against zen_demo, and included by the consuming repository:

```yaml
includes:
  zen:
    taskfile: ../jZen/Taskfile.app.yml
    vars: {APP_NAME: prudent, CLIENT_DIR: client, SERVER_DIR: server}
```

Three go-task facts make it work, and they were **measured before the file was written**, not
assumed: an included file's tasks run in the *including* repository's directory; `ROOT_DIR` is the
consumer's root while `TASKFILE_DIR` is jZen's, which is how a task operates on the application's
files while reaching back into the framework checkout (`{{.TASKFILE_DIR}}/server/mvnw`); and
`vars:` on the include override the file's defaults.

**One file, not a `taskfiles/` directory.** A folder whose only job is to hold a single member is a
container for something that does not need containing — `ZEN_ARCHITECTURE.md` §5, "fewer files,
fewer indirections". A second reusable taskfile is what earns a folder, and there is not one.

**jZen consumes it exactly as an application does**, through `includes:` in its own `Taskfile.yml`
with `APP_NAME: zen_demo`. This is the load-bearing half of the decision. A reusable file the
framework does not itself use is a file that drifts, and the claim "an application can orchestrate
itself with this" is only true while something does. `generate:l10n` and `build:apps:runners` are
the first two tasks moved; both now exist once, and `Taskfile.yml` keeps their documented names by
delegating.

### Scope, and what deliberately did not move

Moved: `info` (which jZen checkout, at which revision, and whether it is dirty),
`framework:install` (the local-repository prerequisite an application's own Maven build cannot
express), `deps`, `generate:l10n`, `test:client`, `build:runners`.

Not moved: the contract loop, the server build, the local stack, the deploy, and every framework
gate. They are still zen_demo-shaped and are migrations to make one at a time, each proven against
zen_demo first. **Recording that as a known limit rather than a plan**: a task living in both files
can drift, which is an argument for finishing the move, never for keeping two copies.

Anything that names zen_demo stays out, as does anything an application would have to fight rather
than configure — a task needing `if APP_NAME == …` has been put in the wrong file.

### What this supersedes, and why

- **ADR-014 and ADR-032's framing of `Taskfile.yml` as "the single orchestrator"** → **refined:**
  one orchestrator, now in two files, one of which is the reusable half. *Why:* the rule was about
  never running a second build driver beside `task`, and that is untouched — `includes:` is
  go-task composing itself, not a second tool. What changes is that "single" described a *file*
  when it meant a *tool*.
- **STANDARDS "Orchestration", by extension.** The prohibition on a second build driver stands;
  the implication that all orchestration lives in one file does not.

### Consequence

An application can orchestrate itself against jZen without copying anything, and the parts it
reuses are the parts jZen itself runs. `task zen:info` answers the question a path-consumed
framework otherwise leaves unanswerable — *which* jZen is this — by reporting the checkout's
revision and warning when it is dirty, because with no version boundary between the repositories
a commit is the only honest answer.

Two defects were found by running the extracted file rather than by reading it, and both are worth
recording because they are the failure modes this repository legislates against:
`[ -d dir ] && build || true` turns a **failed build into a pass** (the `|| true` cannot tell a
missing directory from a compiler error), and under `set -e` a false `[ -d "$root" ] &&` as a
loop's last statement makes the loop's status 1 and kills the script — a task that fails without
running anything. Both are now `if` statements, with the reason written beside them.

Verified: `task build:apps:runners` through the delegation is byte-for-byte the same outcome as
before it (macOS, iOS simulator and Android built; Linux and Windows skipped audibly), a scratch
consumer outside this repository resolves `zen:info`, `zen:generate:l10n` and `zen:test:client`
against its own root, and `task generate:l10n` still finds all four localized packages.

Lockstep versioning is unchanged at `0.1.0`. No module, no dependency, no Flyway band.

---

## ADR-045 — Linux and Windows are delivery targets; their gate is a real build on a real host, in CI

**Date:** 2026-08-15. **Status:** accepted.

### Decision

jZen claims to be a framework for new applications (ADR-001). A framework that cannot deliver a
desktop app on two of the three desktop operating systems is not complete, so **Linux and Windows
join macOS, iOS, Android and web as first-class delivery targets of the client tier.**

Most of the framework already handled them and nothing knew it:

- `zen_core` has declared `zenIsLinux`, `zenIsWindows` and `zenIsDesktop = macOS ‖ linux ‖ windows`
  all along, and `zen_ui_navigation` branches on `zenIsDesktop` — the desktop navigation was never
  macOS-specific.
- The transport codec seam splits **native vs web**, not per-OS, so `test:client:matrix` needs no
  new rows: Linux and Windows are already covered wherever macOS is.
- CI runs on `ubuntu-latest`, and `test:client` compiles every Flutter widget test with
  `ZEN_PLATFORM=linux`. The Linux *code path* has been compiled and tested on every commit for
  as long as CI has existed.

What was missing was the only thing that actually proves a delivery target: **a build of the real
runner.** The reference app had `android ios macos web` and no `linux/` or `windows/` directory, so
neither had ever been built. That is now closed:

1. **`zen_demo_client` gains `linux/` and `windows/` runner directories.** The reference app is the
   framework's evidence; a target it cannot build is a target jZen does not have.
2. **`build:apps:runners` builds every runner the host can, and says so when it cannot.** It gains
   a Linux branch and a Windows branch beside the existing Apple and Android ones, host-detected
   (`uname -s`, with `MINGW*`/`MSYS*`/`CYGWIN*` recognised as Windows), and skips **loudly** — the
   rule ADR-012 set for the Apple targets, applied to two more.
3. **CI is where the desktop gate lives, because it cannot live anywhere else** (see below). The
   existing Linux job additionally builds the Linux desktop runner, and a new `windows-latest` job
   builds the Windows one.
4. **`run:demo:native` and `test:client` learn the two platforms** — the former's allowlist was
   `macos|ios|android`, the latter mapped every non-Darwin host to `linux`.

### The verification boundary, stated precisely

Flutter does **not** cross-compile desktop targets, and this is measured, not assumed — on the
delivery machine (`arm64` macOS), against a throwaway project:

```
flutter build windows  →  "build windows" only supported on Windows hosts.
flutter build linux    →  "build linux" only supported on Linux hosts.
```

So the three tiers of verification are different things, and conflating them is how a framework
claims a platform it has never shipped:

- **Logic** — verified everywhere, including the delivery machine. The per-OS branching is
  compile-time constants (`zenIsLinux`, `zenIsWindows`) and the only conditional imports are
  `dart:io` vs `dart:html`, not per-OS, so widget tests compile and pass under any `ZEN_PLATFORM`
  on any host. This proves the code path, **not the app**.
- **The runner build** — only on a matching host, therefore only in CI. This is the gate.
- **Running the built app** — possible for Linux in CI under `Xvfb`, and deliberately **not done
  yet**; a named next step rather than a silent gap. The full-stack `test:e2e` (Supabase + Quarkus
  + the app, no mocks) stays **Linux-only**: the Windows runner cannot practically host the Linux
  containers Supabase needs, so a Windows end-to-end would be a different, weaker test wearing the
  same name.

**This forces a documented exception to a rule jZen has held since ADR-012**: "every command shown
was run on the delivery machine". For Windows that is now structurally impossible — no macOS
machine can run it. The Windows claim is therefore phrased as **"verified on `windows-latest` in
CI"** wherever it appears, and the difference is stated rather than blurred. A README that claimed
otherwise would be a claim nobody could reproduce.

### Cost, taken deliberately

CI goes from one operating system to two. That is the full-fanout wall-time pressure STANDARDS §25
and ADR-026 name as a second-application trigger, arriving early and for a different reason. It is
accepted because the alternative is a framework whose platform list is aspirational. **macOS and
iOS remain outside CI** on the existing cost reasoning (a `macos-latest` runner bills at several
times the Linux rate, and `build:apps:runners` covers them on a developer's machine) — so the
matrix is `ubuntu-latest` + `windows-latest`, not three.

### What this supersedes, and why

- **ROADMAP and the client READMEs' implied platform set (Apple, Android, web)** → **widened to
  include Linux and Windows.** *Why:* the constants and the desktop navigation branch already
  existed, so the documents understated what the framework contained while overstating what it had
  proven. Both halves are now true.
- **ADR-012's "every command shown was run on the delivery machine"** → **narrowed**, with Windows
  named as the exception and CI named as its evidence. *Why:* a rule that cannot hold must say so;
  silently breaking it is how documentation stops being trustworthy.
- **The CI comment "the macOS and iOS runners … a cost decision, not an oversight"** → **kept, and
  extended** to say why Windows was worth the cost when Apple was not: Apple targets are verifiable
  on the delivery machine, and Windows is verifiable nowhere else.

### Consequence

Every delivery target the reference app declares is now built by something on every commit, except
the two Apple ones, which are built locally and announced when skipped. `zenIsWindows` is compiled
for the first time. An application choosing Linux or Windows is choosing a supported platform
rather than breaking new ground — which is what ADR-001's claim requires, and what the second
application asked for.

Lockstep versioning is unchanged at `0.1.0`. No Flyway band is claimed, no module was added, and
no dependency was added: the runner directories are Flutter scaffolding, and the rest is
orchestration.

---

## ADR-044 — The supported locale set belongs to the application; jZen declares only what it ships

**Date:** 2026-08-15. **Status:** accepted.

### Decision

`ZenLocales` conflated two sets under one name, and the second application broke on it immediately.
The two are separated, and the framework's half becomes a **floor, not a ceiling**.

- **A — the locales jZen's own packages ship strings for.** Legitimately the framework's, and an
  honest thing to declare. Today `{en, uk}`.
- **B — the locales the product supports.** Always an application decision.

`ZenLocales` declared **A** and every consumer used it as **B**. The framework did not merely omit a
locale it had no strings for; it **erased** one, in three places: `resolve()` clamped any unknown
tag to `en` and `UserStore` ran every registration's `Accept-Language` through it, so a Polish
user's `users.language` was written `en`; each generated delegate answered
`isSupported(locale) => ['en','uk'].contains(...)`, so under `Locale('pl')`
`IdentityLocalizations.of(context)` was null and a framework screen **crashed** rather than
degrading; and each localized package asserted its generated `supportedLocales` equalled
`ZenLocales.supported`, so the framework's own suite failed on the application's decision.

Five coupled changes, and **no locale is added to jZen**:

1. **`supported` → `shipped`, on both stacks.** `ZenLocales.shipped` / `ZenLocales.SHIPPED` is "the
   locales jZen's own packages ship strings for", still `{en, uk}`, still hand-mirrored across the
   two declarations. The rename is the load-bearing part: the old name is what invited every
   consumer to read an inventory as a policy. (`default` was considered and is impossible — a
   reserved word in both languages.)
2. **The supported set is supplied by the application, per tier, the way that tier already does
   config.** Server: the runtime MicroProfile property `zen.i18n.supported`, defaulting to the
   shipped set, injected where resolution happens (`UserStore`, `EmailService`). Client: a
   compile-time `const` list the app hands to the delegates it composes. This is not a new
   concept — it is the existing runtime-server / compile-time-client split (BLUEPRINT "The
   compile-time config rule") applied to one more value.
3. **Resolution takes the set as an argument.** `resolve(tag, against:)` /
   `resolve(tag, supported)` and `fromAcceptLanguage(header, supported)`; the single-argument forms
   remain, delegating to `shipped`, so a caller that genuinely means "the framework's own set"
   still reads that way. `users.language` can now hold a tag jZen ships no strings for.
4. **Framework delegates degrade instead of refusing.** Each localized package exports a delegate
   whose `isSupported` is unconditional and whose `load` resolves exact → primary subtag →
   `fallback`. An application supporting a locale jZen has no strings for now gets **framework
   chrome in English and its own content in Polish**, rather than a null-assertion crash. The
   pure resolution stays in `zen_core`; the Flutter glue is four lines per package, which is why
   this needs no new package and no shared base class.
5. **An application may translate framework strings without the framework shipping that locale.**
   The generated `XLocalizations` classes are `abstract` and exported, so an app subclasses one and
   composes its own delegate **before** jZen's — Flutter's `Localizations` takes the first delegate
   per type that supports the locale. The override is deleted the day jZen ships that locale. This
   is a documented seam, not a fork.

**Rejected: `MyLocales extends ZenLocales`.** It reads well and cannot work. `ZenLocales` is a
static holder (`abstract final class` in Dart, a private-constructor `final class` in Java); Dart
does not inherit static members at all, and Java *hides* rather than overrides them — so
`PrudentLocales.SUPPORTED = {en,uk,pl}` would compile while every framework call site kept reading
`{en, uk}`. A silent, compiling, wrong result is the failure mode this codebase reserves its
loudest rules for. It is also the ceremony `ZEN_ARCHITECTURE.md` §5 rejects: the app supplies a
value, it does not extend a base class.

### What this supersedes, and why

- **BLUEPRINT "Client localization": "`ZenLocales` (in `zen_core`) is the client's single
  declaration of the supported set … Each package tests its generated `supportedLocales` against
  it, so an ARB set cannot drift from what the server can answer in"** → **split.** *Why:* the
  drift check is worth keeping and is retained against `shipped`; the claim that one declaration is
  *the* supported set is what an application cannot live with. The set a package ships and the set
  a product supports are different facts.
- **ADR-009's "Adding a locale to jZen … needs no code edit on either [stack]: … then the tag in
  `ZenLocales` on each side"** → **refined.** *Why:* it described adding a locale **to the
  framework**, which is still exactly right. It was silently read as the only way an application
  could gain one, which is what this entry corrects.
- **ADR-008 pt.3's "`ZenLocales` (in `zen-core`) is the single declaration of the supported set"**
  → **reframed** to the single declaration of the *shipped* set, with the supported set config-
  supplied. *Why:* same conflation, server side. The `users.language` clamp it produced was a data
  defect, not a styling one.
- **`client/README.md` and `client/zen_core/README.md`, "the single declaration of the locales jZen
  supports (`{en, uk}`)"** → **corrected** to what jZen *ships*.

**Not superseded, and worth stating:** ADR-007 (the locale is ambient, sent as `Accept-Language`
per request), ADR-009's typed-generated-accessors decision, and the tracked-vs-generated rule are
all unchanged. So is ADR-010's bar — this entry adds no capability on speculation. It removes a
coupling that the first real second consumer broke on, which is the evidence ADR-010 asks for.

### Consequence

An application declares its own languages and jZen stops ratifying them. jZen ships `{en, uk}` and
says so; an app shipping `{en, uk, pl}` needs no framework change, no fork, and no locale added
upstream. A locale the framework has no strings for degrades per delegate instead of crashing, and
the ARB-drift gate that motivated the original assertion survives intact against `shipped`.

The trigger for jZen to *ship* a new locale is unchanged and unmet: ARB files in every localized
package plus a `@Localized` bundle variant and templates server-side. An application wanting one
language is not that trigger — it is what item 5 exists for.

Lockstep versioning is unchanged at `0.1.0`. No Flyway band is claimed (200-299 remains free), no
module was added, and no dependency was added on either stack.

**Verified on the delivery machine.** `task test:client` green — **321** tests (`zen_core` 89,
`zen_identity` 54, `zen_secure_store` 8, `zen_transport` 68, `zen_ui_identity` 58, navigation
example 2, `zen_ui_navigation` 42); `task test:apps:client` **11**; `task test:apps:server` **158,
0 failures**. `task verify:boundaries`, `task verify:docs` (18 LICENSE copies byte-identical) and
`task sync:contracts` ("Contracts in sync.", "Generated localizations correctly untracked.") are
green.

The new proof is behavioural on both stacks, because every failure this entry fixes was silent:

- `ApplicationLocaleSetTest` (`@QuarkusTest`, `zen.i18n.supported=en,uk,pl` via `@TestProfile`)
  registers a user with `Accept-Language: pl-PL` and asserts `users.language` **reads `pl` out of
  the database** — the clamp wrote `en` there, and that column is email's only locale source. Its
  second case registers `de` and asserts `en`: the set is wider, not open.
- `identity_localizations_test.dart` pumps a real `LoginScreen` at `Locale('pl')` under an app set
  of `{en, uk, pl}` and asserts it renders English rather than throwing, then pumps the same tree
  with an app-supplied Polish delegate and asserts the app's wording wins.
- `navigation_localizations_test.dart` asserts the same degradation for its own delegate, and both
  packages pin that the *generated* delegate still refuses `pl` — the difference between the two
  is the entire mechanism.
- `zen_locales_test.dart` adds the `against:` case: `pl` survives an application set and still
  falls back under the framework's own.

**Checked against the artefact production actually ships, not only the JVM.**
`task build:server:native` is green (6m03s, a 145 MB `linux/amd64` binary), and that binary was
run in an `amd64` container against a throwaway Postgres: the migrate job applied its 9 migrations
and the service started in **1.010s under `%prod` with `ZEN_I18N_SUPPORTED=en,uk,pl` set and no
configuration complaint**. This mattered because the injected value is an `Optional<List<String>>`
and native images resolve config differently from a JVM - it is read from an instance field at
runtime, so nothing about it is folded into the image, while `ZenLocales.SHIPPED` is a genuine
constant and correctly is.

**One correction found by testing rather than by reading.** The seam works only if the
application's delegate is composed **first** and returns a `SynchronousFuture`. An override placed
after jZen's loses (`Localizations` takes the first delegate per type that supports the locale),
and an `async` load leaves the type unresolved for a frame, during which the framework's delegate
answers in its place. Both are now stated where an implementor will read them — the delegate
doc comments, the `zen_ui_identity` library docs, and the test that would otherwise pass for the
wrong reason.

**One asymmetry the native image forces, and it is not obvious.** `zen.i18n.supported` is
*runtime* config, so an operator can widen the set on a deployed service — but the native image
bakes JDK locale data at **build** time, and Quarkus defaults to `-H:IncludeLocales=en-US`.
Anything resolving through `java.util.Locale` (date, number and currency formatting) therefore
formats as `en-US` in a native binary no matter what the runtime set says. jZen's own i18n is
unaffected because it is string-keyed throughout — Qute picks a template by filename and
`@Localized` picks a bundle by tag — but an application that formats money or dates server-side
must also set the build-time `quarkus.locales`. Two properties, deliberately: the languages a
product *answers in* are an operational choice, while the locale data compiled into a binary is a
build artefact, and pretending otherwise would produce a service that accepts `pl` at runtime and
silently formats it as English. The Cloud Run deploy passes `ZEN_I18N_SUPPORTED` through
(`--set-env-vars` replaces the whole environment, so a variable not passed is a variable removed),
and treats a blank value as unconfigured rather than as an empty set — `BlankLocaleSetTest` pins
that, because a blank variable is what an unset export actually produces at deploy time.

Two smaller things landed with it: the Java `resolve` now splits on `[-_]` like its Dart mirror
(it split on `-` only, so `uk_UA` resolved to the fallback on one stack and to `uk` on the other),
and the per-locale generated classes (`IdentityLocalizationsEn` and friends) are now exported,
without which "subclass the fallback and override a few getters" was not actually reachable from
outside the package.

---

## ADR-043 — The shipped image gets an SBOM and a keyless signature; the build itself stays where it is

**Date:** 2026-08-14. **Status:** accepted. **Closes:** `docs/plans/SECURITY-ARCHITECTURE-REVIEW.md`
F6.

### Decision

- **Record what shipped.** `cyclonedx-maven-plugin` is added to
  `apps/zen_demo/zen_demo_server/pom.xml` — the one `<packaging>quarkus</packaging>` module — bound
  to the `package` phase, writing a CycloneDX SBOM to `target/bom.json` on every `mvn package`,
  including the native build `deploy:cloudrun` runs. Measured: 253 components, generated in
  roughly a second — negligible against the ~5m35s native build it rides along with.
  `skipNotDeployed=false` is set explicitly: the plugin's default skips any module with
  `maven.deploy.skip=true`, which `quarkus-maven-plugin` sets for every app module (none of them
  are ever `mvn deploy`ed to a Maven repository — they ship as container images instead), and that
  default would have silently produced no SBOM for the only module that needs one.
- **Sign the image, keyless.** `Taskfile.yml`'s `deploy:cloudrun`, immediately after `docker push`
  and before the migration job starts, runs `cosign sign` on the pushed image and `cosign attest
  --type cyclonedx` on `target/bom.json` — both **keyless** (Sigstore Fulcio + Rekor), not a stored
  key pair. No private key is generated, stored in Secret Manager, or rotated.
- **Verify before trusting.** `cosign verify` and `cosign verify-attestation` must both succeed
  against `COSIGN_CERT_IDENTITY`/`COSIGN_CERT_OIDC_ISSUER` before the migration job or `gcloud run
  deploy` runs — fail-closed, the same shape `MigrateOnlyRunner`'s schema gate (ADR-041) already
  uses. `COSIGN_CERT_IDENTITY` has no default; `deploy:cloudrun` refuses to run without it, the
  same shape `RUNTIME_SERVICE_ACCOUNT` (F1) already established — an empty identity would make the
  gate accept a signature from anyone, which is not a gate. `COSIGN_CERT_OIDC_ISSUER` defaults to
  `https://accounts.google.com`. `cosign` is added to `task doctor` as presence-only, the same
  category as `docker`/`gcloud` — a deploy-time client, not a pinned build input.
- **Keyless over a stored key pair, and why.** The review asked for a deliberate choice, not a
  default. Keyless wins on this repository's actual shape for three reasons: (1) there is no CI
  deploy credential at all (F6's own finding — deploy is manual, by a person), so there is no
  automation identity a stored key would need to represent; a human is already the one authorizing
  every deploy, and keyless just makes that identity verifiable instead of implicit. (2) The trust
  anchor becomes a real OIDC identity, checkable against Sigstore's public Rekor transparency log,
  rather than "whoever holds this key file" — stronger, not weaker, for a single maintainer. (3) It
  adds no new Secret Manager entry and no private-key rotation story. The cost is real and is taken
  knowingly: a live dependency on Fulcio/Rekor availability at deploy time, and an interactive
  browser OIDC login partway through `task deploy:cloudrun`. That was judged acceptable because the
  same command already depends on an interactive `gcloud auth login` — this adds one more login to
  a flow that already has one, not a new category of friction.
- **Not done, deliberately.** The native build stays local. `.github/workflows/ci.yml`'s own
  "Deliberately NOT here" reasoning (CI verifies; it never ships) is not reopened by this entry —
  the review was explicit that this finding is about the artifact that ships, not about moving the
  build, and this decision agrees.

### What this supersedes, and why

- **Nothing in an earlier doc is reversed.** F6 found no SBOM, no signature, no attestation
  anywhere in the pipeline — SLSA level 0, stated as a finding rather than a prior decision. This
  entry is the first decision recording the resulting posture, not a change to one.

### Consequence

**State plainly what is now verifiable and what still isn't — no SLSA level number is claimed.**
Verifiable: the image that ships carries a CycloneDX SBOM and a signature, both bound to a specific
human OIDC identity and anchored in Rekor's public transparency log, and `deploy:cloudrun` will not
proceed to migrate or deploy an image that fails that check. Not verifiable, and not claimed to be:
the build itself is neither hermetic nor reproducible — it still runs on a developer's workstation
(`task build:server:native`), and CI still never touches the artifact that ships, exactly as
`ci.yml`'s own comment already argues it should not.

**Verified this pass, and how.** `task doctor` (cosign added, green), `task sync:contracts`
(in sync), and `task test` (155 backend tests green; `test:e2e` did **not run** — ports
54321/54322 were held by another product on this machine, the same constraint prior passes
recorded, not a result of this change) all ran clean. The `cosign sign` / `cosign attest` /
`cosign verify` / `cosign verify-attestation` mechanics were verified functionally against a
disposable local scratch registry (`localhost:5500`, torn down after), using a throwaway
`cosign generate-key-pair` key pair as a stand-in for the interactive keyless flow: all four
commands succeeded, `verify-attestation`'s payload round-tripped the actual `bom.json` content
through the in-toto envelope, and `cosign verify` was separately confirmed to fail closed
(non-zero exit) against an unsigned image. **The real keyless OIDC round trip was not exercised
end to end in this pass** — completing Sigstore's login requires a browser this environment does
not have; it will run for the first time on the next actual `task deploy:cloudrun`, with the
operator's own go-ahead.

---

## ADR-042 — Framework wiring gets proof, not just logic: a conformance test-jar, decided now, built when app #2 starts

**Date:** 2026-08-14. **Status:** accepted (shape only — no module built yet). **Closes:**
`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md` F8.

### Decision

- **Shape: a conformance test-jar**, not a static `verify:assembly` gate. When it is built, the
  six `*WiringTest` classes that exist today only in `apps/zen_demo/zen_demo_server`
  (`SecurityHeadersWiringTest`, `CsrfWiringTest`, `RateLimitWiringTest`,
  `CorsCredentialsGuardWiringTest`, `MigrateOnlyWiringTest`, `StaticCacheHeadersWiringTest` — one
  more than the review counted) move into a new module, `zen-conformance`, or ship as
  `zen-transport`'s Maven `test-jar` classifier. An application declares it in test scope and the
  tests run against that application's own assembled container.
- **Why a test-jar and not a static gate.** The two candidates check different things. A
  `verify:assembly` script can only inspect a built artifact's Jandex index and bean list —
  static presence. The existing `*WiringTest` classes already do something strictly stronger:
  each is `@QuarkusTest` code that asks a **live CDI container**,
  `beanManager.resolve(beanManager.getBeans(SomeClass.class))`, whether the bean actually
  activated — which also catches a bean that is discoverable but fails to wire correctly for some
  other reason a static index can't see. Every one of the six already follows the same
  mechanical shape (confirmed by reading `SecurityHeadersWiringTest`: inject `BeanManager`,
  assert one class resolves), which is what makes relocating them cheap rather than requiring a
  new mechanism to be invented.
- **What a second application has to do to use it:** declare the test-jar in test scope. Nothing
  else — the assertions ship with the jar and run against whatever container the app assembles.
- **Overlap with F9's `verify:modules` gate (ADR-039's sibling, already shipped): none that makes
  either redundant.** `verify:modules` is static — a `pom.xml` either runs `jandex-maven-plugin`
  or it doesn't. This test-jar is dynamic — the bean is actually resolvable in *this* assembled
  container. A module can pass the static gate and still fail a wiring test if some other
  assembly step (an exclusion, a dependency-version mismatch) breaks discovery a Jandex-presence
  check cannot see. Both stay.

### What this supersedes, and why

- **Nothing in an earlier doc is reversed.** F8 named the gap; this decides how it will be closed
  without closing it yet. Extends ADR-001's framework/application split: proof of wiring is
  something the framework now owns delivering, the same way it owns delivering the code.

### Consequence

**No module exists yet, deliberately.** The review argued, and this entry agrees, that the
payback arrives when a second application starts (ADR-026) — building `zen-conformance` today
would be six test classes maintained against a single consumer that already has them. What
changes today is that the shape is **decided**: when app #2 begins, this is "relocate six
classes into the already-agreed module" rather than "have the test-jar-vs-gate conversation
again." `apps/zen_demo/zen_demo_server` keeps its six `*WiringTest` classes exactly as they are
until that migration happens.

---

## ADR-041 — The Data API lockdown's outcome is asserted at deploy time, not re-derived from its cause

**Date:** 2026-08-14. **Status:** accepted. **Refines:** ADR-036, ADR-038. **Closes:**
`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md` F10.

### Decision

- **`MigrateOnlyRunner`** (`server/zen-identity`) now runs a Data API exposure check
  immediately after a successful migration, on the same DDL-credentialed connection the
  migration itself used — not a second connection, and not once per boot (ADR-038's whole point
  is that nothing runs per boot in `%prod`). Guarded on the `anon` role existing, the identical
  guard `R__identity_data_api_lockdown.sql` already uses, so it is a no-op against the plain
  Postgres `@QuarkusTest`/Dev Services provisions.
- **What it checks:** every object in `information_schema.role_table_grants` for `table_schema =
  'public'` and `grantee IN ('anon', 'authenticated')` (objects that already exist and are
  exposed today), plus every `pg_default_acl` row in the `public` namespace whose ACL text names
  either role (a role other than the one the lockdown last captured is still handing out future
  grants). Either is a refusal.
- **New exit code, `EXIT_DATA_API_EXPOSED = 3`,** alongside the existing `0`/`1`/`2`. There is no
  override for it (unlike `zen.allow-schema-rollback` for exit `2`) — an exposed grant has no
  legitimate "proceed anyway" case the way a deliberate rollback does. `deploy:cloudrun`'s
  failure message and `verify:deploy:smoke`'s native-image integration test were both updated to
  know about it; the smoke test creates a throwaway `anon` role and a live grant specifically to
  prove the gate actually fires, not merely that its no-op guard compiles.

### What this supersedes, and why

- **"[the lockdown] holds for tables not yet written"** (`R__identity_data_api_lockdown.sql`'s
  own header, and ADR-036's reasoning) → **refined, not reversed.** *Why:* the security
  architecture review of 2026-08-13 (F10) found the future-table protection binds to
  `ddl_role := current_user`, captured once, at the moment the repeatable migration last ran. A
  repeatable only re-runs on checksum change; rotating the DDL role — which
  `application.properties` already contemplates as an operator action — does not touch that
  checksum. So the SQL file's own guarantee about future tables can silently stop applying to
  whoever is creating tables now, and nothing was checking that it still held. The SQL file is
  unchanged and still correct for the role it captured; this entry adds a second, independent
  check of the *outcome* rather than trusting the *mechanism* to still be aimed at the right
  role.
- **Two options were on the table** (widen `ALTER DEFAULT PRIVILEGES` to every table-owning role,
  vs. assert the outcome in `MigrateOnlyRunner`) and the outcome-assertion was chosen because it
  is strictly stronger: it also catches the file's own documented gap — a table created via the
  Supabase dashboard's table editor, which runs as `supabase_admin` and which no default-privilege
  widening naming Flyway-created-table owners would ever reach.

### Consequence

Verified functionally against a throwaway Postgres (not the hosted Supabase project — ports
54321/54322 were held by another product on this machine for the whole of this pass, same
constraint the original review recorded): a clean database migrates and exits `0`; manufacturing
an `anon` role plus a live `GRANT SELECT ... TO anon` on a scratch table makes the same image
exit `3` and name the exposed table in its log; revoking the grant returns it to exit `0`. This
is deliberately closer to the real failure mode than the SQL file's own guard, which only proves
"no anon role" rather than "no exposure" — see §8 Q2 of the review for the `psql` query that
would additionally verify this against the hosted project once the ports are free, which remains
unverified by this entry.

`R__identity_data_api_lockdown.sql` is untouched. Widening its `ALTER DEFAULT PRIVILEGES` to
every table-owning role (the review's Option 1) was not taken — the outcome assertion in
`MigrateOnlyRunner` makes it unnecessary as a *detection* mechanism, though it would still
narrow the window between a role rotation and the next deploy catching it, and is left as a
cheap follow-up if wanted rather than bundled into this scope.

---

## ADR-040 — The undocumented `msgpack` alias is removed from `X-Zen-Transport`

**Date:** 2026-08-13. **Status:** accepted. **Amends:** ADR-011. **Closes:**
`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md` F15.

### Decision

- **`ZenTransportFormat.parseOrNull`** (`server/zen-transport`) no longer accepts `"msgpack"` as an
  alias for the binary format. The header now parses exactly `json` and `protobuf` — the two values
  every tracked document already claimed it supported — and any other value, `msgpack` included,
  falls through to `negotiate()`'s existing behaviour: a content-type sniff, then default JSON. No
  request is ever rejected by an unrecognised header value; that property is unchanged.
- **Deleted, not documented.** `client/zen_transport`'s Dart `ZenTransportFormat` never emitted
  `msgpack` — confirmed by grep across `client/` and `apps/` before deletion — so nothing in the
  product depended on the alias resolving to protobuf. Documenting a third wire value nobody sends
  would have cost more than it returned.
- **`CLAUDE.md` and `BLUEPRINT.md`** are also corrected in the same change: both stated that
  `ZenTransportFilter` "rewrites `Accept`/`Content-Type`". It rewrites only `Accept`
  (`ZenTransportFilter.java:44`) — the **request** body's parser is selected independently, by the
  client's own `Content-Type` via `@Consumes`, not by `X-Zen-Transport`. The behaviour was always
  safe (the two selections are independent, so the header could never steer a body into the wrong
  parser), but the documents described the framework's core mechanism incorrectly.

### What this supersedes, and why

- **"One item is deliberately left alone. … Removing the alias is a small behavioural decision for
  a later step."** (ADR-011, discussing `ZenTransportFormat.parseOrNull`) → **fulfilled.** *Why:*
  the security architecture review of 2026-08-13 (F15) is that later step — it re-confirmed no test
  asserted the alias and no client emitted it, which is exactly the precondition ADR-011 named for
  removing it without a compatibility concern.
- **"`ZenTransportFilter` … rewrites `Accept`/`Content-Type`"** (`CLAUDE.md` "The dual-mode transport
  seam", `BLUEPRINT.md` "Quarkus implementation" step 1) → **corrected.** *Why:* verified on the wire
  and in source — a protobuf body sent with `X-Zen-Transport: json` is still parsed by the protobuf
  reader, because request parsing never consulted the header to begin with.

### Consequence

**This is a public wire-contract change**, stated plainly: a caller that was (undocumentedly)
relying on `X-Zen-Transport: msgpack` resolving to protobuf now gets JSON instead — matching the
two-value contract the documentation always described, never a rejected request. `task test` and
`task sync:contracts` are green with no other change required, since neither language's test suite
asserted the alias. `CLAUDE.md` and `BLUEPRINT.md` now describe the seam's actual behaviour;
`task verify:docs` passes.

---

## ADR-039 — `task audit` is wired into CI on a schedule; it had never actually run there

**Date:** 2026-08-13. **Status:** accepted. **Amends:** ADR-034. **Closes:**
`docs/plans/SECURITY-ARCHITECTURE-REVIEW.md` F5.

### Decision

- **A new, separate workflow file, `.github/workflows/audit.yml`,** runs `task audit` on a weekly
  `schedule:` (`cron: "17 6 * * 1"`) and on `workflow_dispatch:`, with `permissions: contents:
  read`. Not a job inside `ci.yml`: a third-party advisory published overnight must not block an
  unrelated pull request the way a red `ci.yml` run would, which is the same reasoning ADR-034
  already gives for keeping `task audit` out of `task test` — it asks a remote service a question
  whose answer changes when nothing in the repository changed.
- **`.github/dependabot.yml`** now covers the `github-actions` ecosystem (weekly). Not the Java or
  TypeScript ecosystems `task audit` already checks — that would be two tools answering the same
  question on two different schedules — but the third-party Actions `ci.yml` invokes, which nothing
  previously watched, and which is what would keep F12's SHA pins current if that finding is worked.
- **The one live advisory closed.** `task audit:admin` was failing on a moderate DOMPurify XSS
  (GHSA-55q2-fjhq-7xh7), transitive through `react-admin > ra-ui-materialui > dompurify` in the
  admin panel — the highest-privilege surface in the system. `ra-ui-materialui`'s own dependency
  range on `dompurify` (`^3.2.4`) already permitted the patched `3.4.13`; the lockfiles
  (`admin/pnpm-lock.yaml`, `apps/zen_demo/zen_demo_admin/pnpm-lock.yaml`) were simply pinned to a
  stale resolution. No `react-admin` version bump was needed — `pnpm update dompurify` in each
  package sufficed.

### What this supersedes, and why

- **"[`task audit`] belongs in CI on a schedule and before a release"** (ADR-034, Decision) →
  **fulfilled, not reversed.** *Why:* the security architecture review of 2026-08-13 found
  `.github/workflows/ci.yml` had no `schedule:` trigger and never invoked `task audit` at all —
  `grep -n 'audit' .github/workflows/ci.yml` matched nothing. The gate ADR-034 built was correct
  and, on the one occasion it had been run by hand, had already caught a real advisory; nothing
  had ever made it run on its own. ADR-034's reasoning stands unchanged — only the wiring it
  asserted, and did not yet have, now exists.
- **"before a release"** is *not* closed by this entry. No release checklist exists in this
  repository yet for `task audit` to be wired into; that half of ADR-034's sentence remains
  aspirational until one does.

### Consequence

`task audit` is green (`task audit:server`: 259 Java dependencies, clean; `task audit:admin`:
clean on the finding this entry closes). The gate now fires on its own weekly and on demand,
rather than only when a human remembers to type the command — which is the defect the review
named: not that the gate could lie, but that nothing made it run.

---

## ADR-038 — Migration runs at the deploy, and the binary-and-schema agreement check is abandoned at boot rather than moved

**Date:** 2026-08-10. **Status:** accepted. **Supersedes:** STANDARDS "Deployment model" and
"Database migrations" in respect of *when* Flyway runs, and STANDARDS "Deployment model"'s boot
figures (ADR-027's 2.9–4.8 s / 3.0 s boot), which the performance audit re-measured.
**Refines:** ADR-031, whose separate Flyway connection now leaves the boot path entirely as a side
effect. ADR-008's version-band reasoning and ADR-033's timestamp versions are untouched: this entry
changes *when* migrations are applied, not what they are or how they are named.

### Context, and the measurement the decision was taken on

`quarkus.flyway.migrate-at-start=true` was unprofiled, so every cold start migrated and validated.
Production is `--min-instances=0`, so the container is replaced around two dozen times a day, and
each of those boots paid the full cost to conclude there was nothing to do. Measured in the
performance audit (2026-08-08, 173 cold starts out of seven days of logs; the `Database:` →
`Schema "public" is up to date` window was **1.423 s** median over 44 boots of one revision and
**1.434 s** over 36 of another — flat to within 25 ms, i.e. a fixed charge):

| Configuration | DB round trips at boot | Connections | Saving |
|---|---|---|---|
| As shipped: migrate + validate at start | 53 | 4 | — |
| `migrate-at-start=false`, `validate-at-start=true` | 41 | 4 | ~420 ms |
| **`migrate-at-start=false`, `validate-at-start=false`** | **12** | **2** | **~2,100 ms** |

**Validation is ~80% of that cost, and validation is the guarantee.** So the decision the owner took
on 2026-08-08, with this split in front of them, is not "move migration": relocating migration alone
buys ~420 ms and needs all of the deploy machinery anyway. It is to take the full ~2,100 ms, which
means **giving up the boot-time check that a running binary and its schema agree**. Recording it as
a relocation would misdescribe it.

**What it is worth, honestly.** ~2.1 s of cold start and **$0.05/month**. It is the largest task in
the remediation and its smallest saving. The case for it is the 2.1 seconds a visitor waits for a
first request, not the bill, and a report of this work that presents it as a cost saving is
misrepresenting it.

### Decision

- **`%prod` neither migrates nor validates at start.** `%dev` and `%test` still migrate at boot and
  must: Dev Services provisions a throwaway database per run, `task test:e2e` depends on it, and the
  database is a sibling container ~0.1 ms away, so there is nothing to save.
- **A migrate-only mode on the same image.** `zen.identity.schema.MigrateOnlyRunner` observes
  `StartupEvent`; when `zen.migrate-only=true` it runs Flyway and terminates. **The same binary, the
  same Flyway, the same `db/migration` location.** A Flyway CLI container was rejected: it is a
  second migration runner and a version-drift risk against "Flyway is the single migration
  authority", which is the rule this design exists to preserve.
  - **It lives in `zen-identity`**, which owns the schema baseline every application inherits — the
    same reasoning that puts `AuthResource` there. The cost is stated rather than hidden:
    zen-identity now declares `quarkus-flyway`, having previously shipped migrations without the
    migrator. An app module would have made every future application re-implement the deploy step.
  - **Exit codes are distinct because the deploy reads them:** 0 migrated or already current, 1
    Flyway raised, 2 the schema gate refused. Nothing returns 0 on a failure.
  - **`Quarkus.asyncExit`, not `System.exit`** — measured, not assumed. `System.exit` from a startup
    observer *deadlocks*: the calling thread blocks in `Runtime.exit` awaiting the shutdown hooks
    while Quarkus's own hook waits in `Application.awaitShutdown()` for a startup that can no longer
    finish. Reproduced here with a thread dump, with the migration already applied — the worst
    outcome available, because Cloud Run would then hold the deploy open until the task timeout for
    a job that was done. The job also sets `quarkus.http.host-enabled=false` so no port is bound.
- **A Cloud Run Job runs it** (`deploy:cloudrun` ONE-TIME SETUP step 1e), on the **DDL** credentials
  and deliberately not `APP_DB_*`: ADR-031 gave Flyway its own connection precisely because
  migrating and serving are different privileges, and `zen_runtime` cannot even read
  `flyway_schema_history`. A job rather than a local `docker run`, so the production database
  password stays in Secret Manager instead of on a developer's machine.
- **The deploy order is build → push → migrate with the image just pushed → `gcloud run deploy`.**
  Migration must not run with the old image, which does not carry the new migrations, and the
  service must not go live in front of a schema that is not ready. The job's exit code aborts the
  deploy, and the deploy prints which branch it took, the habit ADR-031's privilege-split line set.
- **A deploy-time schema gate replaces the boot-time one.** Before migrating, the job compares its
  own migration set against `flyway_schema_history` and refuses when the database has applied
  migrations this image does not carry (`MISSING_*` / `FUTURE_*`) — the rollback case, and the one
  thing boot validation caught that nothing else did. `ALLOW_SCHEMA_ROLLBACK=1` overrides it in the
  shape `ALLOW_DIRTY=1` already establishes: explicit, loud, and it says what it gives up. The
  override reaches Flyway too (`ignoreMigrationPatterns=*:missing,*:future`), scoped to those two
  states only — a checksum mismatch on a migration this image *does* carry still fails, because that
  is a rewritten migration rather than a rollback.

### What this supersedes, and why

- **"Flyway migrates at start and is the single migration authority"** (BLUEPRINT "Persistence") →
  **changed in half.** Single authority is untouched and is the constraint that shaped the design;
  "at start" is now true only of `%dev` and `%test`.
- **STANDARDS "Database migrations"** → **refined.** It gains the rule that migration is an act of
  the deploy, the three properties that hold it together, and a plain statement of what is given up.
- **STANDARDS "Deployment model"**'s boot decomposition, quoting ADR-027's 2.9–4.8 s cold request
  and 2.6–3.3 s boot → **superseded by measurement.** The audit's decomposition of 173 cold starts
  puts a cold request at ≈4.51 s, of which 726 ms is platform. *Why:* ADR-027 sampled twelve
  wake-ups by hand; the audit read the recorded logs and attributed the phases.
- **ADR-031** → **refined, not reversed.** Its Flyway connection was an unpriced ~660 ms on every
  boot (audit F8). That cost disappears here as a consequence of Flyway leaving the boot path, which
  is the whole of F8 resolved without touching the privilege split. ADR-031 stands exactly as
  written.

### Consequence

- **A `%prod` process now assumes its schema is already there.** `UserRoleLoader`'s `to_regclass`
  latch stops being a millisecond-wide startup nicety and becomes the only thing between a
  mis-ordered deploy and a confusing failure: role augmentation degrades to "no such user" — every
  authenticated request refused — instead of every request dying on a missing relation. Its javadoc,
  which asserted `migrate-at-start=true` creates the table "before the HTTP server accepts
  anything", is corrected.
- **A deploy now has two failure points instead of one**, and neither is allowed to be quiet. The
  job exits non-zero and the deploy stops; `task test:native` asserts the migration container's exit
  code, that it bound no port, that it created the schema, and that the serving container's log
  contains no Flyway at all.
- **The local release gate runs the production sequence.** `test:native` used to rely on
  migrate-at-start to create its schema; it now migrates in a separate container first, exactly as
  the deploy does, and exercises the schema gate in both directions. Special-casing the smoke
  container would have left the real path untested by anything.
- **Discovery is asserted.** `MigrateOnlyWiringTest` fails if `zen-identity` ever stops running
  `jandex-maven-plugin` — without the index the bean is never instantiated, and the job would boot,
  migrate nothing and exit 0, letting a deploy ship over a schema that was never created. Same
  reasoning, same shape, as `RateLimitWiringTest` (ADR-029).
- **Verified locally, and only locally** — this entry records no deployment. Measured against a
  Postgres with `log_connections`/`log_statement` on, `%prod` profile, steady-state schema: boot
  goes from **3 connections and 52 round trips** to **1 connection and 11 round trips**, and the
  boot log contains no `DbMigrate`/`DbValidate`. (Three, not the audit's four, because Wave 0's
  `jdbc.min-size=1` had already landed; the 41 round trips and 2 connections removed here are
  exactly the audit's attribution.) Local `started in` moves 1.63 s → 1.38 s and that number means
  nothing: the local database is 0.1 ms away where production's pooler is ~35 ms per round trip and
  ~332 ms per connection. **The counts are the measurement.** The migrate-only mode was exercised
  against an empty database (exit 0, schema created, no port bound), an unreachable one (exit 1,
  naming the refused connection), a database ahead of the image (exit 2, naming the migration and
  the override), and with the override (exit 0). `task test` (155 backend tests, 8 Dart suites, the
  admin typecheck, `test:e2e`) and `task test:native` are green.

---

## ADR-037 — A deploy performs the privilege cutover whether or not the plan said so, and a build define that silently does not apply must fail the build

**Date:** 2026-08-04. **Status:** accepted. **Corrects:** ADR-036's consequence "this is not the
`zen_runtime` cutover, and deliberately ships without it". **Refines:** ADR-031 (the cutover),
`build:web`.

Two things the deploy of ADR-036 taught, neither of which was visible from the repository.

### The separation ADR-036 described was not the deploy's to make

ADR-036 states that the Data API fix ships without ADR-031's `zen_runtime` cutover, so that a wrong
policy and a wrong role could not produce the same zero-rows symptom in one deploy. That was the
right reasoning and it did not survive contact with `deploy:cloudrun`, which **enables the privilege
split whenever `APP_DB_USERNAME` and `APP_DB_PASSWORD` exist in Secret Manager**. They had existed
since ADR-031 provisioned them. The deploy printed `Database privilege split ON: the app will serve
as the least-privilege role` and the cutover happened in the same revision as the migrations.

**The lesson is not "add a flag".** It is that a sequencing decision recorded only in a plan is not a
sequencing decision — the tooling had already decided, months earlier, that the presence of a secret
means "use it", and no document outranks that. Either the tool takes the switch or the plan should
not claim the property.

It was verified rather than assumed, and it is healthy. Measured against the deployed database
immediately after, which is ADR-031 step 1c's own check:

| As `zen_runtime` | As the DDL role |
|---|---|
| `current_user` = **`zen_runtime`** | — |
| `users` = **8** | `users` = **8** |
| `zen_jobs` = **2** | `zen_jobs` = **2** |
| `zen_rate_limit_counters` = **35** | `zen_rate_limit_counters` = **35** |

Equal counts on every table is the whole point: it means `users_application`, `zen_jobs_application`
and `zen_rate_limit_counters_application` all cover the runtime role, and the zero-rows trap ADR-036
was written around is absent. The application path was exercised too — a job forced due by hand ran
on the next trigger and its `run_count` went **17 → 18** with `last_status = SUCCESS`, which required
reading `zen_jobs` under RLS, deleting from `zen_rate_limit_counters` under RLS, and writing the
outcome back.

**Why a job had to be forced due, and it is worth keeping.** The first trigger returned `200` and
changed nothing, because nothing was due. "Nothing due" and "the table read zero rows" are the same
observation from outside — the exact indistinguishability the policy exists to prevent — so the
trigger alone proves nothing. Making a job due is what turns a silent success into a measurable one.

### A build define that silently does not apply must fail the build

The deployed web app could not log in. The browser refused
`http://localhost:18080/api/v1/auth/login` under the Content-Security-Policy — correctly, because
the bundle was asking for a foreign origin.

**Flutter's web build cache does not invalidate on a `--dart-define` change.** A build differing only
in `ZEN_API_URL` is answered from cache and keeps whatever URL the previous build baked in.
`test:native` builds against its smoke container at `http://localhost:18080`; every deploy after that
reused the output. Measured: **818ms cached against 18.9s real**, and the staged `main.dart.wasm`
carried a timestamp four hours older than the deploy shipping it. Revision `00016` shipped it too, so
this was not new to the ADR-036 deploy — it was inherited by it.

**Nothing caught it, and the reason generalises.** `build:web` printed the correct URL, because it
prints what it *requested*. `flutter` reported success. `deploy:cloudrun` succeeded. `verify:deploy`
passed every check — and every check it makes is unauthenticated: the shell loads, the wasm is served
as `application/wasm`, the CSP is right. The app is broken only at the first API call a user makes,
in a browser. A gate that only exercises anonymous surfaces cannot see a broken client config.

So `build:web` now discards `build/web` and `.dart_tool/flutter_build` before compiling, and then
**reads the bundle it just staged and fails if the host is absent**. The printed line says what was
asked for; only the assertion is evidence. The check is a byte search in Python rather than
`strings | grep`, because dart2wasm packs string literals without the terminators `strings` looks
for — it finds nothing and would pass vacuously, which is the failure mode being fixed, reintroduced
inside the fix. Asserted both ways: the correct host passes, a wrong host exits 1.

### Consequence

- STANDARDS "Frontend split" gains the rule: a compile-time client define that reaches a deployed
  artifact is asserted in that artifact, not trusted to the build tool.
- `verify:deploy` remains unauthenticated by design, and this entry records what that costs: it is a
  deployment gate, not a client-correctness gate. The thing that catches a bad client config is the
  build asserting its own output.
- ADR-036's separation stands as reasoning and is withdrawn as a description of what shipped. Both
  changes went out together in revision `00017`, and the cutover is measured above.
- The web bundle regression is fixed in revision `00018`, verified by byte-searching the **served**
  bundle (`tovqpjhspa` present, `localhost:18080` absent) and by the page making its first call
  same-origin: `GET /api/v1/auth/identity` → `204`. The macOS client reaches the same service:
  `Dart/3.12 (dart:io)` → `/api/v1/auth/identity` → `204`.
- **A real macOS login closed the loop that no database query could.** Read out of the deployed
  service's request log: `POST /api/v1/auth/login` → **200**, then `/api/v1/demo/ping` → 200,
  `/api/v1/demo/terms` → 200, `/api/v1/demo/ping` → 200. An authenticated request is the one path
  that makes `RoleAugmentor` read `users` — under row-level security, as `zen_runtime`, on the real
  application path rather than through a psql session standing in for it. The counts in the table
  above say the policy is right; this says the application agrees.
- The same run reproduced ADR-023's macOS exception, and it is worth naming so it is not read as a
  regression of this work: `PlatformException(..., Code: -34018, A required entitlement isn't
  present)` from the Keychain write, logged as *"Could not persist the session; it will not survive
  a restart"*. It is caught, the login proceeds — the four `200`s above are after it — and it is the
  documented consequence of the MVP's no-signing boundary, not a fault in the session path.
- Note the service answers on two hostnames — the configured origin (`SITE_URL`, `CORS_ORIGINS`,
  `AUTH_REDIRECT_URI`, and `gcloud run services describe` all agree on
  `zen-demo-server-tovqpjhspa-lm.a.run.app`) and the newer name `deploy:cloudrun` prints on success.
  The bundle is built for the configured one, so **that is the URL to open**; the other serves the
  same app and then blocks its own API calls as cross-origin. Recorded because the deploy's final
  line invites exactly that mistake.

---

## ADR-036 — Every table jZen creates is exposed to the Supabase Data API until two independent layers say otherwise

**Date:** 2026-08-04. **Status:** accepted. **Corrects:** ADR-031, which identified PostgREST's
`anon`/`authenticated` roles as the surface row-level security defends in jZen and then defended
only one table on it. **Refines:** STANDARDS "Database migrations".

### What was found, and it was live

A Supabase project publishes a REST interface (PostgREST) over the `public` schema, reached with the
project's anon key — a key Supabase publishes on purpose and documents as public. Three tables jZen
migrates into that schema had no row-level security: `zen_jobs` (`V100`),
`zen_rate_limit_counters` (`V200`), and Flyway's own `flyway_schema_history`. Only `users` was
covered, by `V2`'s `users_owner` policy.

This was not a theoretical gap. **Measured against the deployed project on 2026-08-04, before any
change**, using the `SUPABASE_KEY` the deployment already holds:

| Request, as `anon` | Result |
|---|---|
| `GET /rest/v1/zen_jobs` | **200**, every job row — id, enabled, interval, last run |
| `GET /rest/v1/zen_rate_limit_counters` | **200**, live counters with their subject hashes |
| `GET /rest/v1/flyway_schema_history` | **200**, the full migration history |
| `GET /rest/v1/users` | **200 `[]`** — `users_owner` matching nothing, exactly as designed |
| `PATCH /rest/v1/zen_jobs` (filter matching no row) | **204** — the UPDATE was accepted |
| `DELETE /rest/v1/zen_rate_limit_counters` (filter matching no row) | **204** — accepted |

The two write probes used filters that match nothing on purpose: a `204` proves the statement was
executed and zero rows qualified, while a missing privilege answers `401` with SQLSTATE `42501`.
The privilege is what was being measured, and it was there, without touching a row.

**The `users` row is the control that makes the rest legible.** The same key, the same schema, the
same request shape — and an empty array, because that table had a policy. Nothing about the
transport or the key was ever the problem.

### Why this is severe, and it is not about the rows

None of these tables holds a secret. `zen_rate_limit_counters` stores salted hashes by design
(ADR-029), and a job's schedule is not confidential. What they hold is **control**:

- One `UPDATE` setting `zen_jobs.enabled = false` stops the retention job. Retention is the whole
  of how jZen discharges its GDPR obligation (ADR-008), and nothing raises when it stops — the next
  tick simply finds nothing due and reports success. Setting `interval_seconds` to something
  enormous is the same attack with a slower fuse.
- A `DELETE` against `zen_rate_limit_counters` clears an attacker's own window on demand. That
  table exists precisely because the hour-scale windows cannot live in memory under
  `--min-instances=0`, where the process is replaced about hourly (ADR-027). A limiter whose
  counters anyone may erase is decoration. The mirror case is worse: rows written against someone
  else's subject hash lock a legitimate address out.
- `flyway_schema_history` decides what the schema *claims* to be. ADR-031 already revoked it from
  `zen_runtime` for that reason; it was reachable over HTTPS the entire time.

### The decision: two independent layers, and neither is the other's backstop

**Layer one — row-level security on the tables, shipped by the module that owns each.**
`R__jobs_row_level_security.sql` and `R__ratelimit_row_level_security.sql` enable RLS and create a
`FOR ALL TO zen_runtime USING (true) WITH CHECK (true)` policy, the same shape `users_application`
has. No `FORCE ROW LEVEL SECURITY`, for ADR-031's unchanged reason: the owner must keep bypassing.

**The policy is not decoration, and its absence is the trap this decision most had to avoid.** The
deployed application still connects as the owner, so RLS does not apply to it *today*. The moment
ADR-031's cutover happens it does — and an RLS table with no policy for `zen_runtime` returns **zero
rows, not an error**. `JobScheduler` would find nothing due, run nothing, and report a successful
tick, forever. That is why both migrations ship the policy in the same file as the `ENABLE`, and why
`DatabasePrivilegeTest` asserts the row count in both directions rather than asserting that no
exception was thrown.

**Layer two — the Data API roles lose their privileges on the schema.**
`R__identity_data_api_lockdown.sql` revokes ALL on all tables, sequences and functions in `public`
from `anon` and `authenticated`, and revokes the `ALTER DEFAULT PRIVILEGES` that would otherwise
re-grant every future table. It ships from `zen-identity` because it names *roles* and never a
sibling module's table — the same rule `R__identity_application_role.sql` states for its
schema-wide grants.

They are independent on purpose. RLS protects the tables that exist and says nothing about the next
one someone adds; the revoke covers tables not yet written and would be undone by one `GRANT` typed
into the dashboard. `DatabasePrivilegeTest` therefore proves each **with the other switched off**:
`rowLevelSecurityAloneStopsTheDataApiRoles` holds the grants and toggles RLS, and
`theDataApiRolesLoseEveryPrivilegeOnThePublicSchema` disables RLS and runs the lockdown.

### Two things the measurement changed about the plan

**The first draft revoked `USAGE ON SCHEMA public`, and that was wrong in both directions.** Schema
usage is held by `PUBLIC`, not only by the Data API roles — measured on a stock Supabase database,
`nspacl` contains `=U/pg_database_owner`. So revoking it from `anon` changes nothing at all, and
revoking it from `PUBLIC` would strip every role holding no explicit grant, which includes
PostgREST's own `authenticator` login role. A control that either does nothing or breaks an
unrelated component is not a control. **Table privileges are the lever**: PostgREST needs `SELECT`
on a table whatever it holds on the schema, and without it answers `42501` before a row is read.

**The exposure is version-dependent, which is the argument for establishing the property rather than
inheriting it.** A Supabase stack started from today's CLI grants `anon` only `Dxtm` — TRUNCATE,
REFERENCES, TRIGGER, MAINTAIN — so its PostgREST already refuses a read. The deployed project,
created earlier, carries `arwd` as well, and that is why it answered `200`. A second stock database
inspected the same day still showed `postgres | r | {anon=arwdDxtm/postgres}` in `pg_default_acl`,
so this is not a setting that has been retired. Depending on which defaults a project happened to be
created under is exactly the kind of inheritance jZen does not accept, and it is also why the revoke
says `ALL` rather than naming the four DML verbs: **`TRUNCATE` is granted even on the "safe"
defaults**, and it empties a table without deleting a row.

### What this does not cover, said plainly

The default-privileges revoke names the role Flyway connects as, because that is the role which
creates jZen's tables. A table created by something else — the dashboard's table editor runs as
`supabase_admin` — takes that role's defaults instead, which still grant `anon` everything, and
altering another role's default privileges requires membership in it. So a table created outside
these migrations is exposed until someone revokes it, and per-table RLS is what stands in for this
layer there. That is a limit of the mechanism, not an oversight.

`flyway_schema_history` deliberately gets no policy. Flyway owns that table, takes its migration
lock on it and rewrites it on every run; RLS there is a way to break the lock rather than a way to
protect anything, and the revoke already removes the Data API's reach.

### What this supersedes, and why

- **"RLS is genuinely load-bearing for the client Postgres *does* know per request — PostgREST's
  `anon` and `authenticated` roles … That is the surface `users_owner` defends, and this entry
  narrows the claim to it rather than deleting it"** (ADR-031) → **corrected in scope, not in
  reasoning.** *Why:* every word of it is right, and it was applied to one table. `zen_jobs` and
  `zen_rate_limit_counters` are on the same surface, reached by the same roles, with the same key,
  and nothing in the repository noticed — because the modules that own them were written after the
  entry that would have covered them, and no rule connected the two. A decision that holds only for
  the tables that existed when it was written is a decision with a expiry date nobody wrote down.
  The rule added to STANDARDS is the durable half of this correction.
- **STANDARDS "Database migrations"** → **gains a rule**: a table added to `public` is exposed to
  the Data API until something says otherwise, so every new table ships RLS and an application
  policy in the same change. *Why:* the band table and the timestamp rule govern how a migration is
  *named*; nothing governed what a migration must *contain*. This gap was created by ordinary,
  careful work — two modules each adding a table the normal way — which is the signature of a
  missing rule rather than a missing review.

### Consequence

- Three repeatable migrations, one per owning module. Repeatable and not versioned for the reason
  `R__identity_application_role.sql` records: these are desired state, they must reach tables from
  any band, and a low version is out-of-order on any database past it (ADR-033).
- **`DatabasePrivilegeTest` grows a third stand-in.** Dev Services is plain PostgreSQL with no
  `anon` role, so the test creates `anon` and `authenticated` **and grants them what Supabase grants
  them**, including the `ALTER DEFAULT PRIVILEGES` half — otherwise "a new table anon cannot read"
  would be true of a database where nothing ever granted anything, and would prove nothing.
- Verified green: `DatabasePrivilegeTest` 14/14, the backend suite **136** tests, and the live
  release gate `task test:e2e` **16/16** against real Supabase + Quarkus.
  `verify:boundaries`, `verify:docs` and `sync:contracts` all pass.
- **Measured before and after on one local Supabase database**, which is the evidence that the
  migrations do what the prose says. Before: `anon=Dxtm,authenticated=Dxtm` on all four tables,
  `relrowsecurity = false` on the three. After: **neither role appears in any table's ACL at all**,
  `relrowsecurity = true` on `zen_jobs` and `zen_rate_limit_counters`, both `_application` policies
  present, and PostgREST answering `401 / 42501` on all four — including `users`, which had
  previously answered `200 []`. `service_role` is untouched, by design: it is the operator's key,
  not a client's.
- The application path is unaffected, which is the other half of what had to be true: `/api/v1/health`
  and `/api/v1/demo/terms` answer normally against the locked-down database, and the e2e gate covers
  the rest.
- **This is not the `zen_runtime` cutover**, and deliberately ships without it. ADR-031's role and
  its secrets exist in `jzen-prod` but the revision does not reference them, so the application still
  connects as owner and the new policies are inert until it does. Shipping both at once would give
  a wrong policy and a wrong role the identical symptom — zero rows, no error — and one deploy in
  which to hide. The cutover is its own deploy, with one variable changed.
- A third layer exists and is operator-side rather than schema: stop exposing `public` through the
  Data API at all. It is now `deploy:cloudrun`'s ONE-TIME SETUP step 1d, outside this repository
  because it is a project setting.

---

## ADR-035 — The security headers sit on the Vert.x router, the app self-hosts its renderer, and HSTS stops short of the two additions that are one-way doors

**Date:** 2026-08-04. **Status:** accepted. **Refines:** ADR-016 (the Wasm delivery target),
ADR-027 (what "no edge" costs and buys), STANDARDS "Deployment model". **Closes:**
`docs/plans/SECURITY-REMEDIATION.md` F8.

### Context

The audit found jZen serving no security headers at all: no `Content-Security-Policy`, no
`Strict-Transport-Security`, no `X-Frame-Options`, no `X-Content-Type-Options`, no
`Referrer-Policy`. Confirmed against the deployed service before this work began — the response to
`GET /` carried `cache-control`, `content-type`, and nothing else jZen had chosen.

Three questions had to be answered with evidence rather than convention, and each of them had an
obvious answer that was wrong.

### 1. Which layer, and the answer is not JAX-RS

The instinct is a `ContainerResponseFilter`, because `zen-transport` already hosts JAX-RS
providers. It would have covered the API — the part of the surface with no DOM, no frames and no
scripts — and left bare the two responses that actually need a CSP: the Flutter web app at `/` and
the admin panel at `/admin/`, both served by Quarkus's static-resource handler, which sits on the
Vert.x router well before any JAX-RS provider runs.

So the headers install as a Vert.x route at `Integer.MIN_VALUE` with an `addHeadersEndHandler`, and
`SecurityHeadersTest` asserts all three path shapes separately rather than trusting the argument.

**It is an `@Observes Router` route, not a `@RouteFilter`**, which the plan had proposed. Both are
the Vert.x layer and the decision between them is not architectural: `@RouteFilter` would mean
adding `quarkus-vertx-web` to `zen-transport` for a capability the router already exposes.
`StaticCacheHeaders` established the pattern in this module and is the empirical evidence it
reaches the static handler — its `Cache-Control: no-cache` override is observable on the deployed
`/` today.

### 2. The CSP, measured against the deployed page rather than a local `flutter run`

This is the half that white-screens production if it is reasoned about instead of measured. The
real page load fetched two things cross-origin:

| Fetched from | What it is | Outcome |
|---|---|---|
| `www.gstatic.com/flutter-canvaskit/<rev>/skwasm.{js,wasm}` | the renderer | **removed**, not allow-listed |
| `fonts.gstatic.com/s/roboto/…woff2` | the default typeface | **allow-listed**, in `font-src` only |

**The renderer is self-hosted, and it costs nothing.** `flutter build web --wasm` already stages a
complete `canvaskit/` directory (~37 MB) into the image and then ignored it, because the loader
defaults to Google's CDN unless `useLocalCanvasKit` is set. `--no-web-resources-cdn` makes the app
use the copy it was already shipping. The bundle does not grow; the image does not grow; what
changes is that `script-src` stays `'self'`. Allow-listing a CDN in `script-src` is permission to
execute whatever that host serves, which is the single thing a CSP exists to withhold.

**The font is allow-listed**, and it is the only third-party host in the policy. There is no build
flag for it the way there is for the renderer — removing it means bundling a typeface and setting
the theme's family, which is application UI work. `font-src` grants no ability to execute anything,
so this is the cheapest possible relaxation and it is scoped to the one directive.

The three remaining relaxations are named in `SecurityHeaders`' javadoc with what each buys:
`'wasm-unsafe-eval'` (without it the Wasm app does not start — and it exists precisely so Wasm need
not be bought with `'unsafe-eval'`), `'unsafe-inline'` in `style-src` (Material UI and the Flutter
engine both inject styles at runtime with no nonce available), and `blob:` in `worker-src` /
`img-src` (the Wasm renderer rasterises on workers created from blob URLs).

**Is a policy with those relaxations worth having?** Yes, and the reason is what remains closed
rather than what is open: `script-src` names no host but this one, `object-src` and
`frame-ancestors` are `'none'`, `base-uri` is `'self'` so an injected `<base>` cannot re-point every
relative URL on the page, and `connect-src 'self'` means an injected script cannot exfiltrate
anywhere. The relaxations are about *styling* and *how Wasm is loaded*; none of them re-admits
remote code.

### 3. HSTS: `max-age` only, and the omissions are the decision

`Strict-Transport-Security: max-age=31536000`. **No `includeSubDomains`, no `preload`.**

Cloud Run serves this application over HTTPS and nothing else, so the header is nearly free. The
two usual additions are refused for one reason: **they are promises about a hostname that is not
settled.** The service answers on a generated `*.run.app` address, and the domain question is open
by decision (ADR-027 defers Cloudflare, and a domain arrives with it for App Links and mail).
`includeSubDomains` would bind names that do not exist and cannot be tested. `preload` is worse: it
is a submission to a list browser vendors ship, enforced by software this repository does not
control and unwound over months rather than by a deploy. A one-way door is not something to walk
through for a demo service on a generated hostname. Both become correct once there is a real
domain, and are cheap to add then — which is why the assertion that they are *absent* is a test
rather than a comment.

**It is sent only when the client actually used TLS**, and that is not fussiness. On
`localhost:8080` a browser honouring an HSTS header would pin the developer's machine to HTTPS for
a year against a port with no TLS on it. In production TLS terminates at Cloud Run's frontend, so
the connection Quarkus sees is plain and the truth arrives in `X-Forwarded-Proto` — which Vert.x
reads into `scheme()` only because `%prod` sets `proxy-address-forwarding`. Both directions are
asserted, because a gate that always closes and a gate that never opens look identical from the
closed side.

### Consequence

- The route lives in `zen-transport`, which is Jandex-indexed, and is therefore silent if the index
  is ever lost. `SecurityHeadersWiringTest` resolves it from the `BeanManager` for the same reason
  `RateLimitWiringTest` resolves the limiter. Headers are a particularly bad thing to lose this
  way: a missing rate limiter eventually shows up as abuse, a missing CSP shows up as nothing until
  it is the reason an injection became an account takeover.
- `task verify:endpoints` asserts the headers on `/`, `/admin/` and `/api/` against the **real
  served artifact**, and asserts `script-src` names no host but this one. The `@QuarkusTest` cannot:
  the web bundle is gitignored, so those paths 404 on a clean checkout.
- **`--no-web-resources-cdn` is now load-bearing.** Removing it from `build:web` does not fail a
  build or a test; it makes the deployed page request a script from a host the CSP refuses, and the
  app renders nothing. The flag carries a comment saying so, and the `verify:endpoints` assertion on
  `script-src` is what would catch the policy being widened to accommodate it.
- ADR-027's "no edge" position gains a third thing depending on it, alongside the cookie path and
  `.well-known`: an edge that injects its own CSP, or a challenge script, would break the page in a
  way that looks like an application bug.

---

## ADR-034 — Dependency vulnerabilities get a gate that cannot pass quietly, and it is not part of `task test`

**Date:** 2026-08-04. **Status:** accepted. **Refines:** STANDARDS "Orchestration" (a gate that
needs a network), STANDARDS "Failures surface; nothing is swallowed". **Closes:**
`docs/plans/SECURITY-REMEDIATION.md` F20.

### Context

The security audit named one outright **GAP** rather than a finding: jZen's Java dependencies had
**never** been scanned for known vulnerabilities. Not scanned and clean — never scanned. The
TypeScript side had `pnpm audit`; the Dart side has no equivalent worth running (pub has no
advisory database of its own); the Java side, which is the entire server, had nothing.

The first attempt to close it is the reason this entry exists, because the tool that looked like
the obvious answer failed in the exact way this repository has a written rule against.

### What was measured, and what it disqualified

| Candidate | Needs a credential | Fails on a finding | **Fails when it cannot check** |
|---|---|---|---|
| `ossindex-maven-plugin` | yes, now | yes | **no** |
| `dependency-check-maven` | yes (NVD API key) | yes | yes |
| `osv-scanner` on `pom.xml` | no | yes | **no** |
| Maven resolves + a script queries OSV | no | yes | yes |

- **`ossindex-maven-plugin`** is the keyless option on paper and was tried first. Sonatype's OSS
  Index now answers an anonymous request with `401 Unauthorized`, and the plugin logs
  `[WARNING] Failed to fetch component-reports` and **lets the build succeed**. A full run across
  this repository's eight modules reported `BUILD SUCCESS` having checked nothing. That is not a
  weak gate, it is an anti-gate: it manufactures the evidence that no one needs to look.
- **`dependency-check-maven`** is the industry standard and does fail properly. It needs an NVD API
  key; without one the database sync is throttled into uselessness, and the documented remedy is a
  flag that makes the build pass regardless. A key is a credential that cannot be committed, and
  the same cost and secret discipline that produced ADR-027's rejection of Cloud Armor rules it out
  here — not any doubt about the tool.
- **`osv-scanner` pointed at `pom.xml`** resolves transitively against Maven Central, so it cannot
  see the `zen:*` SNAPSHOT modules that are the whole point of this repository. It printed the
  resolution failure, reported `0 packages`, and **exited 0**. The ossindex failure again, in a
  different tool.

### Decision

- **Maven resolves; a script understands the result.** `mvn dependency:list` produces the real
  graph — it is the only thing here that can, because it knows the local repository — and
  `scripts/audit-maven.py` parses it, queries `api.osv.dev` (no key, no local database), and exits
  non-zero. That split is STANDARDS "Scripting" Rule 3 applied literally, and ADR-032's rule
  picked the language without anyone choosing it.
- **It fails when it cannot answer.** A network error, an HTTP error, a malformed response, a
  result count that does not line up with the query, an unreadable suppressions file, or an *empty
  dependency list* all exit 1 with the reason. "We did not look" and "we looked and it was clean"
  must not produce the same exit code. The empty-list case is the one that matters most and is the
  one every tool above got wrong.
- **Suppressions carry their reason inline, or the file does not parse.**
  `scripts/audit-suppressions.txt` is `<ADVISORY-ID>  <why this is accepted>`, and a line without
  the second half is a hard error. A suppression list rots because adding to it is cheaper than
  justifying an entry, and the conventional shape — an XML file of bare `<suppress>` elements —
  makes that exactly true. This makes the two cost the same. It is empty today, which is the
  correct state.
- **It is NOT part of `task test`, and that is the deliberate half.** `task test` is the release
  gate and has to be a statement about the code. This task asks a remote service a question about
  the outside world, and the answer changes when nothing in the repository changed — a suite that
  goes red overnight because an advisory was published, or because a developer is on a train,
  teaches people to ignore it. `task audit` stands alone, says in its own description that it needs
  a network, and belongs in CI on a schedule and before a release.
- **`task audit:admin` covers both TypeScript packages.** `admin/` (the scaffold) and
  `apps/*/*_admin` (the panel) resolve independently — the panel imports the scaffold from source
  via a TypeScript paths alias rather than a pnpm dep edge (ADR-005) — so a package vulnerable in
  one tree is invisible from the other. Checking only the panel missed the scaffold's own copy of
  the react-router advisory, which is how this was found.

### What the gate found on its first run

Not a formality. **14 vulnerable Java dependencies**, and two of them were about jZen's own
guarantees rather than a transitive library: `quarkus-vertx-http` 3.32.2 carries
**GHSA-qcxp-gm7m-4j5v** and **GHSA-rc95-pcm8-65v9**, both HIGH
*authentication/authorization bypass* advisories, in the extension jZen's entire authorization
model runs through. The deployed revision was running that version.

Moving the platform to **3.38.0** closed those two and eleven of the rest (netty's codec, http,
http2, handler and resolver-dns; vertx-core; pgjdbc; opentelemetry), because all of them arrive
through that BOM. The last one, jackson 2.22.0, is pinned one patch forward to **2.22.1** by
importing `jackson-bom` ahead of the platform's. The gate now reports **259 dependencies, no known
vulnerabilities**.

That result is the argument for the entry: a gate whose first run finds two HIGH auth bypasses in
the running version is not a formality that was missing, it is a check that was missing.

### What this supersedes, and why

- **"Two areas are not covered and must not be read as clean: Maven dependencies have never been
  CVE-scanned (F20)"** (`SECURITY-REMEDIATION.md` §, preamble) → **closed.** *Why:* it is covered
  now, by a gate rather than by an audit, so it stays covered.
- **"Baseline: Quarkus 3.32.2 on Java 25"** (`CLAUDE.md`) → **3.38.0 on Java 25.** *Why:* the
  version moved for a security reason and the baseline sentence is the one place a reader looks
  for it.

### Consequence

- The gate needs no new binary and no secret: `python3` was already a declared toolchain (ADR-032)
  and `curl`-equivalent access to `api.osv.dev` is all it adds. `task doctor` is unchanged.
- Test-scoped dependencies are excluded by default, and `--include-test-scope` asks the other
  question. A vulnerable test library is a real finding about a developer's machine, but it is not
  shipped, and one verdict cannot honestly mean both things at once.
- **A green `task audit` is a statement with a date on it.** Nothing in this repository changes
  when a new advisory is published, so the gate's value is entirely in being run again. That is
  why it is wired for CI rather than left as a thing someone remembers.

---

## ADR-033 — A migration version is a timestamp: monotonic by construction, because a band cannot be

**Date:** 2026-08-04. **Status:** accepted. **Supersedes:** ADR-008's version-band table, for every
migration written from now on. **Refines:** STANDARDS "Database migrations", ADR-031 (which found
the problem and solved one instance of it).

### Context

ADR-031 discovered, by the application failing to boot, that a reserved version band allocates
ownership but does not stay reachable: production has run `V100` (zen-jobs) and `V200`
(zen-ratelimit), so a new `V3` inside zen-identity's 1-99 band is out-of-order and Flyway refuses
to start at all. It escaped by making that file **repeatable**, which was the right shape on the
merits — grants and policies are a desired state, not a step.

Wave 4 has a migration that cannot take the same exit. Adding `UNIQUE` to `users.email` is a schema
**step**: it happens once, it is checksummed, and expressing it as an `R__` file that re-runs on
every checksum change would be a lie about what it is. It needs a version, and the version has to
be above every version any database has already applied.

**A band cannot express that.** "Above everything applied" is a fact about the whole repository over
time; a band is an allocation to one module. The two are not the same kind of statement, and
ADR-008's table silently implied they were.

### What was rejected, and why

- **Extend the band scheme — give zen-identity a second, higher range.** It fails on the second
  occurrence, not the first. Say zen-identity gets 2000-2099 and zen-jobs 2100-2199; the moment
  zen-jobs ships a `V2100`, zen-identity's *next* migration is out-of-order again. Every scheme
  that allocates contiguous per-module ranges has this property, because interleaving over time is
  exactly what ranges cannot represent. Moving the trap further away is not removing it.
- **A hand-assigned globally monotonic integer** — `V201`, then `V202`. It works, and it re-creates
  the collision the bands were invented to prevent: two libraries developed on parallel branches
  both pick the next free number, and the merge produces two `V201` files. Flyway catches that
  loudly, so it is a nuisance rather than a hazard — but it is a nuisance on every branch forever,
  and it needs a human to look up "what is the highest number anywhere" before writing a file.
- **`out-of-order=true` / `ignoreMigrationPatterns`.** Both work by making Flyway stop checking, the
  same shape of change as `validate-on-migrate=false`, which STANDARDS already refuses. Not
  considered further, and named here so nobody has to consider them again.

### Decision

- **A new versioned migration is named `V<UTC timestamp>__<module>_<what>.sql`**, timestamp as
  `YYYYMMDDHHMMSS`. The first is `V20260804113000__identity_email_unique.sql`.
- **This is monotonic by construction and needs no coordination.** Two branches cannot collide
  without being written in the same second, and whichever merges second is still ordered after
  whatever shipped in between. It is the industry-standard answer to this exact problem for the
  same reason.
- **The owning module moves into the description**, which is where `R__` migrations already carry
  it (`R__identity_application_role.sql`). Nothing is lost: the band never appeared in a query, a
  log line or an error message — the file name is what a human reads, and the file name still says
  `identity`.
- **The applied migrations keep their numbers and their meaning.** `V1`, `V2`, `V100`, `V200` are
  immutable, and the band table stays in STANDARDS as the record of what they are. It stops being
  an instruction for new work.
- **Applications keep 1000+ as a floor, and it is now advisory.** A timestamp is above 1000 by
  several orders of magnitude, so the "no library can grow into an application's numbering" rule is
  satisfied automatically rather than by discipline.

### What this supersedes, and why

- **"Each framework library owns a reserved version band, and never numbers outside it"**
  (STANDARDS "Database migrations", ADR-008) → **superseded for new migrations.** *Why:* the rule
  solves the collision problem correctly and does not solve the ordering problem at all, and the
  second one is the one that stops a deployment from booting. A timestamp solves both. The table
  is retained as history, because four applied migrations are described by it.
- **"A library's second migration either takes a number above every applied version, or … is
  repeatable"** (STANDARDS "Database migrations", ADR-031) → **refined into a rule that does not
  need judgement.** *Why:* it is accurate and it leaves the number to be chosen correctly each
  time, by a person, against a fact they have to go and look up. "Use a timestamp" needs no lookup
  and cannot be got wrong by omission.

### Consequence

- STANDARDS "Database migrations" gains the timestamp rule and marks the band table historical.
- Verified rather than assumed: on a fresh database Flyway applies
  `1, 2, 100, 200, 20260804113000` in that order and then the repeatable, and reports
  `now at version v20260804113000`. Ordering across the boundary is the property this entry rests
  on, so it is the one that was watched.
- **pgcrypto was not dropped, and F18 is therefore half-closed on purpose** — recorded here because
  it is a decision and not an omission. The audit paired the `UNIQUE` constraint with dropping the
  unused `pgcrypto` extension `V1` creates. Measured against the live database: on Supabase, in
  production and locally alike, **pgcrypto is provisioned by the platform in the `extensions`
  schema before jZen's first migration runs**, so `V1`'s guard has never fired there and jZen has
  never created it. Dropping it would delete platform infrastructure out of a schema this
  application neither owns nor migrates. On plain PostgreSQL — Dev Services, the native smoke
  container — `V1` does create it, unused, and dropping it only there would make the migration
  behave differently depending on which database it met. It is left alone in both places. The
  reasoning is in the migration's own header, where the next person to reach for `DROP EXTENSION`
  will be standing.

---

## ADR-032 — `scripts/` is bilingual by rule: sh runs things, Python understands things

**Date:** 2026-08-04. **Status:** accepted. **Refines:** ADR-014.

### Context

Python entered this repository without a decision. `scripts/pick-device.py` landed on 2026-08-01,
eight days after ADR-014 argued the orchestrator choice at length, and nothing recorded that a
second scripting language had joined the repository or what it was allowed to do. The consequence
is measurable: every other toolchain is pinned in the file its own ecosystem reads and checked by
`doctor` — `java` (`.sdkmanrc`), `flutter` (`.fvmrc`), `node` (`.nvmrc`), `pnpm` (`packageManager`)
— while `python3` is pinned nowhere, checked nowhere, and set up in no CI job. `run:demo:native`
fails with a raw `env: python3: No such file` on a machine without it.

The question that forced the issue was a different one: `Taskfile.yml` has reached 1976 lines, and
the maintainer is fluent in Java, Dart and TypeScript but not in sh. Two answers suggested
themselves and both are wrong.

**Replacing `task` with a runner written in a product language** (Gradle/Maven-driven Java, a Dart
CLI, an npm-script layer) fails on ADR-014's own grounds plus one this repository has not written
down: `doctor` exists to verify the toolchain, so the tool that runs it cannot depend on the
toolchain. A Java runner needs a JDK resolve before it can report that the JDK is missing. It also
elevates one of three peer product languages to the language that builds the other two, which is
the language-neutral-root rule (ADR-014 point 4) arriving from the inside.

**Converting the shell to Python wholesale** fails on measurement. Of the 1976 lines, 605 are
`summary:` prose, 271 are YAML structure, and 171 are comments and `desc:`; only **539 are shell
logic**, and 109 of those are bare tool invocations (`gcloud run deploy …`, `./mvnw …`) that read
identically in any language. The lines that genuinely cannot be reviewed by inspection — nested
`grep` pipelines, the `awk` comment-strippers, and the backtick smuggled past command substitution
as `bt=$(printf '\140')` because a literal one would be command substitution before `grep` saw it —
amount to **72 lines in two tasks**.

So the real problem was never the volume of sh, and never the number of languages. It was that a
small, identifiable subset of the shell implements *algorithms* whose correctness is not visible
from reading them, and that subset is exactly where a defect hides silently.

### Decision

**1. Python is a declared, first-class scripting language of this repository, bounded by a rule.**
It is not the default and sh is not the default; each has a domain, and `scripts/` holds both
because both are scripting languages serving the dev loop.

**2. The rule is four ordered tests. First match wins.**

| # | Test | Language |
|---|---|---|
| 0 | Must it run *before* the toolchain is verified? | **sh** |
| 1 | Does it start, background, signal, wait on, or kill a process — or export environment into its caller? | **sh** |
| 2 | Does it only run commands and branch on exit codes or scalars a tool hands it? | **sh** |
| 3 | Must it understand *content* — parse structure out of text, or construct structure safely into it? | **Python** |

**Tiebreak:** if Rule 3 work is ≲3 lines inside a Rule 1/2 script, it stays sh. If Rule 3 work *is
the point* of the script, Python. In one sentence: **sh runs things; Python understands things.**

Rule 0 is not an exception carved for `doctor`; it is ADR-014 point 1's reasoning applied one level
down. The tool that verifies the toolchain cannot depend on the toolchain, which is why `task` is
itself unpinnable (ADR-014, Consequence) and why `doctor` stays sh permanently.

Rule 1 is the one that is structural rather than stylistic. `lib.sh`'s `ensure_supabase` runs
`eval "$(supabase status -o env | sed 's/^/export SB_/')"` and exports into **its caller**, which
`start_backend` then relies on `java` inheriting. A Python child process cannot export into its
parent — that is an operating-system property, not a shortcoming of the language — so the launchers
are not sh by preference, they are sh by necessity.

**3. Applying the rule to what exists.** It reproduces every choice already made, and disagrees
with exactly three files:

| Artifact | Rule | Verdict |
|---|---|---|
| `doctor` | 0 — bootstrap | sh, permanently |
| `lib.sh`, `admin.sh`, `demo.sh`, `stop.sh` | 1 — trap, background, foreground, kill, export-into-caller | sh |
| `deploy:cloudrun`, `destroy:cloudrun`, `test:e2e`, `test:native`, `run:demo*`, `build:*` | 2 — invocation | sh |
| `sync:verify` | 2 — `git status --porcelain`, emptiness check | sh |
| `verify:endpoints`, `verify:deploy` | 2 + one parse line → tiebreak | sh |
| `pick-device.py` | 3 — parses `flutter devices --machine` JSON | Python *(already)* |
| **`seed-admin.sh`** | **3 — constructs JSON and SQL** | **→ Python** |
| **`verify:boundaries`** | **3 — parses Dart/TS source, strips comments** | **→ Python** |
| **`verify:docs`** | **3 — parses docs** | **→ Python** |

That the rule independently re-derives `pick-device.py` as Python and all four launchers as sh is
the evidence that it describes this repository rather than imposing a preference on it.

**4. Python is floored, not pinned — and the distinction is the existing one.** `doctor` already
separates `checkv` (presence **and** pinned version, for the four build-input tools) from `check`
(presence only, for services and clients), on the principle that a version is pinned when it shapes
the artifact. Python shapes no artifact: it returns verdicts and seeds a dev database. It therefore
joins the `check` group with a **minimum of 3.9**, verified against Apple's `/usr/bin/python3`
(3.9.6), so the scripts run on a Mac carrying nothing but Xcode Command Line Tools. No
`.python-version` file is created: nothing but `pyenv` reads one, so it would be an inert file
making a pin-shaped claim about a tool that is not pinned.

**5. Stdlib only.** No `pip`, no virtualenv, no `requirements.txt`. This preserves the property
that made `task` the right orchestrator — the dev loop bootstraps from what is already installed.
A gate that needs a third-party library has grown past being a gate.

**6. `make` is closed, not deferred.** ADR-014 left one door open: a trigger under which moving
recipe bodies into `scripts/` would make `make`'s ubiquity win. This entry moves two bodies into
`scripts/` and, in doing so, establishes that the door was never real — the trigger's premise is
false, on the evidence below. **`go-task` is the orchestrator for the life of this repository**, and
a future proposal to adopt `make` is arguing against a measured decision, not filling a silence.
What remains open is a different and still-sound question: ADR-014's *second* trigger, about CI
wall-time once a second application lands, is untouched and still points at `sources:`/`generates:`
fingerprinting, then affected-detection, then Moon. Closing `make` is not closing orchestration.

### What this supersedes, and why

- **"If the Taskfile's recipe bodies collapse to one-line wrappers with the real logic living in
  `scripts/`, then `task` is adding nothing that `make` does not, the four objections in point 2
  evaporate along with the multi-line blocks that cause them, and `make`'s ubiquity wins. Revisit
  then."** (ADR-014 point 7, first reversal trigger) → **retired.** *Why:* the trigger rests on a
  premise that measurement does not support — that all four objections in ADR-014 point 2 are
  consequences of multi-line bodies. **Two of them are independent of body length, and two more
  that ADR-014 never weighed are as well.**

  1. **Discovery does not evaporate.** `verify:docs` (ADR-012) mechanically asserts that every
     `task <name>` named in a doc resolves in `task --list` — **57 distinct references** across the
     READMEs and architecture docs today. `make` has no `--list`; the substitute is a hand-rolled
     `##`-comment convention plus an `awk` parser, in a repository whose headline rule is "no custom
     magic". ADR-014 already called this "the objection this entry finds hardest to answer", and it
     is exactly as hard when every body is one line.
  2. **The phony tax does not evaporate.** All 51 targets need `.PHONY` regardless of body length.
  3. **`summary:` was never weighed, and is now the largest loss.** The Taskfile carries **18
     `summary:` blocks spanning 605 lines — 31% of the file** — reachable as
     `task <name> --summary`. That is the operator-facing contract for things like
     `deploy:cloudrun`'s capacity knobs (ADR-028), and `make` has no equivalent at any body length.
     This surface barely existed when ADR-014 was written and has since become load-bearing.
  4. **Task naming was never weighed, and is disqualifying on its own.** **44 of 51 task names
     (86%) contain `:`** — `deploy:cloudrun`, `test:apps:server`, `generate:proto:java` — which is
     `make`'s rule separator. Adopting `make` means renaming every one of them, breaking the 57
     documented references above, `CLAUDE.md`, and `ci.yml`. Body length has no bearing on this.

  The direction of travel confirms it independently: the Taskfile has gone from **12 multi-line
  blocks across 40 tasks** (ADR-014, 2026-07-24) to **23 across 51**, and stands at **22** after
  this entry's first conversion — accreting inline logic roughly twice as fast as this removes it. The
  trigger anticipated a collapse that is not happening and, per Rules 0–2, is not permitted to: a
  body that supervises a process or invokes a tool is *required* to stay in the Taskfile. The
  condition is therefore not merely unmet, it is unreachable while this rule holds, and a condition
  that cannot be reached is not a trigger. It is retired rather than left standing, because a dead
  trigger in a live document is an invitation to relitigate `make` on a technicality.
- **"Shared logic (colors, Supabase bring-up, backend start, health wait, port freeing) lives in
  `lib.sh`, which the runners source."** (`scripts/README.md`) → **refined.** *Why:* accurate for
  the sh side and now incomplete. `lib.py` becomes its Python counterpart for the scripts that
  cannot source a shell file, and the README states which language a helper belongs to rather than
  implying there is only one.
- **Python's undeclared arrival on 2026-08-01** → **legitimised and bounded.** *Why:* `pick-device.py`
  was the correct call — parsing `flutter devices --machine` JSON in sh is precisely the Rule 3 work
  that hides defects — but it was made without a recorded decision, which is how it ended up as the
  only toolchain in the repository that `doctor` cannot see. This entry is the decision it should
  have arrived with, and it constrains the language rather than merely permitting it.

### Consequence

- **`doctor` gains a `python3 >= 3.9` check**, so the one tool `run:demo:native` silently depended on
  is now reported like every other. The CI `gates` job gains `actions/setup-python`, because
  `verify:boundaries` and `verify:docs` run there and will execute Python once converted; the
  dependency is declared before it is relied upon rather than after.
- **`.gitignore` gains `__pycache__/`.** This is cheap insurance and not a live fix: a `__main__`
  script is never byte-cached and `pick-device.py` imports only stdlib, so nothing is generated
  today. It matters once scripts import `lib.py`, because `deploy:cloudrun` computes `GIT_DIRTY`
  from `git status --porcelain` where untracked files count — an untracked `__pycache__/` would tag
  every image `-dirty`.
- **The `summary:` blocks stay in the Taskfile** when a body moves to `scripts/`. They are the
  operator-facing contract and are reachable as `task <name> --summary`; the Python file carries a
  module docstring about implementation. Two audiences, no duplicated text — `pick-device.py` and
  `run:demo:native` already model this split.
- **The conversions are not in this entry.** This records the rule and closes the declaration gap;
  `verify-boundaries.py`, `verify-docs.py` and `seed-admin.py` follow as separate work, and until
  they land the three rows above marked **→ Python** describe an intent, not the tree. ADR-014 set
  the precedent for an entry whose diff is a decision plus a STANDARDS cross-reference.
- **One defect is the reason `verify:boundaries` converts first.** Its scans end in
  `2>/dev/null … || true`, so if a glob stops matching — a directory renamed under `client/` — the
  gate reports success having examined nothing. That is STANDARDS "Failures surface; nothing is
  swallowed" broken by the gate that enforces the boundary rule, and the Python version asserts its
  scan matched source roots and gets fixture tests proving it still catches a planted
  `supabase_flutter` dependency.

**No behaviour changed by this entry.** The diff is this ADR, a STANDARDS section, the `doctor`
check, the `.gitignore` line, the CI step, and `scripts/README.md`; no task body, module, or
generated artifact is touched. What was measured on the delivery machine: `/usr/bin/python3` reports
3.9.6 and parses `pick-device.py` clean, Homebrew's reports 3.14.6 and wins `PATH`; the Taskfile
holds 23 multi-line shell blocks and 19 `dir:` declarations across 51 tasks, 44 of whose names
contain `:`.

---

## ADR-031 — The application stops being the database owner, and row-level security is Supabase-side only

**Date:** 2026-08-04. **Status:** accepted. **Supersedes:** `V2__row_level_security.sql`'s
implication that the `users_owner` policy is a line of defence the application path receives.
**Refines:** STANDARDS "Database migrations" (a fourth zen-identity migration; migrations may now
carry grants), STANDARDS "The client talks to one server" (the gate's language coverage).

### Context

The audit's F5 (`docs/plans/SECURITY-REMEDIATION.md`): the application connects to PostgreSQL as
the owner. **Nothing exploits this today** — every admin filter uses named Panache parameters,
sort is whitelisted, and `UserRoleLoader`'s native query takes no user input, all of it verified
during the audit. This entry is therefore blast-radius reduction and not a fix, and it is worth
being plain about which of the two it is.

What it changes is what a *future* injection, or a leaked `DB_PASSWORD`, is worth. Supabase's
`auth` schema lives in the same database as the application's `public` schema, so under the owner
role the answer is "`auth.users`, password hashes, and the ability to forge identities". Under a
role that holds DML on `public` and nothing else, the answer is the application's own data.

The second half of F5 is the more interesting one. `V2` enables row-level security on `users` and
creates `users_owner` (`id = auth.uid()`), and its own header already says the owner connection
bypasses it. So the migration reads as a second line of defence that the application path does not
get — and that ambiguity is not merely cosmetic, because **the two halves of this wave interact in
a way that fails silently.** `auth.uid()` reads a request-scoped Supabase JWT claim. jZen reaches
Postgres over a plain pooled JDBC connection carrying no such claim, so `auth.uid()` is NULL and
the predicate matches nothing. Give the application a non-owner role while that policy stands and
every query against `users` returns **zero rows** — not an error, an empty result. `RoleAugmentor`
fails closed on every request, `@RolesAllowed` refuses everything, the admin panel dies, and the
whole thing reads as a permissions bug rather than a database one.

### Decision

- **Two roles, one database.** `zen_runtime` serves traffic; the existing DDL role migrates. The
  name is deliberate: it is the role the running server *connects as*, the counterpart of the DDL
  role. The first draft called it `zen_app`, which reads as "the zen application" in a repository
  whose `apps/` directory holds exactly that — a name inviting the misreading is a defect even
  when the code is right. One role serves every application, the way one `users` table does.
- **The migration lives in `zen-identity`, and the role is framework-wide.** Worth stating rather
  than leaving to be noticed, because they are in tension: the role needs privileges over
  zen-jobs' and zen-ratelimit's tables too. It sits in zen-identity because that library owns the
  schema baseline and every application depends on it, so the role exists before anything needs
  it — and because the grants are **schema-wide** and never name a sibling's table, so no library
  reaches into another. A `zen-db` module for one repeatable migration and no code was considered
  and rejected as more layering than the problem has.
  `R__identity_application_role.sql` creates `zen_runtime` **NOLOGIN** and grants it `CONNECT`,
  `USAGE` on `public`, and `SELECT/INSERT/UPDATE/DELETE` on that schema's tables — plus `ALTER
  DEFAULT PRIVILEGES` so tables from later migrations are covered. It gets nothing on `auth`,
  nothing on `flyway_schema_history`, and no DDL.
- **The migration is repeatable, and that is forced rather than stylistic** — see the next section.
- **Flyway holds its own credentials.** `quarkus.flyway.jdbc-url` / `username` / `password`
  (Quarkus 3.32.2; all three are required together, and Quarkus only opens a separate Flyway
  connection when `jdbc-url` is present). `%test` sets none of them, so Dev Services is unchanged.
- **The migration deliberately does not create a usable credential.** A password written into a
  migration is plaintext in git, readable by everyone who can read the repository, and rotated
  only by editing source. `ALTER ROLE zen_runtime WITH LOGIN PASSWORD …` is **operator work, outside
  the repository**, and `deploy:cloudrun`'s summary step 1c carries the commands alongside the other
  fourteen secrets.
- **The split is opt-in, and the deploy says which branch it took.** `APP_DB_USERNAME` /
  `APP_DB_PASSWORD` fall back to `DB_USERNAME` / `DB_PASSWORD` when absent, and `deploy:cloudrun`
  attaches them only when both exist in Secret Manager, printing "privilege split ON/OFF" either
  way. Refusing to boot without them would break a deploy on configuration the deploy itself
  cannot supply; printing nothing would be the silent regression this wave exists to remove.
- **Row-level security on `users` is Supabase-side only, and says so in the schema.** The migration
  adds `users_application` (`FOR ALL TO zen_runtime USING (true) WITH CHECK (true)`). `FORCE ROW LEVEL
  SECURITY` is **not** set, and that is now a decision rather than an omission.

### A version band allocates ownership, and does not stay reachable

Discovered by the migration failing to boot, not by reading the rule. The obvious name for this
file was `V3`, inside zen-identity's band 1-99. Every database that has run `V100` (zen-jobs) and
`V200` (zen-ratelimit) — which is production, and the local dev database — is already past
version 3, so a new `V3` is **out-of-order** and Flyway refuses to start the application at all:

```
Caused by: org.flywaydb.core.api.exception.FlywayValidateException: Validate failed:
Detected resolved migration not applied to database: 3.
```

The band scheme (ADR-008) does exactly what it was designed to do — it stops two libraries
colliding on a version — and it silently implies something it never guaranteed, that a library can
keep adding migrations inside its band. It cannot, once a higher band has shipped. Flyway offers
`out-of-order=true` and `ignoreMigrationPatterns` as the remedies, and both work by making Flyway
stop checking, which is the same shape of change as `validate-on-migrate=false` that STANDARDS
already refuses.

So this file is **repeatable** (`R__`), which is also what it should have been on the merits.
Repeatables run after every versioned migration — so `GRANT … ON ALL TABLES IN SCHEMA public`
reaches every band's tables, on a fresh database and an existing one alike — they are keyed by
description rather than version, and they re-run when their checksum changes. What that buys is
the honest semantic for this content: grants and policies are a **desired state**, not a step, and
a privilege model that can be edited and re-applied is better than one frozen by a checksum. The
price is idempotence, which every statement in the file is written for. Nothing here weakens
validation: the versioned migrations remain immutable and validated exactly as before.

### Measured against the live database

Taken 2026-08-04 against `jzen-prod`'s Supabase project, through the **session pooler** — the same
connection Cloud Run uses. Three of these were open questions that reasoning could not close, and
one of them changed the migration.

| Question | Measured |
|---|---|
| Does the pooler accept a non-`postgres` role in the `<role>.<ref>` form? | **Yes.** `current_user` and `session_user` both answer `zen_runtime`. |
| Is the production database past the identity band? | **Yes** — `V1, V2, V100, V200` applied, so a `V3` refuses to boot. |
| Does `zen_runtime` still see rows with RLS on and `users_owner` present? | **Yes** — 8 of 8, then 9 of 9 after seeding one. Owner and application counts agree. |
| Can the DDL role revoke on the `auth` schema? | **No.** `auth` is owned by `supabase_admin`; `postgres` holds `USAGE` without grant option. |
| Can the DDL role drop or impersonate the runtime role? | **No, by default.** PostgreSQL 16+ gives a `CREATEROLE` creator membership with `ADMIN` but `inherit_option = f, set_option = f`, so `DROP OWNED BY` is refused until the membership is re-granted `WITH SET TRUE, INHERIT TRUE`. |

Every denial was exercised rather than assumed: `auth.users` (schema denied), `flyway_schema_history`
(select and delete denied), `CREATE TABLE`, `ALTER TABLE users`, `DROP TABLE users` — and the
permitted side too, insert/update/delete on `users` and reads of `zen_jobs` and
`zen_rate_limit_counters`.

**The `auth` measurement changed the migration.** It originally revoked — `REVOKE ALL ON SCHEMA
auth`, and on its tables, sequences and functions. PostgreSQL answers a revoke the caller is not
entitled to make with a **warning, not an error**, one per object and per *column* for tables, so
that version printed dozens of "no privileges could be revoked" lines on every boot while changing
nothing. It now **asserts** instead: if `zen_runtime` ever holds `USAGE` on `auth`, the migration
raises and the application refuses to start. That is strictly better than what was intended — the
revoke was always a no-op on a freshly created role, and the property that matters is that it
stays true. A control that cannot enforce itself should fail closed rather than warn.

### Why RLS cannot be the application's second line

The tempting reading is that `FORCE ROW LEVEL SECURITY` plus a policy the application can satisfy
would make this a real defence. It would not, and the reason is about access patterns rather than
plumbing: **the application legitimately reads rows it does not own.** The admin panel lists every
user; `UserRetentionService` scans every user. Any policy the application path can satisfy is
therefore a policy that permits everything the application path does. Making the application
satisfy `id = auth.uid()` would additionally require binding a per-request identity onto a pooled
connection (`SET LOCAL request.jwt.claims` per transaction), which is real architecture bought for
a predicate that then has to be widened until it protects nothing.

RLS is genuinely load-bearing for the client Postgres *does* know per request — PostgREST's `anon`
and `authenticated` roles, where the JWT claim is present by construction. That is the surface
`users_owner` defends, and this entry narrows the claim to it rather than deleting it.

### What this supersedes, and why

- **"The Quarkus JDBC connection uses the postgres/service role, which is the table owner and
  bypasses RLS (no FORCE ROW LEVEL SECURITY); the policy guards direct Supabase-side access"**
  (`V2__row_level_security.sql`, header) → **narrowed and made enforceable.** *Why:* the sentence
  is accurate and was always honest about the bypass; what it left open is whether the bypass was
  intended or pending. It was pending, and an undecided middle is the worst of the three available
  positions — it is the state in which someone tightens the role, gets zero rows, and spends a day
  in the wrong subsystem. **The file itself is not edited**: `V2` has run on production and Flyway
  checksums comments along with DDL, so correcting it is indistinguishable from rewriting its DDL
  and would refuse to boot every database that already ran it (STANDARDS "Database migrations").
  `V3`'s header and this entry carry the correction, which is exactly the mechanism that rule
  prescribes.
- **"A dedicated least-privilege database role for the application … Coordinate with Supabase
  project setup"** (SECURITY-REMEDIATION §4.3, task 3.1) → **refined.** *Why:* it reads as
  repository work and it is not entirely. The role's password cannot live in a migration, so
  provisioning is operator work by construction, and `deploy:cloudrun`'s summary step 1c is where
  those commands belong. The pooler's `<role>.<ref>` form was the open question the task rested on
  and it is now measured (above), so the arrangement the plan assumed is the one that ships — no
  direct-connection fallback, and therefore no collision with the IPv4/IPv6 constraint.
- **"Scope is `client/*/lib` and `apps/*/*/lib`"** (`verify:boundaries`, summary) → **extended to
  TypeScript.** *Why:* covering only Dart read as a statement that the boundary rule was about
  Flutter. It is about clients, and react-admin is one — a browser application holding a session
  cookie, for which `@supabase/supabase-js` is one `pnpm add` away and better documented than the
  Dart SDK. `schema.generated.ts` is excluded as generated output, and `config.ts` is the
  TypeScript analogue of `zen_identity_config.dart`.

### Consequence

- `zen-identity` still owns `V1` and `V2` in band 1-99 and now also ships one repeatable. STANDARDS
  "Database migrations" gains two rules: a band allocates ownership but does not stay reachable,
  and repeatables are named with the owning module's prefix and must be idempotent.
- **Production is unaffected until an operator acts.** The migration applies cleanly to the running
  database and changes nothing about how the application connects, because `zen_runtime` cannot log
  in. That is what makes this deployable in the same release as the rest of Wave 3.
- **`%test` still runs as the Dev Services owner**, because those credentials are generated and
  there is nothing to point at `zen_runtime`. `DatabasePrivilegeTest` therefore proves the *privileges*
  by opening its own connection as the role and trying — reading `auth.users`, creating a table,
  editing Flyway history, all refused with SQLSTATE 42501 — rather than proving the application
  path end to end. Stated here so the coverage is not read as more than it is; the end-to-end half
  was measured against the live database instead (above).
- The migration re-runs cleanly (it is repeatable, so "runs twice" is ordinary), and the
  auth-schema assertion is itself asserted: granting `zen_runtime` `USAGE` on `auth` makes the
  migration refuse, and revoking it makes it migrate again.
- `jzen-prod` is **provisioned but not yet cut over**: `zen_runtime` exists with its login, and
  `APP_DB_USERNAME` / `APP_DB_PASSWORD` are in Secret Manager. The deployed revision does not
  reference them, so the split takes effect on the next deploy and can be undone by removing two
  secrets.
- The zero-rows trap is asserted **in both directions**: with RLS enabled and a stand-in for
  `users_owner` in place, the application role still reads its rows; dropping `users_application`
  makes the same query return 0. The second half is what stops the first from passing for some
  unrelated reason, and it is why the assertion is on rows returned rather than on the absence of
  an exception.
- Verified green: `task test` (111 backend tests, including the nine above, and the live e2e gate
  at 16), `task sync:contracts`, `task test:admin`, `task verify:docs`. `verify:boundaries`'
  TypeScript extension was verified by planting a violation of each of its three checks and
  confirming it fails, then confirming both exemptions (`schema.generated.ts`, `config.ts`) hold.

---

## ADR-030 — An unverifiable session cookie means anonymous, not an error: the ambient-credential rule

**Date:** 2026-08-03. **Status:** accepted. **Supersedes:** the implicit rule in
`application.properties` that `quarkus.http.auth.proactive=true` may reject any bad credential
before routing. **Corrects:** ADR-029's coverage claim for the rate limiter. **Refines:** ADR-027
(the perimeter), STANDARDS "Deployment model" (the cookie path).

### Context

jZen keeps proactive authentication on, so every request is authenticated before it reaches JAX-RS.
Quarkus's default answer to a `zen_access_token` cookie that does not verify is an
`AuthenticationFailedException`, which proactive auth turns into a 401 **immediately** — before any
resource, filter or provider.

For a token offered in an `Authorization` header that is the right answer: the caller deliberately
presented a credential and it was bad. For a cookie it is the wrong answer, and the distinction is
the whole of this entry. **A cookie is ambient.** The browser attaches it with nobody deciding to,
so "the cookie in your jar is an hour old" is the most ordinary state a session ever reaches — not
an error condition, and not a statement of intent by anyone.

Three failures followed from treating it as one. All three were **measured against a running
server**, not inferred:

| Request (with an unverifiable access cookie) | Was | Should be |
|---|---|---|
| `POST /api/v1/auth/logout` | 401 | 204, cookies cleared |
| `POST /api/v1/auth/refresh` | 401 | 200, session renewed |
| `GET /api/v1/auth/identity` | 401 | 204, anonymous |

- **Sign-out was impossible.** The one action that ends a stale session was the one action a stale
  session could not perform — and after Wave 2 it is also where upstream revocation happens, so the
  refresh token stayed live for its remaining days.
- **Recovery was impossible.** `/auth/refresh` exists to be called *after* the access token dies,
  and its credential is the refresh cookie — but the expired access cookie travelling beside it
  killed the request first. A seven-day refresh token was unreachable from any client still holding
  the dead one, which on native is every client until the process restarts.
- **The rate limiter was bypassable**, and this is the one that changes a shipped decision.
  `RateLimitFilter` is a JAX-RS filter, so a request rejected before JAX-RS is never counted.
  Measured on the durable counter: three calls carrying a junk `zen_access_token` moved it by
  **0**; three identical calls without the cookie moved it by **3**. Attaching any junk value made
  a request unmetered on **every** endpoint while still occupying one of the 200 concurrency slots
  that are the entire capacity of the service.

### Decision

- **`SessionCookieAuthenticationMechanism`** (zen-identity) wraps Quarkus's `JWTAuthMechanism` as an
  `@Alternative @Priority(1)` bean and recovers an authentication *failure* into **no identity**.
  The request proceeds as anonymous. Everything else — challenge, credential types, transport — is
  delegated unchanged.
- **It fails closed.** Recovery yields no identity, never a partial or assumed one, so
  `@Authenticated` and `@RolesAllowed` still answer 401 through the delegated challenge and
  `RoleAugmentor` has nothing to augment. What changes is *when* the 401 is decided and *by whom* —
  the route, on its own terms, rather than the transport layer on everyone's. Refusing later is not
  refusing less.
- **The CSRF check keys on the identity, not on a cookie being present.** Forgery rides on an
  ambient credential the server *accepts*; a request it does not accept has nothing to forge with.
  The earlier rule — enforce when the access cookie is present — was only safe because an
  unverifiable cookie 401'd first, and would now answer 403 to a client whose session had merely
  aged out, with no way to clear it (the CSRF cookie expires alongside the access token). Signing
  out would have been impossible for exactly the sessions that most need to end.
- **The client renews and replays.** `ZenClient.recoverSession` is an optional callback: on a 401 it
  runs once, and on success the request is replayed once. Safe because a 401 is decided before the
  resource runs, so the original had no effect to repeat. Concurrent 401s **join** one in-flight
  attempt rather than each starting their own — the refresh endpoint sits in the limiter's
  credential bucket at 10/min, so a client recovering in parallel would throttle itself out of
  recovering. The callback's own requests are excluded by the `Zone` they run in, not by "is an
  attempt in progress", because those two look identical from outside.

### What was rejected, and why

- **`quarkus.http.auth.proactive=false`** — the documented lever, and far broader: it changes the
  posture of every route at once. It also **does not fix this**, because any `@PermitAll` route that
  touches `SecurityIdentity` (`AuthResource` does) forces the same failure lazily.
- **A path-scoped `quarkus.http.auth.permission.<n>.policy=permit`** — measured, and it does not
  suppress the challenge. Config alone cannot fix this.

### What this supersedes, and why

- **"Coverage is three buckets … and everything else under `/api/`"** (ADR-029, Consequence) →
  **corrected.** *Why:* it described the buckets accurately and the coverage optimistically. Any
  request carrying an unverifiable session cookie reached none of them, so the limiter shipped with
  a one-cookie opt-out. `RateLimitFilter`'s own javadoc already stated the intended rule — "the 429
  is charged before authentication, not after" — and this is what makes it true.
- **"proactive=false so login and register are not 401'd before it runs"** (`application.properties`,
  the JWT block) → **refined.** *Why:* the comment names proactive auth's blast radius correctly but
  treats it as a property of a hypothetical packed-cookie future. It is a property of *today's*
  cookie path, and the narrow fix is one credential source reclassified rather than the whole
  posture inverted.

### Consequence

- An expired session now behaves the way a client can act on: 401 on the routes that need a user,
  204 from the identity probe, and a refresh that works. The seven-day refresh token is reachable
  for the first time on the web at all.
- Enforcement widened where it should: an authenticated mutation without a CSRF token is refused
  even when the caller never presented a cookie. `AdminUserResourceTest.update_persistsEditableFields`
  was updated to send the pair the real panel sends, and a new
  `update_withoutTheCsrfToken_isRefused` asserts the omission is refused and writes nothing —
  the assertion is stronger than the one it replaced, not weaker.
- Verified green: `task test` (102 backend tests including the bean-discovery guard, the
  dead-cookie behaviour in both directions, and the limiter counting a dead-cookie request;
  every client suite; the live e2e gate at 16 tests, three of which drive an unverifiable cookie
  against a real provider-issued session), `task test:client:matrix` under dart2js **and**
  dart2wasm, `task test:admin`, `task verify:docs`.
- The mechanism lives in a Jandex-indexed module and is therefore silent if lost.
  `ExpiredSessionCookieTest` resolves it from the `BeanManager` for the same reason
  `RateLimitWiringTest` resolves the limiter: without the index the default returns, and nothing
  else would say so.

---

## ADR-029 — The rate limiter is two tiers: in-memory burst, PostgreSQL for anything that outlives a process

**Date:** 2026-08-03. **Status:** accepted. **Supersedes:** STANDARDS "Deployment model", the
bullet *"One instance makes in-process state valid"*. **Refines:** ADR-027 (the perimeter),
ADR-028 (what each capacity knob invalidates), ADR-020 (the max-instances trigger).

### Context

A security audit found the backend had no rate limiting anywhere
(`docs/plans/SECURITY-REMEDIATION.md`, F1). ADR-027 already accepted that the perimeter is the
application's own limiter and nothing else, so this is the component that decision was resting on.

The obvious place to put counters is memory, and STANDARDS said so in as many words:

> **One instance makes in-process state valid.** Because at most one instance ever runs, in-process
> state — rate limiting, in-memory caches, login-attempt counters — is correct by construction.
> […] **The trigger to externalize state (Postgres/Redis) is the decision to raise
> `--max-instances` above 1**.

That is right about sharing and **wrong about lifetime**, and the second half is what a rate
limiter depends on. ADR-027's measurement is the evidence: under `--min-instances=0` the container
exists only while it is serving, and the live service's process is replaced **about every hour** —
zen_demo's only recurring traffic is one scheduler tick an hour, so it starts, serves, and scales
back to zero, twenty-four times a day.

A login counter with a one-hour window, held in memory, therefore resets itself roughly as often as
an attacker fills it. It is not weakened by scale-to-zero; it is *defeated* by it, silently, while
looking exactly like a working control. Raising `--max-instances` was never the trigger for that
one — `--min-instances=0` already was, and STANDARDS stated the very same constraint correctly one
bullet later for *scheduling* ("Scale-to-zero makes in-process scheduling invalid") without
carrying it to counters.

### Decision

- **Two tiers, split on how long the window is.**
  - **Burst — in memory.** Fixed windows, second- to minute-scale. Valid because at most one
    instance runs, and valid *in time* because a window shorter than the process's life is one the
    attacker's own traffic keeps alive: the flood that would exceed it is what stops the instance
    scaling to zero.
  - **Durable — PostgreSQL.** Hour-scale windows, in a Flyway-migrated table
    (`zen_rate_limit_counters`, `V200`, band 200-299 claimed for `zen-ratelimit`). Incremented with
    a single `INSERT … ON CONFLICT DO UPDATE … RETURNING`, because a read-then-write is a lost
    update and a rate limiter that loses updates has whatever limit concurrency happens to produce.
- **Redis rejected.** Memorystore has no free tier (~$35/month floor); Upstash adds a vendor, a
  secret, a network hop and a failure mode. Postgres is already provisioned, already under Flyway,
  already migrated at start, and costs $0 incrementally. The application cannot serve an
  authenticated request without it anyway, since roles are loaded from the `users` table on every
  one — so it adds no new dependency, only a new table.
- **The client address is resolved by counting `X-Forwarded-For` from the right**, by a configured
  number of trusted hops (`zen.ratelimit.forwarded-hops`, default **0** = ignore the header
  entirely). The conventional leftmost reading — which is what `quarkus.http.proxy.allow-x-forwarded`
  does — is attacker input, because a proxy appends rather than replaces. `%prod` sets 1: Cloud Run
  is itself a proxy and its frontend appends the real peer. **An edge in front of Cloud Run changes
  this number**, which is one more thing ADR-027's "no edge" position is holding up.
- **Two guards, because all three failure modes here are silent.**
  `RateLimitAddressGuard` refuses to boot when `proxy-address-forwarding` and `forwarded-hops`
  contradict each other (either pairing throttles nobody). `RateLimitWiringTest` resolves the
  filter from the `BeanManager`, so losing `jandex-maven-plugin` from the module fails the build
  rather than producing a limiter that permits everything.
- **Cleanup is a `zen-jobs` `ZenJob`, never `@Scheduled`** — the rule this ADR is restating, applied
  to itself.
- **Production limits are the framework's defaults**, shipped in the module's
  `META-INF/microprofile-config.properties`. `%dev` and `%test` deliberately run looser ones, and
  the reason is recorded next to them: a suite drives hundreds of requests from `127.0.0.1` in
  seconds, so production values would test the limiter instead of the endpoint. `%dev` needs looser
  *durable* limits for a further reason `%test` does not have — it points at the persistent local
  Postgres, so an hour-scale counter accumulates across every `task test:e2e` run in that hour.
  Enforcement is not taken on trust: `RateLimitEnforcementTest` boots its own `@TestProfile` with
  deliberately tiny limits and asserts a real 429.

### What this supersedes, and why

- **"One instance makes in-process state valid […] The trigger to externalize state
  (Postgres/Redis) is the decision to raise `--max-instances` above 1"** (STANDARDS "Deployment
  model") → **refined, and one constraint added.** *Why:* it names one of two constraints.
  `--max-instances > 1` governs whether state is *shared*; `--min-instances = 0` governs whether it
  *survives*, and only the second is measurable — ADR-027 measured it. The corrected rule is that
  the state's window decides where it lives: minute-scale in memory, hour-scale in Postgres. The
  original claim stays true for caches and for `JobScheduler`'s overlap flag, which only has to
  outlive a tick.
- **"Rate limiting" as an example of valid in-process state** (same bullet) → **split.** *Why:* it
  was the one example in that list where the lifetime constraint bites, and it was leading by
  example toward a limiter that could not work.

### Consequence

- `zen-ratelimit` is the sixth framework library and claims Flyway band **200-299**; STANDARDS
  "Database migrations" updated. The next library takes 300-399.
- Coverage is three buckets, tightest first: `POST /api/v1/jobs/trigger` (20/hour durable — its
  real caller is one Cloud Scheduler entry once an hour, and a successful call anonymises
  accounts), the credential-bearing auth endpoints (10/min, 100/hour), and everything else under
  `/api/` (120/min burst only — below the ~3.3 req/s that saturates all 200 slots per ADR-027,
  and far above any real client).
- The counter table stores a **salted hash** of the address, never the address: an IP is personal
  data under GDPR Recital 30 and the limiter only ever needs equality.
- ADR-027's residual risk is unchanged. This closes the single-source attack; a distributed one
  still saturates 200 slots, and that remains accepted rather than closed.
- Verified green: the app's `@QuarkusTest` suite (80 tests, including the 429 enforcement proof and
  the bean-discovery guard), `zen-ratelimit`'s own 31 unit tests, and the live `task test:e2e` gate.
  One existing assertion changed and was made *stronger*, not weaker:
  `JobTriggerResourceTest` asserted `due == 1`, which encoded "this application has exactly one
  job"; it now identifies the retention job by id among the due runs and additionally asserts that
  nothing failed.

---

## ADR-028 — Deployment capacity is the application's choice: the framework ships defaults, not constants

**Date:** 2026-08-03. **Status:** accepted. **Refines:** ADR-027, ADR-020, ADR-001 (the
framework/application boundary).

### Context

`Taskfile.yml`'s `deploy:cloudrun` writes `--memory=256Mi --cpu=1 --min-instances=0
--max-instances=1 --concurrency=200 --timeout=300s` as **literals**, while `GCP_PROJECT`,
`GCP_REGION`, `SERVICE_NAME` and `AR_REPO` sitting a thousand lines above are overridable `vars`.

The repository root is language-neutral and framework-level; `zen_demo` is the only application
today, not the only application there will be. So the framework's orchestrator currently fixes one
particular application's capacity envelope for every application that will ever use it. That is a
layering defect by the repository's own rules, and it is invisible precisely because there is only
one app to notice it.

It also quietly misrepresents ADR-020 and ADR-027, both of which read as though `--max-instances=1`
were a property of *jZen* when it is a property of *zen_demo's deployment*.

### Decision

- The capacity parameters become `vars` with **today's values as defaults**. jZen's own posture is
  unchanged: `zen_demo` still deploys at 256Mi / 1 CPU / min 0 / max 1 / concurrency 200.
- An application may override them. Concretely, an operator willing to pay for it may deploy at
  `--min-instances=1 --max-instances=10`, and the framework must not stand in the way.
- The framework's obligation in exchange is to say **what each knob invalidates**, next to the knob
  and not only here. A framework that lets an operator raise `--max-instances` without telling them
  what it breaks is a trap, and the things it breaks fail silently.

### What each knob costs

- **`--max-instances > 1`** invalidates three pieces of in-process state, none of which fails loudly:
  1. **The burst tier of the rate limiter.** N instances keep N independent counters, so the
     effective limit is N× the configured one.
  2. **`JobScheduler`'s overlap guard.** The `AtomicBoolean ticking` flag is per-instance, so two
     instances can run the same tick concurrently. `JobScheduler`'s own javadoc already names the
     remedy — a Postgres advisory lock — and ADR-020 already names the trigger. Worth stating the
     stakes plainly, because the tick runs retention: concurrent ticks mean concurrent **account
     anonymisation**. The retention queries exclude already-anonymised rows, so the operation is
     idempotent and the damage is bounded, but that is a property to verify rather than assume.
  3. **Any in-memory cache**, which diverges per instance.

  The **durable** tier of the rate limiter is unaffected: it lives in Postgres precisely so that it
  depends neither on how many instances run nor on any one of them surviving. The second half of
  that is measured rather than assumed — under `--min-instances=0` the live service's process is
  replaced every hour (ADR-027), so a counter whose window outlives an hour cannot be held in
  memory at all, whatever `--max-instances` says.
- **`--min-instances ≥ 1`** is the opposite axis and invalidates nothing. It removes cold starts and
  would make an in-process `@Scheduled` viable again — but `zen-jobs` stays correct either way, so
  there is no reason to undo it. Paying for a warm instance buys latency, not a simpler
  architecture. **What it buys is now measured** (ADR-027): a cold request costs 2.9–4.8s against
  26ms warm, and in `zen_demo`'s deployment the instance is cold for practically every real
  visitor, because the only recurring traffic is one scheduler tick an hour.
- **`--concurrency` and `--timeout`** carry no invariant at all. They are capacity and latency
  trade-offs, and `--timeout` is additionally a denial-of-service lever (ADR-027).

### What this supersedes, and why

- **The literal capacity flags in `deploy:cloudrun`** → **replaced by defaults.** *Why:* a framework
  whose orchestrator hardcodes one application's cost envelope has stopped being a framework at that
  line. The values were right for `zen_demo`; being right for one app is not a reason to be
  mandatory for all of them.
- **"`--max-instances=1` stays valid for the MVP, with the documented trigger unchanged"** (ADR-020,
  Consequence) → **reframed, not reversed.** *Why:* the trigger is unchanged and still correct. What
  changes is whose decision it is — the application's, not the framework's — and that the framework
  now has to publish the consequences instead of assuming a single deployment reads the ADR.

### Consequence

- Defaults are unchanged, so ADR-027's acceptance of the 200-slot ceiling still describes what
  `zen_demo` actually runs. An application that raises the ceiling opts out of ADR-027's reasoning
  along with its cost floor.
- `deploy:cloudrun`'s summary is where the knob-by-knob consequences above belong, because that is
  what an operator reads before changing them.

---

## ADR-027 — The 200-slot ceiling is accepted: the perimeter stays inside the application, and what would move it

**Date:** 2026-08-03. **Status:** accepted. **Refines:** ADR-020 (the `--max-instances=1` trigger),
STANDARDS "Deployment model".

### Context

A security audit of the whole surface (`docs/plans/SECURITY-REMEDIATION.md`) found that the backend
has no rate limiting at all, and that the deployment shape makes denial of service cheap. Two
numbers carry the argument:

- `--concurrency=200` on `--max-instances=1` means 200 concurrent requests is the entire capacity of
  the service, and by design that capacity cannot grow.
- `--timeout=300s` means holding all 200 slots costs an attacker `200 / 300` = **0.67 requests per
  second**. One slow connection. No botnet, no load.

The second number is a configuration mistake and is fixed. The first is not a mistake — it is the
cost floor working as intended — and it cannot be configured away.

### Measured on the live service

Taken 2026-08-03 against `zen-demo-server` revision `00013-qw9` in `jzen-prod`, from Cloud Run
request logs and browser Navigation Timing. This ADR rests on these numbers rather than on estimates.

| | Measured | Samples |
|---|---|---|
| Cold request, end to end | 2.9–4.8s, mean **3.7s** | 12 |
| — of which Quarkus native boot | 2.6–3.3s, mean 3.0s | 15 |
| Warm request, time to first byte | **26ms** | 1 |
| Deployed flags | concurrency 200, timeout 300s, min 0, max 1, 256Mi / 1 CPU | — |

Two findings came out of the measurement that reasoning had not produced:

- **The service is almost never warm.** Its only recurring traffic is the hourly Cloud Scheduler
  tick, so the container starts, serves one request and scales back to zero — 24 cold starts a day,
  and a visitor arriving between ticks pays the full 3.7s.
- **The heaviest operation takes about 0.7s of actual work.** The hourly trigger completes in 3.7s
  *including* the 3.0s boot, which is what makes a 60s timeout generous rather than a guess.

### Decision

1. **The application closes what it can.** Lower `--timeout` to roughly 60s — the measurement above
   shows the only long-running operation needs under a second — and add the rate limiter. Together
   these raise the single-source cost about fivefold and put the remaining 3.3 req/s within reach of
   a per-address limiter.
2. **The residual is accepted, not closed.** A distributed attack from a pool of addresses still
   saturates 200 slots, and nothing in the application can prevent that.
3. **No edge is introduced.** jZen continues to serve Cloud Run directly.

### What was rejected, and why

- **Cloud Armor** → **rejected on cost.** It cannot attach to Cloud Run directly; it requires a
  Global External Application Load Balancer in front. The floor is roughly **$25–30/month before a
  single request** (ALB forwarding rule ~$18/mo, policy $5/mo, $1/mo per rule). *Why this is
  consistent rather than a compromise:* the same cost discipline that produced `--max-instances=1`
  and `--min-instances=0` cannot then buy a $30/month appliance to defend them.
- **Cloudflare's free tier** → **deferred on invariants, not on price.** It is $0, and a domain is
  already on the critical path for App Links and email deliverability, so it adds no money either.
  It is deferred because **two written constraints depend on there being no edge**: STANDARDS
  "Deployment model" (an edge that strips or renames cookies breaks the entire auth path, since the
  session is a normally-named cookie SmallRye JWT parses directly) and `WellKnownResource` (the
  `.well-known` association files must not be rewritten and must not redirect — and a *failed* App
  Links verification is cached by both Android and iOS, which is painful to recover from).
  Free-tier Bot Fight Mode, which injects a JavaScript challenge, would break every API client
  outright. One wrong toggle in a third-party panel breaks two invariants at once.

### Why acceptance is a position rather than negligence

`--max-instances=1` is simultaneously the vulnerability and its own fuse. Because at most one
instance ever runs, an attack cannot produce a surprise bill: **it costs availability, not money.**
That asymmetry is what makes accepting the residual an engineering judgement instead of an omission
— the blast radius is bounded by the same constraint that creates the exposure.

### The trigger

Revisit on **observed abuse**, not on a date and not pre-emptively. In that order:

1. **Cloudflare free**, gated on verifying that cookies and `.well-known` paths pass through
   untouched and that Bot Fight Mode is off. It needs its own ADR, because it amends two invariants
   this one is preserving.
2. **Raising `--max-instances`**, which ADR-020 already names as the trigger that forces in-process
   state out to Postgres or Redis.

### Consequence

- The perimeter is the application's own rate limiter and nothing else. There is no network-level
  protection in front of jZen, and that is a chosen position, recorded here so it is not later
  mistaken for an oversight.
- `docs/plans/SECURITY-REMEDIATION.md` carries the execution and is disposable once executed. This
  entry carries the reasoning and is not.

---

## ADR-026 — A second product consumes jZen from a sibling checkout: one Maven aggregator, path dependencies everywhere else

**Date:** 2026-08-02. **Status:** accepted. **Refines:** ADR-020 (backlog item 1's trigger).

### Context

The second product (ROADMAP step 4) lives in its **own repository**, which is what makes it an
honest test of the framework/application boundary — `zen_demo` cannot be, because it was written
alongside the framework and an awkward API gets fixed in the same commit that revealed it.

But a separate repository cannot use the `path:` dependencies and `<relativePath>` parents that
`zen_demo` relies on, and publishing every iteration is exactly the tax ADR-020 postponed
publishing to avoid. The question is how a sibling checkout consumes an unpublished framework.

Both repositories are cloned side by side under a plain working folder:

```
workspace/
  pom.xml          jzen/          <product>/
```

### Decision, and what was measured rather than assumed

- **Maven: a root aggregator POM.** It lists `jzen/server` and `<product>/<product>_server` as
  modules, so both build in one reactor and the product resolves `zen-core` from it directly. The
  product's server keeps `zen-parent` as its parent with a `<relativePath>` into `jzen/`, exactly
  as `zen_demo_server` already does across directories. **Verified:** a probe module compiled
  against `zen.core.http.ZenStatus` with `BUILD SUCCESS`, no `~/.m2` install and no registry.

  This is required rather than chosen. Maven has **no path dependencies and no git dependencies** —
  `<relativePath>` resolves a *parent POM*, never a dependency — so of the three ecosystems only
  Java cannot manage on its own.

- **Dart: plain `path:` dependencies, package by package.** **Verified** that a package outside
  jZen's workspaces resolves `path: ../jzen/client/zen_core` cleanly, and that a git dependency
  with a `path:` subdirectory works too. `resolution: workspace` does not obstruct an external
  consumer, which was the open worry.

- **TypeScript: the existing source alias**, or an outer `pnpm-workspace.yaml`. jZen declares no
  pnpm workspace at all, so nothing conflicts.

- **No root `pubspec.yaml`.** Two variants were built and both *worked*, and both were rejected:

  1. *An outer Dart workspace over jZen's* is impossible without adding `resolution: workspace` to
     `client/pubspec.yaml` and `apps/pubspec.yaml` — which **breaks jZen standalone**, verified:
     a member with no root above it fails with *"found no workspace root including it"*. The
     framework would resolve only from inside one particular folder layout. Its own CI would fail.
  2. *A facade package re-exporting the framework* compiles, but changes every import in the
     product to `package:<facade>/…`, so the day the packages are published **every import
     changes**. A `path:` dependency leaves imports as `package:zen_core/…` — character for
     character what a published consumer writes — making that migration a pubspec edit with zero
     code churn.

  Importing a package transitively without declaring it also works, and is precisely what
  `depend_on_referenced_packages` exists to stop; the lint was confirmed to fire.

### The reason that is not mechanical

A facade would **erase the signal the second product exists to produce**. `import
'package:zen_identity/…'` says the product reached into identity; `import 'package:<facade>/…'`
says nothing. A product's dependency list naming five framework packages *is the finding* — the
real coupling surface, visible. One umbrella dependency hides it behind a name we invented.

The verbosity is therefore the feature, and it is also the exact dependency list that will be
published against.

### What this supersedes, and why

- **"The one thing that would force [publishing] earlier is a consumer in a *different
  repository*, since path dependencies do not reach across repos"** (ROADMAP, backlog item 1;
  ADR-020) → **refined, and it was half wrong.** Path dependencies reach across repositories
  perfectly well in **Dart**, and TypeScript needs no dependency edge at all. It is **Java** that
  cannot, and even Java is satisfied locally by the aggregator. So the trigger is not "a separate
  repository" but **"the second product gets its own CI"** — a lone clone has no sibling `jzen/`
  and no root POM, so the reactor is not there and the Java half must resolve from a registry.

### Consequence

The second product can start immediately, in its own repository, with no publishing at all, and
the framework stays buildable on its own. Publishing (backlog item 1) keeps its postponement and
gains a sharper trigger — **the product's first CI run, and Java first**.

That last point is itself the first signal from crossing the boundary, and it arrived before a line
of the product was written: the ecosystems disagree about what "depend on something unpublished"
means, and the framework's Java half is the one that will force the decision.

**Date:** 2026-08-01. **Status:** accepted. **Refines:** ADR-018, ADR-019, ADR-021. **Closes:** backlog item 8 (Android half).

### Context

`zendemo://auth-callback` is a private-use URI scheme, and RFC 8252 §8.6 is explicit that no
application can claim one exclusively — any app on the device may register the same string. That
would be a small matter if the link carried a one-time code. It does not: jZen uses the implicit
fragment flow (ADR-018), so the URL contains a live **access and refresh token**. An app that wins
the scheme race has the account, and every signal the victim can check says they are safe — they
requested the email, it came from the right sender, they followed their own link.

The server-side allowlist (ADR-019) does not help, and the reason is worth stating because it looks
like it should: it governs which return address may be **requested**, and the attacker requests
nothing. They listen for the address the real app already asked for.

### Decision

- **Serve the association files from the backend** — `GET /.well-known/assetlinks.json` and
  `GET /.well-known/apple-app-site-association` (no extension, as iOS requires), both
  `application/json`, both anonymous, neither redirecting. A `WellKnownResource` in `zen-identity`,
  framework-side like the rest of auth, with the values coming from configuration.
- **404 until configured, never an empty document.** Android and iOS both *cache* the outcome of
  verification, so a file that exists but does not name the app teaches the platform that the
  association **failed**. Absent is a state they retry from cleanly; wrong is not. This is why the
  `verify:deploy` assertion fails on a malformed file but merely reports an absent one.
- **The values are public, so they are environment variables, not secrets.** The server serves them
  to anyone who asks — that *is* the mechanism. Putting them in Secret Manager would imply a
  confidentiality they do not have and cannot enforce.
- **Android gets an `autoVerify` https intent-filter beside the custom-scheme one.** Both, not
  either: the scheme is what makes a local run work with no domain and no signing, and it is what a
  developer replays from the terminal. The https filter is what a deployed environment mails.
- **The host is a manifest placeholder, not a literal** (`-Pzen-applinks-host=…`), defaulting to
  `applinks.invalid` — a reserved TLD (RFC 2606) that can never resolve. An environment fact
  baked into the manifest would outlive the environment it names, and `destroy:cloudrun` cannot
  edit the repository (STANDARDS "Deployment model"). A manifest placeholder cannot be empty, so
  the default had to be a host that exists syntactically and can never match.
- **Every signing certificate is listed, not just the release key.** A debug keystore signs the
  build a developer actually installs; a build signed by an unlisted key fails verification with no
  error anyone sees.

### iOS is deliberately not finished, and not for a technical reason

The server half is done — configure `APPLINKS_APPLE_APP_IDS` and the file is served. The app half
needs the **Associated Domains** capability, which Apple grants only to a **paid Developer Program
membership**; free provisioning cannot sign it. Adding the entitlement now would break every iOS
build on a machine without that membership, which is exactly the trap the macOS Keychain
entitlement sprang earlier (ADR-023): an entitlement that requires signing turns a working build
into `"entitlements that require signing with a development certificate"`.

So the entitlement is **not** added. The custom scheme continues to serve iOS, and the remaining
step is one entitlement plus one config value on the day a paid membership exists.

### What this supersedes, and why

- **"Blocked on signing identities, so it sits with item 6"** (ROADMAP, backlog item 8) →
  **split.** True for iOS, false for Android: an App Link is verified against the SHA-256 of
  whatever key signed the build, and a *debug keystore* is a perfectly good key to list. The
  Android half needs no paid account, no store, and no release signing — so it was never actually
  blocked, and treating the item as one indivisible thing is what kept it closed.

### Consequence

The hijack is closed on Android for any environment that configures it, and the mechanism is in
place for iOS. What remains true, and is the reason both filters stay: **a deployment that has not
adopted App Links is not broken**, it is simply back to the custom scheme with its known weakness.
Retiring the scheme in production is a configuration change (`AUTH_REDIRECT_URIS`), not a code one.

Verified: `WellKnownResourceTest` + `WellKnownResourceConfiguredTest` cover both sides of
"configured" — 404 when unset, and the exact documents the platforms parse, served as JSON, without
redirect, anonymously, and with the Apple file refusing a `.json` suffix. `task test:apps:server`
72/72. The Android build produces both intent-filters, confirmed by dumping the manifest out of the
built APK; the default placeholder and a real host both build. The served `assetlinks.json` was
fetched from a running backend and matches Digital Asset Links byte for byte. `verify:deploy`
against the live service correctly reports the association as *not adopted* rather than failing,
because that environment has not been redeployed with the values yet.

**Date:** 2026-07-31. **Status:** accepted. **Refines:** ADR-016, ADR-023.

### Context

Adding `flutter_secure_storage` for native session persistence (ADR-023) **broke the web build
entirely**, and nothing found it until `deploy:cloudrun` ran `build:web`:

```
Target dart2wasm failed:
  flutter_secure_storage_web-1.2.1/lib/flutter_secure_storage_web.dart:5:8:
  Error: Dart library 'dart:html' is not available on this platform.
  main.dart => web_plugin_registrant.dart => package:flutter_secure_storage_web => dart:html
```

Two facts collide. jZen delivers the web app as **WebAssembly** (ADR-016), and dart2wasm has no
`dart:html`, `dart:js_util` or `package:js`. And a Flutter web build compiles a **generated
`web_plugin_registrant.dart` that imports every web plugin in the dependency graph**, whether the
application calls it or not.

The consequence is worth stating plainly, because it defeated a guard that looked sufficient:
**`zenIsWeb ? null : SecureTokenStore()` does not help.** The value is never constructed on web,
the constant folds away, and the build still fails — the plugin is reached through the registrant,
not through jZen's code. The same is true of any conditional import. A pubspec dependency is
unconditional, and plugin registration is downstream of every mechanism jZen has for saying
"not on this platform".

### Decision

- **Any Flutter plugin entering a client or app package must be Wasm-clean**: its web
  implementation may not import `dart:html`, `dart:js_util` or `package:js`. `package:web` and
  `dart:js_interop` are the Wasm-compatible equivalents.
- **`flutter_secure_storage` is pinned to `^10.3.1` as a floor, not a preference.** 9.x is the
  `dart:html` implementation. The bound carries a comment saying so, because "upgrade blocked, pin
  it back" is an entirely reasonable-looking change that would silently un-ship the web app.
- **The Android `encryptedSharedPreferences` option is dropped** — deprecated in 10.x (Google
  deprecated the Jetpack Security library behind it), ignored when passed, and removed in 11. The
  plugin encrypts with its own ciphers and migrates existing data on first access.

### What this supersedes, and why

- **"Null on web is not a gap … the web session client ignores the store for exactly that
  reason"** (ADR-023's `main.dart` reasoning) → **refined.** The runtime reasoning was correct and
  is unchanged; what it did not cover is that a plugin costs something at *compile* time no
  runtime guard can refund. ADR-023 called the web dependency "dead weight on a bundle you
  deliberately optimize" — that was too generous. It is not weight, it is a build failure.
- **STANDARDS "Client config is compile-time"** → **extended**, not altered. Conditional imports
  and compile-time constants select jZen's *own* code. They have no authority over a plugin's
  generated registration, which is the gap this ADR names.

### Consequence

Verified: `flutter build web --wasm` compiles and stages the bundle (45M) after the upgrade, and
`task test:e2e`, `test:client`, `test:apps` and the native suites stay green — the keystore path on
iOS and Android is unaffected by the version change.

The lesson is the same shape as ADR-022's, one layer down: **the checks that pass are not evidence
about the thing they do not compile.** `task test` never builds the web bundle, so every suite was
green on a commit that could not produce a web app at all. The deploy caught it, which is the gate
working — but the cheap habit is to run `task build:web` after adding any Flutter dependency,
rather than to discover it while shipping.: the refresh token in the platform keystore, behind a port `zen_transport` cannot import

**Date:** 2026-07-31. **Status:** accepted. **Refines:** ADR-018, ADR-020, ADR-021.

### Context

A browser persists session cookies to disk for their `Max-Age`. Nothing did that on native, so
the jar was in-memory and **a native user signed in again on every launch** — a defect the web
flow could never surface, and one ADR-020 named in advance as MVP work ("cookie persistence").

Devices have exactly the right facility for this: Keychain on iOS/macOS, Keystore-backed storage
on Android. The reason it was not simply used is mechanical. Reaching it means a Flutter plugin,
which imports `package:flutter/services.dart`, which imports `dart:ui` — and **a `dart:ui` import
anywhere in the graph cannot be compiled by the Dart VM at all**. `dart test` fails while
*loading* such a file, called or not. `task test:e2e`, the release gate, is a plain `dart test`
process that imports `zen_transport`. Putting the keystore there would not degrade the gate, it
would end it. Verified directly rather than assumed: a probe test importing
`package:flutter/services.dart` fails to load under `dart test`.

Conditional imports do not solve it. They select *code*; a pubspec dependency is unconditional,
so a plugin behind `if (dart.library.io)` is still in the graph.

### Decision

- **`zen_transport` declares a `TokenStore` port** (pure Dart, three methods, one value) with an
  `InMemoryTokenStore` default that touches nothing. `createSessionClient({TokenStore? store})`.
- **`zen_secure_store`**, a new Flutter package, implements it over `flutter_secure_storage`. The
  app's `main` wires the two — the composition root is the one place allowed to know both.
- **Only the refresh token is persisted.** The access token stays in memory: an hour long and
  re-obtainable, so writing it down widens what sits at rest to save one round trip. This is a
  defence-in-depth judgement, *not* a rule from a standard, and is recorded as such. What is a
  rule: **OWASP MASVS-STORAGE-1** requires any persisted token to live in platform secure storage,
  which is what rules out the tempting app-support file. And because a native app is a public
  client, the **OAuth 2.0 Security BCP (RFC 9700)** wants refresh tokens rotated — Supabase issues
  a new one per refresh, and persisting on every arrival keeps the stored copy the live one.
- **Restore feeds `POST /auth/refresh`**, before the ordinary identity probe. The probe asks "is
  there an access token?", and on a native launch there is not — only a restored refresh cookie.
- **Expiry travels with the value**, so a token past its seven days is discarded rather than sent.
- **A keystore failure degrades to "no session", loudly.** It is a platform service and can
  refuse; a crash on launch would be the worse trade. Reported through `ZenLogger`, never hidden —
  "nothing to resume" is a real answer, not a swallowed failure.
- **`ZenSessionClient`**, a neutral return type, so the app can say `restore()` without naming
  `CookieJarClient`, which does not exist in a web build.

### macOS is the exception, and the boundary is the reason

**Session persistence does not work on macOS, deliberately.** A sandboxed macOS app reaches the
Keychain only with the `keychain-access-groups` entitlement, and Xcode refuses to sign that
without a development certificate: the build fails outright with *"entitlements that require
signing with a development certificate"*. The MVP's stated boundary is a local run with **no
signing identity** (ROADMAP "What the MVP is"), so requiring one would trade a session that
survives a restart for a macOS build that does not happen at all. The entitlement is therefore
absent and the failure is contained — the store reports nothing to restore and the session ends
with the process, exactly as before. A *distributed* macOS build is signed anyway (backlog item
6), which is the point at which this costs nothing.

### What this supersedes, and why

- **"The jar is a simple in-memory map keyed by cookie name, sufficient for a single-origin demo
  session"** (`session_client_io.dart`) → **reversed for the refresh token, kept for everything
  else.** "Sufficient for a demo" stopped being true when the demo became the MVP on real
  devices; a per-launch sign-in is not a rough edge on a phone, it is the product being unusable.
- **"Whatever the native targets break that the web never exercised … cookie persistence"**
  (ROADMAP, "What the MVP is") → **resolved**, and with a result the row did not anticipate: two
  of three native targets, with macOS blocked by a boundary the same document sets.
- **`zen_transport` as a pure-Dart package** → **reframed.** The value is not package purity, it
  is that the VM gate stays a plain process. Stated precisely because the imprecise version
  ("keep it framework-free") suggests the port could be dissolved by relaxing a preference, when
  in fact the toolchain forbids it.

### Consequence

Verified by running it, not only by testing it — a real dart:io backend, a real device keystore,
a real process restart, with the server's access log as the evidence:

| Target | Restart behaviour | Evidence |
|---|---|---|
| iOS Simulator | **Session survives** | `POST /api/v1/auth/refresh 200` on relaunch |
| Android emulator | **Session survives** | `POST /api/v1/auth/refresh 200` on relaunch |
| macOS (sandboxed, unsigned) | Signs in again, as before | `GET /api/v1/auth/identity 204` on relaunch |
| Web | Unchanged | the browser persists its own cookies; the store is ignored |

Suites: `zen_transport` 58 tests (13 new, covering persistence, rotation, expiry, corruption,
logout, and a keystore that refuses), `zen_secure_store` 5 (pinning the storage key, whose
renaming would silently sign every user out), `task test:e2e` 10/10 — the gate still compiles on
the VM, which is the design's own proof.

A note for whoever reads this next: the macOS row is a *finding*, not a defect to file. The
interesting part is that it was invisible to every test — the suites pass identically on all four
targets, and only launching the app twice tells them apart.

**Date:** 2026-07-31. **Status:** accepted. **Refines:** ADR-019, ADR-020, ADR-021.

### Context

MVP step 3 is "MVP live and tested on the real stack". The first thing testing the real stack found
was that **no native client can authenticate against it at all**. The deployed service refuses
`zendemo://auth-callback` with `400 invalid_redirect`:

```
$ curl -X POST $URL/api/v1/auth/restore-password \
    -d '{"email":"…","redirectUri":"zendemo://auth-callback"}'
invalid_redirect;That return address is not configured for this application.  HTTP 400
```

Nothing was broken. `auth.redirect-uris` is empty by default — deliberately, per ADR-019, because
an unchecked return address mails a live session token to a destination an attacker names — and
`deploy:cloudrun` never provisioned it. The native work of ADR-021 was verified locally, where the
value was passed by hand; the deployment contract was never taught it existed.

### Decision

- **`AUTH_REDIRECT_URIS` is part of the deployment contract**, not an optional extra: a fourteenth
  configuration secret in `deploy:cloudrun`'s one-time setup, and wired into `--set-secrets` so a
  deploy *fails* when it is absent rather than succeeding into a half-working environment.
- **`verify:deploy` asserts it against the real environment.** One `POST /restore-password` with a
  nonexistent user (the endpoint answers 204 regardless of whether the account exists, so it reads
  the allowlist and nothing else, and mails no one). A non-204 fails the task and prints the
  `gcloud secrets create` line that fixes it.
- **The assertion lives in `verify:deploy`, not the shared `verify:endpoints`.** It needs a real
  Supabase behind the service, which the `test:native` smoke container deliberately does not have —
  the same boundary that file already draws for anything needing real Supabase or SMTP.
- **Both gates are named together in the operator step.** They fail differently and only one is
  visible: the backend refuses an unlisted target with a 400, while GoTrue *silently drops* a target
  missing from the Supabase dashboard's Redirect URLs and falls back to the Site URL — the email
  arrives, the link opens the web app instead of the phone app, and nothing reports an error.
- **`RedirectTargetsTest` covers the additional-entries path**, which nothing did before.

### What this supersedes, and why

- **"`auth.redirect-uris` — additional permitted targets, comma-separated. Empty until an
  application ships a client that needs one, which is the safe default"** (`RedirectTargets`
  javadoc; ADR-019) → **refined, not reversed.** The default stays empty and exact matching stays
  exact; ADR-019's security reasoning is untouched and remains correct. What was missing is that
  *an application has now shipped such a client* (ADR-021), so the condition the safe default was
  waiting on has been met, and the deployment path had no way to express it.
- **"the thirteen configuration secrets"** and the teardown's **"all fourteen secrets"**
  (`Taskfile.yml`, `deploy:cloudrun` / `destroy:cloudrun` summaries) → **changed** to fourteen and
  fifteen. The counts are load-bearing: the setup block is what an operator works through, and the
  teardown claim is what "no orphans" is checked against.
- **"Verified on a simulator, emulator, or local macOS run"** (ROADMAP, backlog item 4) → **refined.**
  A local run verifies the *client*; it cannot verify the environment the client will actually talk
  to, because the value under test is supplied by hand at the point where it is later supplied by
  configuration. This is the general shape of the miss, and the reason the gate is a deploy-time
  assertion rather than another test.

### Consequence

The lesson generalizes past this one secret: **a security control that fails closed is a
deployment trap when its absence is indistinguishable from correct operation.** The empty allowlist
was right, the deploy omitting it was wrong, and no suite could see the difference — the image is
byte-identical either way, the web app is wholly unaffected, and every other assertion in
`verify:deploy` passed green on exactly the broken environment. The remedy is that the gate now
asserts *configuration*, not only code, against the real environment.

Verified: `verify:deploy` run against the live service reproduces the failure and exits non-zero,
with every other assertion green (both transport modes, the Wasm bundle, the admin panel).
`RedirectTargetsTest` 10/10, `task test:server` green, `task test:apps:server` 66/66,
`task test:client`, `task test:admin`, `task sync:contracts` and `task verify:docs` green, and
`task test:e2e` — the release gate, run for the first time across the native work — 10/10 against
real Supabase + Quarkus. The live environment itself is **still unfixed at the time of writing**:
creating the secret and redeploying are operator actions, and until they happen the deployed
service remains web-only in practice.

**Date:** 2026-07-29. **Status:** accepted. **Follows:** ADR-018, ADR-019, ADR-020.

### Decision

`zen_demo` now builds and runs on **macOS, the iOS Simulator and the Android emulator** as well as
the web, and an email link signs the user in on all of them. What that required, and what was
decided along the way:

- **A custom scheme, `zendemo://auth-callback`,** registered in `CFBundleURLTypes` (iOS, macOS) and
  a `BROWSABLE` `intent-filter` (Android). Not Universal Links or App Links: those need a domain
  serving a verification file plus a Team ID, which is a paid account and a domain commitment, and
  they prove nothing the scheme does not. Revisit only if a link must survive being opened by a
  browser that refuses custom schemes.
- **Delivery belongs to the application, consumption to the framework.** `AuthDeepLinks` (in the
  app, `app_links` behind a conditional import so the web bundle never sees it) hands a `Uri` to
  `IdentitySessionStore.consumeAuthLink`. The framework names no plugin and no platform.
- **A cold start is not a warm arrival**, and both are handled. Off the web `Uri.base` is a file
  path, so the launch URL is invisible to the startup path and must be fetched and replayed.
- **One link is one sign-in.** iOS delivers a launch URL as the initial link *and* replays it on
  the stream; a cold start spent the same token three times before this was fixed in the framework.
- **The Java version stays aligned across the product; only the Android distribution differs.**
  AGP's `jdkImage` transform shells out to `jlink`, which fails on **GraalVM at every version**
  (17, 21 and 25 alike). A standard Java 25 (Temurin) builds Android cleanly, so jZen does not
  split its Java version: server and Android are both 25.

### What this supersedes, and why

- **"`zen_demo_client` has no native runners at all (only `web/`), so there is no manifest to
  register a scheme in"** (ROADMAP item 4; ADR-019 Consequence) → **resolved.** *Why:* the runners
  now exist, the scheme is registered, and the flow is verified cold and warm on three targets.
- **"Native release pipelines … a mobile MVP does not touch this item"** (ADR-020) → **confirmed by
  doing it.** *Why:* worth recording as evidence rather than prediction — the whole native surface
  was built and verified with no developer account, no signing identity, and no store.
- **An earlier claim of mine that "AGP does not support Java 22+"** (written into `run:demo:native`
  and the READMEs before it was tested) → **withdrawn.** *Why:* it was inference from the GraalVM
  failures, not a result. Temurin 25 was then tried and built Android in 28 seconds. The guard now
  rejects GraalVM only, which is what the evidence supports.

### Consequence

- Four defects that only a real run could surface, each now fixed and documented in ROADMAP: the
  missing macOS `network.client` entitlement (a sandboxed app silently cannot reach any backend),
  the triple sign-in, the GraalVM/`jlink` collision, and two broken toolchain installs (a missing
  iOS simulator runtime; a truncated `android-36` system image with no `system.img`).
- `task run:demo:native` runs the app on any native target and refuses a GraalVM JDK up front.
  It cannot *fix* the JDK: Flutter's `--jdk-dir` is machine-wide and outranks `JAVA_HOME`,
  `GRADLE_OPTS` and `org.gradle.java.home`, all of which were tried. A task that pretended
  otherwise would be lying, so it checks and explains instead.
- Icons and copyright are the product's, not `flutter create`'s defaults: every launcher icon is
  generated from `jZenLogo*.svg`, and `PRODUCT_COPYRIGHT` names **jLogic Software**. `dev.jzen`
  remains what it always was — the identifier namespace, not the copyright holder.
- **Verified green:** `task test:apps:server` 66 tests, `task test:client`, `task test:admin`,
  `task sync:contracts` ("Contracts in sync"), `task verify:docs`. Deep links proven on all three
  native targets, cold and warm, with one exchange per link. `task test:e2e` was *not* run — the
  local Supabase stack's port is held by an unrelated project.

---

## ADR-020 — The POC is done and the MVP is not: the order after the POC, and three triggers that move

**Date:** 2026-07-28. **Status:** accepted. **Follows:** ADR-015.

### Decision

The POC named in ADR-015 is delivered and live (backend, Wasm web app, admin panel, same-origin,
image `bc488f0`). The next goal is an **MVP** — the product actually usable, with mobile and
desktop clients beside the web one — and it runs on the same infrastructure. Three consequences,
each of which contradicts something already written down:

1. **Teardown waits for the MVP, not the POC.** Two conditions, both required: nothing is being
   tested on the environment, and no data on it still matters. Once real users exist the second
   condition acquires legal weight a POC teardown never had.
2. **Publishing waits for the second product.** Not for CI, and not for a date.
3. **Native release pipelines leave the critical path.** "Mobile and desktop" here means a
   simulator, an emulator, and a local macOS run — none of which needs a paid developer account or
   a signing identity. Item 6 begins only if something is distributed to another machine.

### What this supersedes, and why

- **"Run `destroy:cloudrun` after the POC … run once the POC has been shown"** (ROADMAP, open
  backlog item 5) → **trigger reversed.** *Why:* the MVP is built on the same stack, so tearing
  down after the POC demolishes what the next milestone runs on. The reason teardown was scheduled
  early — that a proving run should not outlive its proof — still holds; it is simply the MVP that
  is now the proof. Worth stating plainly because the inverse is tempting and wrong: **teardown is
  never a prerequisite to testing.** Testing needs the environment teardown removes. What makes
  teardown safe when it does come is that the environment is reproducible from this repo — Flyway
  owns the schema, `deploy:cloudrun`'s summary documents the one-time setup and every secret — and
  what is *not* reproducible is data and the Supabase project ref.
- **"Publish the packages … Also gated on 6 [CI]"** (ROADMAP, delivery order item 7; backlog
  item 1) → **regated.** *Why:* CI was never the real constraint. While the framework's only
  consumer is a reference app written by its own authors, an awkward API is fixed in one commit
  across both sides and never felt — so `zen_demo` cannot falsify the framework/application
  boundary that ADR-001 draws. A second, different product can, and will want the API changed.
  Publishing first freezes an API about to be bent, and it is the only irreversible step in the
  plan: a published version is retractable, never removable. The one condition that would force it
  earlier is a consumer in a *different repository*, since path dependencies do not reach across
  repos.
- **"Native release pipelines … filed against an app when one ships"** (ROADMAP, "Two items are
  declarations") → **refined, and moved further out.** *Why:* the wording implied that a native
  client implies the pipeline. It does not. Running on a simulator or locally needs nothing paid;
  only distribution does. An earlier reading of this — that a mobile MVP means starting developer
  enrolment now — was wrong and is corrected here rather than left in the conversation.

### Consequence

- The post-POC order, recorded in ROADMAP: MVP scope written down → native deep-linking (backlog
  item 4's per-platform half, on simulator/local) → MVP live and tested → **second product** →
  publish → native pipelines *if ever* → teardown last.
- Backlog item 4 is verifiable **without a paid account and without email**: a token from one real
  confirmation mail can be replayed through `simctl openurl` / `adb` / `open`, which also confirms
  the custom-scheme choice over Universal/App Links for the first pass.
- Two known checks that belong to the MVP, not to the framework as it stands: the auth path assumes
  *"jZen serves Cloud Run directly, same-origin, browser cookies"* (STANDARDS "Deployment model"),
  and a native client is a different HTTP client — cookie persistence, `CORS_ORIGINS`, and
  `SameSite` need verifying on a running native build rather than assumed. And `--max-instances=1`
  stays valid for the MVP, with the documented trigger unchanged: raising it above 1 is what
  forces in-process state (rate limiting, caches) out to Postgres or Redis.
- Nothing in this ADR changes what the POC was. ADR-015's delivery order stands as the record of
  how it was reached; this supersedes only its tail.

---

## ADR-019 — A client may name where its email link returns to, and the server permits it only by exact match

**Date:** 2026-07-28. **Status:** accepted. **Follows:** ADR-018.

### Decision

One backend serves every client an application has. A web client is reachable at the origin that
served it — which is exactly the address the server already holds in `auth.redirect-uri` — but a
native build is reachable only through its own scheme, and no server-side default can name it. So
the client may **ask** for a return address, and the server decides:

- `RegisterRequest.redirect_uri` and `RestorePasswordRequest.redirect_uri` (both optional). Empty
  means "the server's default", which is what every web build sends.
- `RedirectTargets` (`zen-identity`) resolves the request against `auth.redirect-uri` plus the
  comma-separated `auth.redirect-uris`, **empty by default**. The default is a member of its own
  allowlist, so naming it explicitly is permitted.
- **Exact match, and nothing else.** Not a prefix, not a host check. `zen://auth` as a prefix also
  admits `zen://auth.evil.example`; a host check on `app.example.com` says nothing about the path
  a token lands on. Exact match has no such edges — a new client is one configuration entry, added
  by a person, once.
- A rejection is a 400 `invalid_redirect` that **does not echo the refused value**: it is untrusted
  text on its way into logs and a client-facing message, and the caller already knows what it sent.
- The check runs **before** Supabase is called, so a refused address sends no email at all.
- Client side, the request is compile-time: `ZEN_AUTH_REDIRECT_URI` (empty by default), matching
  every other client setting. `IdentitySessionStore.consumeAuthLink(Uri)` handles a link that
  arrives while the app is already running — the native case, where the OS hands a URL to a live
  app rather than starting it with one.

**Why the allowlist and not simply trusting the client:** the email Supabase sends carries a live
session token in the link's fragment. A return address taken on trust would let anyone request a
token for *someone else's* account and have it delivered to a destination they control — the victim
need only click a genuine email from their real provider. For recovery it is worse than a leak: a
recovery link can set a password, so it is an account takeover. This is the single most dangerous
input in the auth surface, which is why it gets the strictest possible check.

### What this supersedes, and why

- **`auth.redirect-uri` as the only return address** (`application.properties`; ADR-018's
  description of the flow) → **refined, not replaced.** *Why:* it remains the default and the only
  address in use until an application configures another. What changes is that it is no longer the
  *sole possibility*, because a native client cannot be served by it.
- **"what is left is per-platform link registration and handing the received URL to
  `ZenAuthLink.parse`"** (ROADMAP item 4, as written after ADR-018) → **corrected.** *Why:* that
  under-described the work. Handing over the URL needed an entry point that did not exist
  (`consumeAuthLink`), and the return address needed a server-side decision that did not exist
  either. Both are now built; what remains is genuinely per-platform.

### Consequence

- `zen_demo_client` **has no native runners** (`web/` only), so the remaining half of ROADMAP item 4
  has nowhere to be configured yet. The steps are recorded in that app's README, and are explicitly
  **not claimed as done**: they cannot be verified without a simulator or a device.
- New config: `auth.redirect-uris`, empty by default. Each entry must also be registered in the
  Supabase project's Redirect URLs, or GoTrue drops it — both halves or neither.
- **Verified green:** `task test:apps:server` — 66 tests. New `IdentityServiceTest` asserts the
  exact-match rule against the shapes a prefix or host check would have admitted
  (`…/../evil`, `….evil.example`, `…@evil.example`), that a rejection does not echo the address,
  and that a password change is made with the session's own bearer and no user id.
  `AuthResourceTest` asserts a refused address returns 400 with **no signup and no recovery email
  sent**. `task test:client` green (new: the return address travels on both email-sending calls; a
  link received while running signs in and raises the recovery gate; a spent one does not sign the
  current user out).
- One test was **removed rather than fixed**: an HTTP-level authenticated password change that
  paired `@TestSecurity` with a fabricated session cookie. It passed alone and failed after any
  test that set real cookies — a statement about how convincing the fake was, not about the code.
  Its two claims are now split between `AuthResourceTest` (an unauthenticated caller is refused)
  and `IdentityServiceTest` (the bearer used is the session's own).

---

## ADR-018 — Email links sign the user in: the implicit fragment flow, exchanged for a cookie, and not PKCE

**Date:** 2026-07-28. **Status:** accepted. **Follows:** ADR-007, ADR-016.

### Decision

Following a Supabase email link — confirmation, recovery, or invite — now **ends signed in**,
instead of returning the user to a login form. The mechanism is the **implicit fragment flow**:

- **`/auth/callback` still only redirects.** Supabase puts the session it minted in the URL
  *fragment* (`#access_token=…&type=…`), which by definition never reaches a server. The endpoint's
  job is to bounce the browser to the app with the fragment intact, and it stays that way.
- **The client is the only party that can read the fragment**, so it does. `ZenAuthLink`
  (`zen_identity`, pure Dart) parses the landing URL into one of five outcomes: nothing, a session,
  a recovery session, a confirmation with no token, or a link the provider rejected.
- **`POST /api/v1/auth/session` exchanges those tokens for the ordinary httpOnly cookie session.**
  It is `@PermitAll` by necessity — the caller has no session yet — and is *not* thereby unguarded:
  the access token is presented to Supabase (`GET /auth/v1/user`) and a cookie is issued only if
  Supabase vouches for it. Possession of a live provider token is the credential, exactly as
  possession of the right password is on `/login`.
- **The exchange happens before the app's first frame**, inside the session load that already
  splashes: `IdentitySessionStore.build()` consumes the link *before* probing for a cookie. Probing
  first would answer "anonymous", render the login screen, and only then sign the user in behind it.
- **Recovery signs in and then holds a gate up.** Being signed in is not the end of a recovery: the
  link exists to change a password nobody remembers. `passwordResetRequiredProvider` stays true
  until `POST /api/v1/auth/password` (authenticated; changes the password of whoever the session's
  own token belongs to) succeeds, and the app routes to `SetPasswordScreen` while it is.
- **Consumed tokens are erased from the URL** (`history.replaceState`, web-only by conditional
  import on `dart.library.js_interop`), so they do not linger in history or in a copied link.

**PKCE was considered and rejected.** Its `code_verifier` must be created by whoever *starts* the
sign-up and held until the link is followed. In jZen sign-up is a backend call
(`IdentityService.register` → GoTrue `/signup`), so the verifier would have to be minted on one
request, stored server-side, and matched to a different browser on a later one — inventing
cross-request state on a deployment whose whole premise is that in-process state is fine *because*
there is one instance. The implicit flow needs no such state, and the token it exposes is exposed to
the browser either way.

### What this supersedes, and why

- **"Not yet done, on purpose: consuming the fragment token to sign the user in automatically after
  they confirm … or Supabase's PKCE flow with a server-side code exchange"** (`AuthCallbackResource`
  javadoc; ROADMAP open-backlog item 3) → **done, and the alternative closed.** *Why:* the deferral
  was about sequencing, not doubt; and the parenthesised PKCE option is now ruled out for the
  reason above, so that it is not reopened as an equivalent choice later.
- **"the user confirms via Supabase's email link (which lands on `/auth/callback` →
  `/?auth=email-confirmed`, so the login screen greets them), then logs in"** (ROADMAP, "Defects
  surfaced by the first real deployment") → **refined.** *Why:* the greeting is now the *fallback*
  for a landing with no usable token, not the normal path. The normal path renders the app already
  signed in and never shows the login screen at all.
- **Item 4, native deep-linking** (ROADMAP open backlog) → **narrowed, not resolved.** *Why:* the
  consumption half is platform-neutral — `ZenAuthLink.parse` takes a `Uri` — so what remains is
  per-platform link registration. Off the web `Uri.base` is a file path, the parser finds no link,
  and the flow degrades to today's "confirm in a browser, then sign in" rather than breaking.

### Consequence

- New contract: `SessionExchangeRequest` and `SetPasswordRequest` in `proto/zen/v1/identity.proto`,
  with their OpenAPI component schemas in the app's static `META-INF/openapi.yaml`. Generated Dart
  messages and the admin `schema.generated.ts` regenerated through `task sync:contracts`.
- New framework surface, inherited by every jZen app: `ZenAuthLink` + `authLinkProvider`,
  `passwordResetRequiredProvider`, and `SetPasswordScreen`. An app decides only *where* the gate
  sits in its routing — `zen_demo` puts it ahead of everything, which is the intended shape.
- A token that reaches jZen from a URL is never trusted locally. Signature-checking it here would
  accept one Supabase had already revoked, so the provider is asked. That is one outbound call on a
  rare path, and it is the reason `@PermitAll` on `/session` is safe.
- **Verified green:** `task test:apps:server` — 59 tests, including a valid exchange setting
  httpOnly cookies, a forged token refused with no cookie issued, a missing token, `setPassword`
  updating with the session's own bearer, and `setPassword` rejected without a session.
  `task test:client` passes every workspace member (new: 7 `ZenAuthLink` parser cases, and 3 store
  cases covering auto-login, a spent link falling back to the probe, and the recovery gate).
  `task test:admin` typechecks. `flutter analyze` clean in `zen_ui_identity` and `zen_demo_client`.

---

## ADR-017 — RBAC: the framework owns the mechanism, the application owns the policy

**Date:** 2026-07-25. **Status:** accepted. **Follows:** ADR-001, ADR-005, ADR-010.

### Decision

jZen provides role-based access control through the **platform's** authorization mechanism, not a
bespoke one, and draws the framework/application line the same way ADR-010 drew it for capabilities:
the framework ships the *enforcement mechanism*; each application defines its *policy* (which roles
exist beyond the base set, who has many, what fine-grained permissions or tenant scoping mean).

**What the framework provides today, and it is complete as a mechanism:**

- **A role model** — `UserRole` in `zen-identity` (`USER`, `ADMIN`, `REVIEWER`, `B2B_ADMIN`), with
  `UserRole.Names.*` string constants because `@RolesAllowed` needs a compile-time constant (the
  ADR-003 pattern).
- **Roles stored in the database, never in the JWT** — a single `users.role` column, defaulted to
  `USER` at registration. This is deliberate and load-bearing: a role change or revocation takes
  effect on the **next request**, with no token refresh, no re-login, and no token bloat. The JWT
  establishes *who*; the database establishes *what they may do*.
- **`RoleAugmentor`** (a `SecurityIdentityAugmentor`) loads the role from the `users` table per
  request and adds it to the Quarkus `SecurityIdentity`.
- **Enforcement via standard Jakarta annotations** — `@RolesAllowed(UserRole.Names.ADMIN)`,
  `@PermitAll`, and `@Authenticated`, enforced by Quarkus proactive auth. `AdminUserResource` is the
  reference; role assignment itself runs through it (`@RolesAllowed(ADMIN)`), so admins grant roles.

**Two rules this entry fixes in place, because they are latent traps:**

1. **"Any logged-in user" is `@Authenticated`, never `@RolesAllowed(Names.USER)`.** Roles are single
   and `@RolesAllowed` has no hierarchy, so an `ADMIN` is *not* also a `USER`. `@RolesAllowed(USER)`
   would therefore 403 an admin. Nothing requires `USER` today (public is `@PermitAll`), so it does
   not bite yet — this rule ensures it never starts to.
2. **Row-Level Security is not the application's authorization.** The `V2` owner policy
   (`id = auth.uid()`) is active only on Supabase and guards *direct Supabase-side* access; the
   Quarkus app connects through the pooler as `postgres`, which bypasses RLS. For jZen's backend,
   `@RolesAllowed` is the only authorization layer — do not assume RLS is a safety net beneath it.

**What is application policy, not framework** (per ADR-010's second-consumer bar): multiple roles
per user (the `users.role` single column and the augmentor's single `addRole` are the current
limit; multi-role needs a `user_roles` join table and an augmentor loop), fine-grained permissions
or attribute/ownership checks ("edit your *own* order"), and tenant scoping (`B2B_ADMIN` anticipates
multitenancy — "admin of *their* org" needs a `tenant_id` dimension and tenant-scoped queries).
None is built; each belongs to an application until a **second** one needs the same shape, then it
promotes to the framework.

**Two framework gaps are committed to the plan** (ROADMAP "RBAC"), because they are general, small,
and awkward to retrofit: documenting the `@Authenticated` convention (rule 1 above), and multi-role
support. Everything past those stays application-side under the ADR-010 bar.

### What this supersedes, and why

- **Nothing is reversed.** This entry *names and records* a mechanism that already exists
  (`UserRole`, `RoleAugmentor`, `@RolesAllowed`) but was never stated as jZen's RBAC position, and
  it draws the same framework/policy line ADR-010 established so future requests ("add permissions",
  "add tenancy") have a decided answer instead of an open one.
- **BLUEPRINT "Persistence"/auth** and **STANDARDS** are *extended* with the two rules above; no
  prior rule changes.

### Consequence

RBAC has a written position: the framework's mechanism is the platform's (Jakarta Security +
DB-sourced roles), and role/permission/tenancy *policy* is application-owned until a second consumer
promotes it. The `@Authenticated` rule and the RLS clarification are now explicit, so neither trap
is discovered in production. No behaviour changed; the diff is this entry plus the two doc rules and
the ROADMAP item. `verify:docs` green.

## ADR-016 — jZen delivers the web app as WebAssembly

**Date:** 2026-07-25. **Status:** accepted. **Follows:** ADR-015 / ROADMAP POC delivery order.

### Decision

The reference app's web target is compiled to **WebAssembly** and that is what jZen ships to the
browser: `flutter build web --wasm` (dart2wasm + the **skwasm** renderer), not the default
`dart2js` output. `task build:web` carries `--wasm`, and the web deploy is not considered done
until the served bundle is Wasm.

The moving parts, stated honestly rather than as a slogan:

- **Two axes, and this decision is about the app-code axis.** Flutter web has always shipped Wasm
  in the form of the CanvasKit/Skia renderer (~40 MB of the bundle); that was never the *app*. This
  decision is about how jZen's own Dart compiles: **dart2wasm → `main.dart.wasm`**, replacing
  **dart2js → `main.dart.js`** as the delivered form. The renderer follows suit — skwasm rather
  than the JS-driven CanvasKit path.
- **WasmGC is the floor.** dart2wasm requires the browser's WebAssembly Garbage Collection
  proposal: Chrome/Edge 119+, Firefox 120+, and **Safari 18.2+** (December 2024). Below that floor
  a browser cannot run the Wasm bundle.
- **The JS build remains, as Flutter's automatic fallback — not as a second jZen target.** A
  `--wasm` build emits *both* the Wasm bundle and a dart2js fallback, and `flutter_bootstrap.js`
  selects at load time by probing WasmGC support. So "jZen delivers Wasm" means Wasm-first with a
  transparent fallback that Flutter owns, not that the JS output is deleted. jZen does not maintain
  the fallback; it is a property of the build, and the day the WasmGC floor is universal it
  disappears on its own.

### What this supersedes, and why

- **"tree-shake native-only code … out of the JS/Wasm web bundle"** (STANDARDS "Client config is
  compile-time") → **refined.** *Why:* that wording treated JS and Wasm as interchangeable names
  for "the web bundle." They are not interchangeable outputs, and jZen now commits to one:
  `--wasm`. The compile-time-config rule is *reinforced*, not weakened — `--wasm` is one more
  build-time selector, exactly the kind the rule exists to enable, and runtime config would defeat
  it here as everywhere.
- **The default `flutter build web` (dart2js)** → **replaced by `--wasm` from the first web
  deploy, not deferred to a later step.** *Why:* an earlier draft of this entry proved the
  same-origin serving path with the dart2js default and made Wasm a separate final step. That
  repeats the exact error [ADR-013 / the native-JSON bug](#) taught: proving one artifact on the
  JVM and shipping another as a native image is how the reflection 500 reached production. Proving
  dart2js serving and then shipping dart2wasm is the same substitution. **Test the artifact you
  ship.** So `build:web` carries `--wasm` from the outset, and `test:native` — which already
  exercises the real native image — asserts the real Wasm bundle: `main.dart.wasm` served with
  `Content-Type: application/wasm`. `verify:endpoints` keys its web-shell assertion on
  `flutter_bootstrap.js` (both compilations emit it), not `main.dart.js` (the fallback, absent from
  the Wasm view).
- **BLUEPRINT "Deployment"** and **STANDARDS "Frontend split"**, which described the web target
  without naming its compiled form → **extended** to state it is Wasm.

### Consequence

The web app jZen serves is WebAssembly, and the architecture docs say so. Three things follow:

- **A browser floor is now part of the product's contract:** WasmGC-capable browsers
  (Safari ≥ 18.2). This is a deliberate trade for the runtime speed and smaller-JS payload of the
  Wasm compilation, and it is stated so it is a decision rather than a surprise.
- **The same-origin delivery is unchanged.** Wasm vs JS is the *compilation* of the app that the
  backend serves at `/`; it does not touch ADR-015's requirement that the bundle be served
  same-origin with the API so the session cookie flows. The Dockerfile bakes whichever bundle
  `build:web` staged.
- **The `.wasm` MIME type is now a checked concern.** A browser stream-compiles WebAssembly only
  when the server sends `Content-Type: application/wasm`; the wrong type is a Wasm-specific failure
  invisible to a dart2js build. `verify:endpoints` asserts it, in the local `test:native` smoke and
  against the deployed service, so it is caught the way the native-reflection bug should have been —
  before production, not in it.
- **skwasm needs no cross-origin isolation here.** Multi-threaded skwasm would want COOP/COEP
  headers (for `SharedArrayBuffer`), but Flutter degrades to single-threaded skwasm when the page is
  not cross-origin isolated, so the Wasm app runs without them. That is deliberate: COOP/COEP would
  fight the same-origin cookie setup ADR-015 depends on, so jZen accepts single-threaded skwasm
  rather than add isolation headers.
- **The Wasm delivery uncovered and fixed a framework bug — exactly what "test the artifact you
  ship" is for.** The compile-time platform selectors guarded their web branch on
  `if (dart.library.html)`, which dart2js defines and dart2wasm does not, so under Wasm all three
  (`zen_transport`'s codec selector and session client, `zen_ui_navigation`'s widget selector) fell
  through to their stub and threw `Unsupported operation: Platform not supported` at startup — a
  bundle that compiled, served, and passed every curl check, then rendered a blank page in the
  browser. Every guard now keys on `dart.library.js_interop` (STANDARDS "Client config is
  compile-time"). This is the same shape as the native-JSON bug: green on one artifact, broken on
  the one actually shipped, caught only by driving the real thing — here a browser, not curl.

## ADR-015 — The appendix gains a delivery order, because a goal was named: a deployed POC

**Date:** 2026-07-24. **Status:** accepted. **Follows:** ADR-013, ADR-014.

### Decision

ADR-013 recorded the remaining pre-production work as an unordered census, and argued against giving
it an order. That argument was correct **for a census**. It stops being sufficient once an objective
is named, and one now is: **get a demonstrable POC deployed** — a running stack a person can be shown,
rather than a framework that composes on a laptop.

**1. The order comes from the goal, not from the items.** This is the part worth preserving from
ADR-013: the appendix items genuinely have no intrinsic sequence, each being independently
triggered. What creates a sequence is an objective, because an objective makes some items
prerequisites and others irrelevant. The order below is therefore a property of *this* goal and is
expected to change when the goal does — which is why it lives in the appendix as a delivery plan and
does **not** become Steps 10-11-12.

**2. The order, with the dependency that forces most of it:**

| | Item | Why here |
|---|---|---|
| 1 | Fix `format:`'s `\|\| true` | A rule violation (STANDARDS "Orchestration") in the tasks CI will later automate. Fixing a swallow after wiring a pipeline around it means the pipeline inherits the blind spot. Minutes of work. |
| 2 | Pin the toolchain | Presence is checked, versions are not; no `.tool-versions` / `mise.toml` / devcontainer exists. Native-image builds are sensitive to JDK/GraalVM drift, so this directly de-risks the next item. |
| 3 | Deploy the backend to Cloud Run | The hard prerequisite: everything visible depends on a live API. Also the step that finally makes GDPR retention *run* — see point 5. |
| 4 | Deploy the Flutter web app, same-origin | The POC's user-facing surface. Blocked by 3. |
| 5 | Deploy the admin panel, same container | The POC's third language binding. See point 4. |
| 6 | CI | Sustains quality; it does not produce the first deploy. |
| 7 | Publish the packages | Serves *other developers adopting the framework* — a different audience from the one a POC is for, and not on its path. |

**3. Publishing drops below the POC, reversing the emphasis ADR-013 gave it.** ADR-013 called
publishing "the largest of these", and it remains the largest *gap*. It is not the most urgent
*task*, because size and urgency are different properties: publishing matters when someone else
builds on jZen, whereas a POC proves the thing runs at all. Publishing is additionally gated on CI —
shipping unverified versions to a registry is worse than shipping none, since a registry version is
not retractable the way a branch is.

**4. The admin panel is part of the POC, not an item after it.** Two reasons, the second decisive:

- It is **already architected same-origin**, and more so than the Flutter app. `vite.config.ts`
  proxies `/api` and `/openapi` to the backend under the comment *"Same-origin proxy so the httpOnly
  `zen_access_token` cookie flows without CORS juggling"*. Deploying it same-origin makes production
  match dev. The web app is the surface that does *not* match: the appendix records it running on
  its own origin behind CORS locally.
- It is **the only surface that exercises the third language binding.** The contract-first claim is
  proto → Java **and** Dart **and** TypeScript; the Flutter client demonstrates the first two, and
  only the panel drives `schema.generated.ts`, the `Content-Range` pagination convention, and the
  JSON transport mode against generated types. A POC without it demonstrates two thirds of the
  headline claim. MANIFESTO names react-admin as one of three stack pillars, STANDARDS "Frontend
  split" makes Product UI and Admin UI co-equal, and ADR-005 made `@jzen/admin-core` framework code
  — leaving it undeployed leaves framework code unexercised.

**5. One consequence of the ordering is a correctness claim, not a preference.** ROADMAP 7a states
"The GDPR obligation is now discharged in production." That is true of the code and false of the
world: retention fires only when a Cloud Scheduler entry calls `POST /api/v1/jobs/trigger`, and no
such entry exists because nothing has been deployed. The mechanism is proven (ADR-008; 10 framework
unit tests over a driven clock, 2 e2e cases); the trigger is simply not wired to anything real.
Item 3 above is what makes that sentence true.

**6. Two items are declarations rather than queued work**, recorded so they are not mistaken for
work left undone:

- **Native release pipelines are per-application.** Signing identities, store accounts, and
  notarization credentials belong to whoever ships a product, not to the libraries it is built on.
  Filed against an app when an app ships; blocks nothing.
- **`task`'s `sources:`/`generates:` fingerprinting is refused, not merely unused.** It would defeat
  `sync:contracts`. Promoted to a STANDARDS "Orchestration" rule rather than left as a backlog note,
  because the hazard is invisible from the feature's description — see "What this supersedes" below.

### What this supersedes, and why

- **"The remaining work is an appendix, not Steps 10-11-12 … numbering them would misrepresent both
  their history and their nature — a numbered step is a commitment with an order, whereas these are
  a boundary the project has not yet crossed, each independently triggered."** (ADR-013 pt.2) →
  **refined.** *Why:* the conclusion stands and the appendix stays an appendix — nothing becomes a
  numbered step, the nine-step sequence stays readable as history, and no item is reframed as
  planned work that slipped. What ADR-013 lacked was an objective; it was written as a census of a
  boundary, and a census legitimately has no order. Point 1 above states the distinction that
  reconciles the two: the items still have no *intrinsic* order, and the sequence is a property of
  the goal now in hand. If the goal changes, the sequence is rewritten and ADR-013's reasoning is
  untouched.
- **"Publishing is the largest of these"** (ROADMAP appendix, following the gap table) →
  **reframed, not contradicted.** *Why:* it is still the largest gap. Point 3 separates size from
  urgency and puts it last for this goal, on audience rather than on effort.
- **"A deploy task that puts the bundle on GCP — its own container on Cloud Run, or static hosting —
  and a documented origin/CORS story for it."** (ROADMAP appendix, web-app row; the admin row
  inherited it) → **corrected.** *Why:* it presented as an open choice something two existing
  constraints already close. An edge that proxies the API is forbidden by STANDARDS "Deployment
  model", and `deploy:cloudrun` rules out `firebase deploy` by name — Firebase Hosting forwards only
  `__session` and jZen sets three cookies. A separate origin that does *not* proxy the API escapes
  that rule and lands on the other: `SessionService` sets all three cookies `SameSite=LAX` and
  `run.app` is on the Public Suffix List, so two default Cloud Run URLs are cross-site and the
  cookie is never attached — login returns 200 and every later request arrives anonymous. Both roads
  end at same-origin. The ROADMAP rows and the note beneath them now say so.

### Consequence

The appendix is now a delivery plan for a stated goal while remaining a boundary census, and the two
readings are distinguished rather than conflated. Three things hold as a result:

- **The POC's completion criterion is explicit**: a deployed backend, a deployed web app, and a
  deployed admin panel, all same-origin — at which point all three language bindings of the
  contract-first claim are demonstrated on live infrastructure rather than in a test suite.
- **The ordering is falsifiable.** It derives from one goal and two repository facts (the cookie
  policy and the admin's existing dev topology), all cited above. A different goal produces a
  different order, and that is not drift.
- **The GDPR sentence in ROADMAP 7a is on notice.** It is currently ahead of reality and becomes
  true at item 3; until then it should be read as describing the mechanism, not the deployment.

**No behaviour changed.** The diff is the ROADMAP appendix, this entry, and one STANDARDS
"Orchestration" rule; `verify:docs` is green and no task, module, or generated artifact is touched.

## ADR-014 — The orchestrator is a task runner by design: `task`, and not make, Bazel, Nx, or Melos

**Date:** 2026-07-24. **Status:** accepted. **Follows:** ADR-013.

### Decision

STANDARDS "Orchestration" has always *stated* the orchestrator rule — `Taskfile.yml` is the only
one, it triggers native tools rather than replacing them, and no second build driver joins it — but
it never **argued** it. A rule without its reasoning is indistinguishable from an arbitrary one, and
it invites the same question from every new reader: *why not `make`, which is everywhere and which
nobody has to learn?* That question was asked, answered in conversation, and lost. This entry is the
answer, recorded once.

**1. The category is the decision.** `task` is a **task runner**; `make`, Bazel, Pants, and Buck2
are **build systems**. jZen picks the runner category on purpose, and the reason is already written
down one line above the rule it explains: *"A task that reimplements what a package manager already
does is a bug."* Incrementality in this repository belongs to `mvnw`, `dart pub`, and `pnpm` — each
of which does it better for its own language than any orchestrator could. An orchestrator carrying
its own dependency graph is one that is *tempted* to duplicate them. **The orchestrator is chosen to
be too weak to become a build system.** That is a feature, and it is the same instinct that keeps
`zen_core` dependency-free and that answered "no" six times in ADR-010.

**2. Not `make`.** The strongest objection — universal availability, universal familiarity, no new
dependency — is real, and for a C, Go, or Rust project it would win. It loses here on four specific
counts, all measured against this repository rather than asserted:

- **The multi-line problem, which macOS makes fatal.** In `make`, every recipe line is its own
  subshell: variables and `cd` do not survive between lines. The remedy is `.ONESHELL:`, introduced
  in **GNU Make 3.82**. macOS ships **GNU Make 3.81 (2006)**, frozen at the GPLv3 licence change and
  never advanced — confirmed on the delivery machine. The Taskfile currently has **12 multi-line
  shell blocks** and **19 tasks using `dir:`** across 40 tasks. `deploy:cloudrun` alone assigns
  `IMAGE` and then uses it on three subsequent lines; under 3.81 that variable is gone by line two.
- **The escaping problem.** `make` claims `$`, so every shell variable doubles. `doctor` defines a
  shell function taking `$1 $2 $3` and reads `$HOME` and `$missing`; as a Makefile recipe those all
  become `$$1`, `$$HOME`, `$$missing`. That task is currently readable, and it would stop being so —
  which lands squarely on MANIFESTO's own bar.
- **The discovery problem, which is load-bearing here.** `task --list` emits every task with its
  `desc:`, and `verify:docs` (ADR-012) **mechanically asserts that every `task <name>` named in a
  README resolves in that list**. `make` has no equivalent; the conventional substitute is a
  hand-rolled `##`-comment convention plus an `awk` parser. Replacing a builtin with a bespoke
  comment DSL, in a project whose headline rule is "no custom magic", is the objection this entry
  finds hardest to answer.
- **The phony tax.** All 40 targets would need `.PHONY`, forever, or break the day a directory
  shares a target's name.

  The escape — move all 12 blocks into `scripts/` and have `make` call them — works, but splits the
  logic across two locations and trades "learn six YAML keys" for "learn `make` *and* navigate a
  script directory". Note also what is actually being avoided: a Taskfile is YAML with about six
  keys (`desc`, `cmds`, `deps`, `dir`, `silent`, `sources`/`generates`) wrapping plain bash, whereas
  `make` is a genuine macro language with automatic variables, pattern rules, text functions, and
  two assignment semantics. **`make` is the larger DSL.** It feels smaller only because it is
  familiar.

**3. Not Bazel, Pants, or Buck2.** These are the real industrial answer for polyglot monorepos at
scale, and they are wrong here for a structural reason, not a scale one: their model *is* replacing
native tool resolution with a hermetic graph, which contradicts the rule in point 1 directly. And
decisively — **Flutter has no viable Bazel story.** Dart's Bazel rules are effectively unmaintained
and Flutter insists on owning its own build and tree-shaking, which ADR-009 proved is load-bearing
for jZen (the web bundle's tree-shaking is *why* client config is compile-time). Adopting Bazel
would mean fighting the toolchain the architecture is built on.

**4. Not Nx or Turborepo.** JS-first. Both require `node_modules` and a JS toolchain at the
repository root, breaking the language-neutral root that BLUEPRINT and `CLAUDE.md` both state (no
root `pom.xml`, no root `pubspec.yaml` — and by the same logic, no root `package.json`). They would
still shell out to Java and Dart as opaque commands, exactly as the Taskfile does, while adding a
plugin system, a generator system, and a daemon. That is more magic, not less. **Moon** is the most
credibly polyglot of this family and remains the one to re-examine first if point 7 ever fires, but
Dart/Flutter is not first-class there either.

**5. Not Melos.** Already excluded by name in STANDARDS, and worth stating why the exclusion is
structural rather than a preference: Melos is Dart-only, so it could never be *the* orchestrator of
a repository that also builds Java and TypeScript. It could only ever be a *second* driver, which is
the thing the "one orchestrator, and only one" rule forbids.

**6. The MANIFESTO scope question, answered.** "No *custom* magic" is written about **code
generation** — it reads "jZen adopts industry-standard, inspectable **generators** only" and lists
generators. The orchestrator was never inside that clause, so `task` was never in violation of its
letter. This entry nonetheless holds the orchestrator to the clause's *spirit* — inspectable, no
bespoke DSL, nothing a reader must learn from scratch — because that is the bar a reader will apply
whether or not the sentence names it, and because points 2–5 are decided on exactly those grounds.

**7. The reversal trigger, stated as a testable condition** (the ADR-010 pattern: a trigger, not a
deferral). Two, and neither is met today:

- **If the Taskfile's recipe bodies collapse to one-line wrappers with the real logic living in
  `scripts/`**, then `task` is adding nothing that `make` does not, the four objections in point 2
  evaporate along with the multi-line blocks that cause them, and `make`'s ubiquity wins. Revisit
  then.
- **If a second application under `apps/` makes full-fanout CI wall-time unacceptable**, the answer
  is, in order: `sources:`/`generates:` fingerprinting (native to `task`, currently unused across all
  40 tasks), then affected-detection scripting, then Moon. **Bazel does not become correct at that
  point** — the Flutter constraint in point 3 is structural and does not soften with scale.

### What this supersedes, and why

- **"`Taskfile.yml` is the only orchestrator. It triggers native tools; it never replaces them."**
  (STANDARDS "Orchestration") → **refined, not reversed.** *Why:* the rule stands exactly as
  written; what it lacked was the reasoning that makes it defensible to someone encountering it
  cold. The sentence "a task that reimplements what a package manager already does is a bug" turns
  out to be the whole argument compressed to one line, and this entry unpacks it. STANDARDS gains a
  pointer here; its wording is otherwise untouched.
- **"Do not introduce Melos, Gradle-as-orchestrator, or any second build driver beside the
  Taskfile."** (STANDARDS "Orchestration") → **refined.** *Why:* that list reads as three specific
  prohibitions, so a reader may reasonably ask whether a tool not on it (Nx, Bazel, Moon, `just`) is
  therefore permitted. Points 2–5 supply the general test the list was standing in for: a candidate
  must not replace native tool resolution, must not require a language-specific toolchain at the
  repository root, and must not require jZen to hand-roll what `task` provides as a builtin.
- **"jZen adopts industry-standard, inspectable generators only"** (MANIFESTO "No *custom* magic") →
  **scope clarified.** *Why:* the clause is about code generation and does not reach the
  orchestrator, but it is routinely read as a whole-repository claim — which is what prompted this
  entry. Point 6 states the boundary and then voluntarily accepts the stricter reading.

### Consequence

The orchestrator choice now has a written argument, and the recurring question has a citable answer
instead of a rule that must be taken on faith. Three invariants follow:

- **The runner/build-system boundary is explicit.** Any future proposal to give the orchestrator its
  own dependency graph, cache, or resolution logic is now arguing against a recorded decision rather
  than filling a silence.
- **The trigger in point 7 is the only route to reopening this**, on the ADR-010 bar: a measured
  condition, not a preference. Both conditions are false as of this entry.
- **`task` itself remains an unpinned, unchecked dependency.** `doctor` cannot check it — `task` is
  what runs `doctor` — and no version is pinned for it or for any other tool: presence is checked,
  versions are not, and no `.tool-versions` / `mise.toml` / devcontainer exists. That is a real gap,
  it is tracked with the production backlog rather than here, and it should be closed alongside CI,
  where an unpinned toolchain stops being a local inconvenience and becomes a source of silent
  divergence between CI and a contributor's machine.

**No behaviour changed.** The diff is this entry plus a cross-reference in STANDARDS "Orchestration";
no task, module, or generated artifact is touched, so `build`, `test`, and `sync:contracts` are
unaffected by construction. What *was* measured, on the delivery machine, is the evidence in point 2:
`make --version` reports GNU Make 3.81 (2006), and the Taskfile contains 12 multi-line shell blocks
and 19 `dir:` declarations across 40 tasks.

## ADR-013 — Completing the roadmap is not being production-ready: the remaining work is named, not implied

**Date:** 2026-07-23. **Status:** accepted. **Follows:** ADR-012 / ROADMAP Step 9.

### Decision

Step 9 finished the last numbered step, and the documents it produced read as though the project
were finished. Reviewing them showed it is not, and that the gap had never been written down
anywhere. This entry records the gap and where it is tracked.

**1. The distinction is stated explicitly, in three places.** "The roadmap's planned steps are
complete" and "a product can ship on this" are different claims, and only the first is true. The
ROADMAP now says so where it closes, the root README carries a **Status** section a newcomer meets
before anything else, and ADR-012's consequence stops short of claiming production-readiness.
Documents that read as finished when the work is not are a defect of the same kind as a silent
failure: they remove the signal that something still needs doing.

**2. The remaining work is an appendix, not Steps 10-11-12.** It is recorded in ROADMAP's
"Beyond the roadmap" appendix. *Why an appendix:* these items were never planned work that
slipped, and numbering them would misrepresent both their history and their nature — a numbered
step is a commitment with an order, whereas these are a boundary the project has not yet crossed,
each independently triggered. It also keeps the nine-step sequence readable as the historical
record it is. The appendix states, for each gap, where it stands today and what "done" means.

**3. The gaps, as measured.**

- **The packages are unpublished** — everything `0.1.0`, Dart `publish_to: none`, npm `private`,
  Java installed to a local repository; consumption is by local path only. **This is the largest
  gap**, because it is the framework's whole distribution claim: until the packages are in
  registries, "build your app on jZen" means "check out this repository", and the lockstep-version
  contract has nothing to bite on. STANDARDS "Code generation" already names publishing as the
  exit condition for tracking generated code, so it is a promise the documents made and the
  project has not kept.
- **The web app and the admin panel have no deploy path** — both build to a bundle nothing ships;
  the backend container serves the API only. Not an exclusion by design, which is what the first
  draft of the README wrongly said; simply unbuilt.
- **Native app pipelines do not exist** — the one item genuinely left to each application.
- **The backend deploy path is unproven** — `deploy:cloudrun` has never run end to end.

**4. One latent defect was found by writing the documentation, and it is the argument for this
entry.** `Dockerfile.native-micro` still copied `zen-app/target/*-runner`, a path left behind when
ADR-001 relocated that module. Relative to the build context the deploy task actually uses, the
directory does not exist, so `task deploy:cloudrun` **failed at the `COPY`** — proven by building
the old and new Dockerfiles against a stub runner (`lstat /zen-app/target: no such file or
directory` versus a clean build). It survived because **nothing exercises it**: no test, no gate,
and no deployment has ever run. A stale rename inside an unexercised path is exactly what an
honest backlog is for, and the sweep that found it also cleared the same rot from five source
comments, a versioning example in STANDARDS, and the Cloud Run `SERVICE_NAME` default.

### What this supersedes, and why

- **ROADMAP Step 9's "This closes the ROADMAP … there is no Step 10", and ADR-012's consequence
  as first written** → **narrowed to the *planned steps*.** *Why:* the sequence really is
  finished, but the sentence was read — including by its author — as "nothing remains", which is
  false. The claim now names what it covers.
- **The root `README.md`'s deploy section, "the Flutter client and the admin panel have no jZen
  deploy task, **by design**"** → **corrected to "not yet built".** *Why:* it was not a decision,
  it was undone work, and describing an omission as a design choice is how a gap becomes
  permanent.

### Consequence

The roadmap is closed and the backlog is open, and no document now implies otherwise. **No
behaviour changed by this entry**; the one functional change in its scope is the `Dockerfile`
`COPY` fix, which repairs a path that could not have worked. Lockstep versioning is unchanged at
`0.1.0`, no Flyway band is claimed (200-299 remains free), and no dependency was added.

The next thing jZen does is not a roadmap step. It is either **publishing the packages** — which
converts the framework claim from an arrangement of folders into something an outside application
can depend on — or **a second application**, which is what ADR-001 says actually tests the claim.
Both are now written down as choices rather than assumed to be already handled.

---

## ADR-012 — READMEs are the front door; a documentation drift gate, and the licence propagated to every module

**Date:** 2026-07-23. **Status:** accepted. **Discharges:** ROADMAP Step 9, and closes the ROADMAP.

### Decision

Step 9 writes the READMEs — the front door to a codebase whose deep reference is
`docs/architecture/`. Five coupled choices, plus one correction forced by a required deliverable.

**1. Step 9's own specification was stale, and is corrected as part of discharging it.** It was
written at Step 0, and three later ADRs moved things underneath it. Each was verified against the
built tree and fixed in place (the same class of problem, and the same resolution, as Step 8's
verification line):

- It asked for **`client/zen_demo/README.md`**. There is no `client/zen_demo` — ADR-001 relocated
  the reference app to `apps/zen_demo/zen_demo_client/`. The reference-app README lives there, plus
  an app-level `apps/zen_demo/README.md` for the assembly as a whole.
- Its `server/README.md` brief listed the modules as **"zen-proto/core/transport/identity/email/app"**.
  `zen-app` no longer exists (ADR-001 relocated it to `apps/zen_demo/zen_demo_server`) and `zen-jobs`
  was missing (it did not exist until ADR-008). The built module map is
  `zen-proto/core/transport/identity/email/jobs`.
- Its *Repository map* bullet listed `server/ client/ admin/ proto/ supabase/` and **omitted
  `apps/`** — the framework-versus-applications split, the single most important structural fact
  about the repository (ADR-001) — as well as `scripts/` and `docs/`. The root README's map names all
  eight top-level directories.

**2. The rule for where a README goes is stated, so the answer for the next package is derivable.**
A directory gets its own README when it is a **front door** — a place a reader arrives at
independently and needs oriented from: the repo root; each top-level surface a contributor treats as
a unit (`server/`, `client/`, `admin/`, `proto/`, `supabase/`, `scripts/`); the reference app as a
unit (`apps/zen_demo/`) and its client (`zen_demo_client`, the surface `run:demo`/`test:e2e` drive);
and a **publication-shaped** package, whose pub.dev audience the monorepo view does not serve. A
directory reached only *through* a front door, whose story is fully told there, gets none — that is
where the drift cost buys nothing. Under the rule: **`zen_demo_server` and `zen_demo_admin` do not
get their own READMEs** (their reusable story is in `server/` and `admin/`; their assembly story is
`apps/zen_demo/README.md`), and **`zen_core`/`zen_transport`/`zen_identity` do not** (documented
collectively in `client/README.md`; the trigger to add one is the same signal the two `zen_ui_*`
packages already carry — a `LICENSE` and shaping for publication).

**3. The five pre-existing READMEs are dispositioned individually, not uniformly.** They were not a
set: `apps/zen_demo/zen_demo_client/README.md` was the **stock Flutter template stub** ("A new
Flutter project"), which described a different project and was **rewritten wholesale**; the two
`zen_ui_*` READMEs and the navigation `example/` README were **already accurate and in jZen's voice**
and were **kept**, the two publication-shaped ones gaining only a one-line "part of the jZen
monorepo" provenance note for their pub.dev audience; `scripts/README.md` — which Step 9 never names
— was **kept**, because `scripts/` is a front door under the rule above.

**4. A documentation drift gate ships: `task verify:docs`.** Prose has no compiler and no
`sync:contracts`, so a README that names a task or a test count rots silently — the exact failure
mode STANDARDS spends its length preventing everywhere else. The two mechanically-checkable things
are gated: (a) every `task <name>` a README mentions must exist in `task --list` (which would have
caught a README over-promising what `task run:all` does), and (b) every module `LICENSE` must be
byte-identical to the root (a diff, over sixteen copies of a 190-line file). The READMEs themselves
are written to **prefer prose that cannot go stale** — pointing at `task --list` and
`docs/architecture/` rather than transcribing 41 task descriptions or restating a rule that will
diverge from its source.

**5. The licence is Apache-2.0 and is propagated to every module.** The root `LICENSE` is
authoritative and was **copied byte-identically** (proven by `diff`) into every directory that roots
a build unit — every Dart package and every Java module, including the two `example/` apps,
`zen_demo_client`, and the `server/` parent aggregator: sixteen copies in all (two already existed).
Because **Maven and npm read metadata, not the file**, the file alone declares the licence to no
automatic reader on those tiers, so the same gap the file closes for Dart (pub.dev reads the file) is
closed for them in metadata: a `<licenses>` block in `server/pom.xml` (inherited by every module,
libraries and app servers alike) and a `"license": "Apache-2.0"` field in both `package.json` files.

**6. The contract-drift gate's proto watch is narrowed, because a required deliverable exposed it as
too broad.** `sync:verify` watched `proto/**` for drift; adding the required `proto/README.md` — a
documentation file, not a contract — turned `sync:contracts` red. The glob is scoped to the contract
sources it was always meant to watch, `proto/**/*.proto`. Verified: it still flags a real `.proto`
edit and no longer misreads a doc beside the contract as drift.

**7. Review corrections, made before this step was committed.** A read-through of the delivered
READMEs found five things wrong or missing, and they are part of this decision rather than a
follow-up, because each changes what the step claims:

- **Every publishable library gets its own README, not only the "publication-shaped" ones.** Point 2
  restricted per-package READMEs to packages already shaped for pub.dev. That premise was wrong:
  **all** the framework packages are publication-bound (STANDARDS "Code generation" names publishing
  as the exit condition), so `zen_core`, `zen_transport`, and `zen_identity` gained their own
  READMEs. Each carries a **"part of the jZen monorepo"** provenance note, as do the two `zen_ui_*`
  packages and `@jzen/admin-core`; the Java tier carries the same statement as Maven metadata
  inherited from `zen-parent`, because Maven reads metadata, not READMEs. It rides in
  `<description>` rather than `<url>`: Maven appends each module's artifactId to an inherited
  `<url>`, so every module would have advertised a path that does not exist, and the documented
  `child.project.url.inherit.append.path="false"` opt-out did not suppress it (checked with
  `help:effective-pom`). A description inherits verbatim.
  Packages that are never published — the two `example/` apps, `zen_demo_client`, the app's private
  admin panel — carry no note.
- **The deploy section said web and admin were excluded "by design". They are not; they are not yet
  built.** The backend has a Cloud Run path; the Flutter web bundle and the admin bundle have no
  deploy task, the backend container serves the API only, and in dev they run on their own origins
  behind CORS. That is unfinished work, and the README now says so. Only native mobile/desktop
  pipelines are genuinely left to each application.
- **"You copy the shape" was the wrong description of building an app on jZen**, and would have
  taught the opposite of the architecture. An application **depends on the libraries as versioned
  packages** and upgrades by bumping a version; a copied framework cannot be upgraded at all. Path
  dependencies are the distribution mechanism *until* the packages are published, not a licence to
  vendor source.
- **The server tier is labelled "Java/Quarkus", not "Java".** Naming only the language invited the
  reading that the backend is framework-free or hand-rolled. The two leaf modules `zen-proto` and
  `zen-core` remain deliberately Quarkus-free, and the module table still says so.
- **The reference app tells a first-time user how to sign in, on screen.** Documentation alone was
  insufficient for something every user meets before reading anything: `zen_demo` has no seeded
  account, and the login page now says so. `LoginScreen` (in `zen_ui_identity`) gained an optional
  **`banner`** slot — a framework mechanism carrying no wording, null by default, so the default
  screen is unchanged — and `zen_demo_client`'s `AuthFlow` fills it with a localized
  `DemoLocalizations` string. The framework supplies the slot, the application supplies the words:
  the same split ADR-007 drew for email and ADR-008 for jobs.

### What this supersedes, and why

- **ROADMAP Step 9's "`client/zen_demo/README.md`", the module map
  "`zen-proto/core/transport/identity/email/app`", and the repository-map bullet that omits `apps/`**
  (ROADMAP Step 9) → **corrected in place.** *Why:* three later ADRs (001, 008) moved the tree
  underneath a spec written at Step 0; following it literally would have produced files at paths that
  do not exist and a module map naming a module that was deleted and omitting one that was added.
- **ROADMAP Step 9's verification, "a new contributor can go from clone to a running `task run:all`
  … every command shown actually runs"** → **restated in the terms actually enforced.** *Why:* the
  human clone-to-run claim is real and was exercised, but the standing, mechanical guarantee is
  `task verify:docs`; the ROADMAP now states what the gate checks rather than only what a one-time
  walkthrough proved.
- **`sync:verify`'s `proto/**` watch** (STANDARDS "Code generation" describes the gate;
  `Taskfile.yml` `sync:verify` implements it) → **narrowed to `proto/**/*.proto`.** *Why:* the gate
  detects contract drift, and a README beside the contract is not a contract; the narrower glob
  watches exactly the source files and nothing else.
- **This entry's own point 2, "a publication-shaped package gets a README"** → **widened to every
  publishable library** (point 7). *Why:* the distinction it drew does not exist — every framework
  package is destined for a registry, so the ones without a README were simply the ones nobody had
  written yet.
- **MANIFESTO "What jZen explicitly discards"** → **retitled "Boundaries — what jZen is not", and
  its prose restated.** *Why:* "discards", "there is no … anywhere", and "Qute survives solely as"
  describe the *removal* of things from somewhere else, which is a frame a standalone product cannot
  use (ADR-011). The choices are unchanged; they now read as boundaries jZen holds rather than as a
  diff against a predecessor. **Earlier entries in this log cite the old title** (ADR-010's census
  row for a document store, and ADR-009's prose); because this log is sealed, those citations stand
  and **resolve to the retitled section** — this line is the mapping, exactly as ADR-011's table is
  the mapping for `TA-N`.

### Consequence

Fifteen tracked READMEs, and the rule that fixes the sixteenth. The diff is prose, licence files,
pom/`package.json` metadata, and two Taskfile edits (a new `verify:docs`, a narrowed `sync:verify`
glob).

**One behaviour change, deliberately.** Step 9 was scoped to prose and licence files, and everything
above holds to that except point 7's last item: `LoginScreen` gained an optional `banner` slot and
`zen_demo`'s login page now renders a localized sign-in hint. It is called out rather than smuggled
in, because a step that claims to change no behaviour must not quietly change some. The slot defaults
to null, so every existing caller renders exactly as before, and **every test count is unchanged** —
backend **50**, `zen-jobs` framework **10**, `test:client` **262** (`zen_ui_identity` still 39),
`test:apps:client` **11** (`zen_demo_client` still 11), `test:e2e` **10/10**.

`task build` and `task test` stay green after the licence propagation: adding files to sixteen module
directories disturbed neither the Maven reactor nor the two pub workspaces. `task sync:contracts` is
green ("Contracts in sync.", "Generated localizations correctly untracked."), `task verify:docs` is
green (all task references resolve; all sixteen `LICENSE` copies byte-identical to root), and both
`verify:docs` arms were shown to fail on injected drift — the task-reference arm caught a phantom
`stop:demo` in this step's own prose. **No structural change beyond the two Taskfile targets above:**
no framework module, no Flyway band claimed (200-299 remains free), no new dependency. Lockstep
versioning is unchanged at `0.1.0`.

**The ROADMAP's planned steps are complete** — there is no Step 10. Its remaining horizon is the
trigger conditions already written down: the second application under `apps/` (which exercises the
framework claim ADR-001 makes), and the capability triggers ADR-010 records for the six deferred
concerns, none of whose conditions is met today.

**That is not the same as production-ready, and this entry deliberately stops short of claiming it.**
Writing the READMEs surfaced work that no roadmap step ever covered: the framework packages are
unpublished (all `0.1.0`, `publish_to: none`, consumed by path), the web and admin surfaces have no
deploy path, and the Cloud Run deploy has never been executed end to end. Those are tracked as open
work rather than folded into this step's completion claim.

---

## ADR-011 — jZen is standalone; the decision log is sealed rather than rewritten

**Date:** 2026-07-23. **Status:** accepted. **Discharges:** ROADMAP Step 8.

### Decision

Step 8 removes every trace of the systems jZen was built from, so that the codebase explains itself
on its own terms. Five coupled choices, one of which is a genuine conflict between two rules this
project holds:

**1. The strip covers everything a reader or a contributor sees.** Source comments, `pom.xml` and
`pubspec.yaml` prose, `application.properties`, `supabase/config.toml`, the `.proto` files,
`MANIFESTO` / `BLUEPRINT` / `ROADMAP` / `STANDARDS`, both `CHANGELOG.md` files, the agent-facing
`CLAUDE.md` and `.claude/skills/`, and one pair of `.arb` files whose text a *user* could read.

**2. `DECISIONS.md` is sealed, not rewritten — and this is the one real decision in the step.**
ROADMAP Step 8 says to strip every reference, and its verification line says a grep must return
nothing. Applied literally to this log, that destroys the thing the log exists for. Its own charter
is "every drift from a prior decision is recorded here with its justification so the reasoning is
never lost", and in several entries the justification *is* the evidence: ADR-010 is a census whose
subjects are package names, ADR-008 declines a specific job-type triad, ADR-009 retires a package
because the constraint that motivated it belonged to another system. Rewriting those leaves
justifications that no longer parse - "not ported", but what wasn't? - and deleting them reopens
decisions that were settled on evidence no longer in the tree.

Four things resolve it, and they all point the same way:

- **Step 8's own scope clause already excluded this file.** It names "source comments, `pom.xml` /
  `pubspec.yaml` prose, `application.properties` comments, and these **four** docs". There are five
  architecture documents; "the four architecture docs" has meant `MANIFESTO`, `BLUEPRINT`,
  `ROADMAP`, `STANDARDS` since ROADMAP Step 0, with `DECISIONS` always cited separately. The scope
  clause is precise and the verification line is loose, so the verification line is what gets fixed.
- **ADR-010 pt.10 already did the work this depends on.** It deliberately phrased every
  forward-looking trigger in jZen's own terms "so Step 8 can strip citations without re-opening any
  of these decisions." The *live* content of this log is therefore already standalone; what remains
  is retrospect, which is the part an archive is for.
- **The log already has this norm.** ADR-009 kept ADR-004 "in this log unedited, as the record of a
  deferral that was honoured rather than forgotten."
- **A rewritten archive cannot be audited.** Once an accepted entry can be edited to match present
  circumstances, no entry can be trusted to say what was actually decided - and that failure is
  silent, which is the kind this project rejects everywhere else.

**3. The verification is a check that was run, not a standing gate.** It searches every **tracked**
file and excludes exactly one path, this log. Tracked rather than working-tree, so an untracked
local file cannot report a failure no clone would see.

Installing it as a permanent Taskfile target was tried and reverted. Step 8 is terminal: nothing in
the project produces these references any more, so the target would guard a failure mode that has
stopped occurring - and, holding the pattern it searches for, it would have had to exempt its own
definition, adding a second exemption that existed only because the first one did. The rule it
would enforce is better placed where a contributor meets it: STANDARDS, and `CLAUDE.md`'s
instruction to explain things on jZen's own terms. ROADMAP Step 8 states the search in words rather
than quoting a pattern that would match the document quoting it.

**4. The Technical Assessments section is deleted, and its rules are folded into STANDARDS.** TA-1
through TA-7 documented gaps between what jZen needed and what it started from, which is a category
that stops existing at this step. But three carried live rules `STANDARDS` did not yet state, and
deleting the section without folding them in would have lost a rule while deleting a citation:

| | Disposition |
|---|---|
| TA-1 | **Folded.** The `Response` + `@APIResponse(@Schema(ref=…))` + static `META-INF/openapi.yaml` merge is now STANDARDS "OpenAPI and the REST surface". Its other two findings (no server-side `quarkus-rest-jackson`; Jandex on every library module) were already carried. |
| TA-2 | **Folded.** "Every endpoint declares its own request and response messages; no generic payload type and no envelope" is now under STANDARDS "Source of truth". |
| TA-3 | **Deleted.** Closed by ADR-009; the package it described no longer exists and no rule survives it. |
| TA-4 | **Reworded in place.** STANDARDS "Deployment model" already carried the rule; it now states the constraint (nothing may sit between the client and Cloud Run that strips or renames cookies, and what it would cost to introduce one) instead of the history. |
| TA-5 | **Deleted.** A gap resolved in code at step 3; no rule survives it. |
| TA-6 | **Folded.** The client's two invariants - default format from `selectDefaultCodec()`, and a decode failure surfacing a `ZenError` rather than a null - are now STANDARDS "Failures surface; nothing is swallowed", together with the rule that no task swallows a failure. |
| TA-7 | **Deleted as a duplicate.** It was already restated verbatim as STANDARDS "Client config is compile-time (non-negotiable)". |

**The `TA-N` vocabulary had spread well beyond the section**: roughly 45 tracked files referenced an
assessment by number, including `.claude/skills/`, `Taskfile.yml`, `admin/`, Java sources, Dart
sources, tests, and YAML. None was caught by the reference grep, and every one would have become a
pointer into a section that no longer exists. All were repointed to the rule that now carries them.

**5. `CLAUDE.md` is in scope, though it is not one of the four docs.** It is the first file every
future contributor and agent reads, and it carried the "cite the source - for now" instruction. A
standalone product whose entry-point document tells the next contributor to cite sources that no
longer exist would undo this step at the first commit after it.

### What this supersedes, and why

- **STANDARDS "Fidelity to the source"** → **retired, which is what it was written to be.** It
  said so itself: "These citations are deliberate, removable scaffolding: ROADMAP step 8 strips
  every reference." Its read-only rule generalizes and survives as STANDARDS "Work happens inside
  this repository"; its do-not-carry-bugs-forward rule survives as the concrete invariants in
  "Failures surface; nothing is swallowed"; the citation rule is gone.
- **ROADMAP Step 8's verification, "`grep -ri …` (outside git history) returns nothing"** →
  **restated over tracked files, excluding this log.** *Why:* the original could not be satisfied as
  written without destroying this archive; and taken over the working tree rather than tracked
  files, it could be held red by a file no clone contains. It is also no longer quoted verbatim in
  the ROADMAP, because a document recording the removal of a pattern necessarily contains that
  pattern - the check is described in words instead.
- **MANIFESTO "Provenance, and its expiry"** → **deleted, having expired exactly as it predicted.**
  It promised that "the final roadmap step strips every reference and rewrites these documents to
  stand on their own; from that point jZen has only its own philosophy, its own history, and its own
  name." That point is now.
- **BLUEPRINT "Technical Assessments" (TA-1..TA-7)** → **deleted, with three rules folded into
  STANDARDS** per the table above. Earlier entries in this log refer to these by number; that table
  is where those references resolve from now on.
- **Both `CHANGELOG.md` files' `0.1.0` entries** → **rewritten** to describe what the release
  contains rather than what it was derived from. *Why:* a changelog ships inside the published
  package to consumers with no knowledge of this project's history, and `0.1.0` is unreleased, so
  no published record is being altered.
- **`client/pubspec.yaml`'s note recording `zen_localization`'s retirement** (ADR-009) →
  **deleted.** *Why:* a workspace list should describe the packages that exist. ADR-009 is the
  permanent record of the one that does not.

### Consequence

No tracked file outside this log names a system jZen was built from. The vocabulary is uniformly
jZen's, which is what makes **ROADMAP Step 9 (READMEs) writable** - there is now exactly one way to describe this codebase, so a README cannot
contradict the documents beneath it.

**No behaviour changed.** The diff is comments, prose, and regenerated generated-comments. The
seven references inside tracked `.pb.dart` files were cleared by fixing `common.proto`,
`demo.proto`, and `identity.proto` and running `task generate:proto` - never by editing generated
output, which STANDARDS forbids and `sync:contracts` is built to catch. **No structural change:**
no framework module, no Taskfile target, **no Flyway band claimed** (200-299 remains free), no new
dependency in any `pom.xml` or `pubspec.yaml`. Lockstep versioning is unchanged at `0.1.0`.

**One rule was earned the hard way and is now written down.** The three Flyway migrations carry
comment blocks, and editing them changed their checksums - Flyway hashes the whole file, comments
included - so every database that had already applied them refused to boot. It surfaced as a red
`test:e2e` against the local stack. Because jZen has never been deployed or published, no database
beyond a local one was affected and the clean comments were kept; a local reset was the entire cost.
This was the last moment that was true, and STANDARDS "Database migrations" now says so: **an
applied migration is immutable, including its comments.** Exempting `db/migration/*.sql` from the
verification was considered and rejected - the references there were pure provenance carrying no
reasoning, so removing them cost nothing, and a check that passes while the tree still names those
systems would be decoration. **This log is the only exclusion, and it is argued on archival grounds
rather than convenience.**

**One item is deliberately left alone.** `ZenTransportFormat.parseOrNull` accepts `"msgpack"` as an
alias for the binary format. No test asserts it and no jZen client sends it, but removing the branch
would change what an inbound `X-Zen-Transport: msgpack` resolves to (binary today, JSON after), and
this step changes no behaviour. Its comment no longer explains the value by naming where it came
from. Removing the alias is a small behavioural decision for a later step.

---

## ADR-010 — The deferred donor packages are settled: a complete census, six "never", and nothing ported

**Date:** 2026-07-23. **Status:** accepted. **Discharges:** ROADMAP Step 7, "Deferred package ports".

### Decision

Every package in the DartZen donor now has a disposition, and the open-ended "port only when a
consumer needs them" list is closed. **Nothing is ported by this step.** The verdict on all six
remaining packages is **never port the donor package**; where the underlying *capability* could
still be wanted, the trigger is written below in jZen's own terms, naming no donor path, so Step 8
is a mechanical strip rather than a second round of decisions.

**1. The census is complete, which the deferred list never was.** Sixteen packages, three verdicts:

| Donor package | LOC | Verdict | Where it stands |
|---|---|---|---|
| `dartzen_core` | 758 | **ported** | `zen_core` + `zen-core` (step 2) |
| `dartzen_transport` | 1579 | **ported** | `zen_transport` + `zen-transport` (steps 1-2) |
| `dartzen_identity` | 1005 | **ported** | `zen_identity` + `zen-identity` (step 3) |
| `dartzen_ui_navigation` | 693 | **ported** | `zen_ui_navigation` (step 3) |
| `dartzen_ui_identity` | 1274 | **ported** | `zen_ui_identity` (step 3) |
| `dartzen_jobs` | 1892 | **ported** | `zen-jobs` (step 7a, ADR-008) |
| `dartzen_localization` | 378 | **ported, then retired** | `zen_localization`, deleted at step 7b (ADR-009) |
| `dartzen_firestore` | 1150 | **never** | MANIFESTO "What jZen explicitly discards"; Supabase/Postgres |
| `dartzen_server` | 687 | **never** | MANIFESTO; the Quarkus backend is the server |
| `dartzen_ui_admin` | 1317 | **never** | MANIFESTO; react-admin per ADR-005, confirmed dropped at step 5 |
| `dartzen_telemetry` | 425 | **never** | pt.3 below |
| `dartzen_executor` | 1337 | **never** | pt.4 below |
| `dartzen_cache` | 750 | **never** | pt.5 below |
| `dartzen_storage` | 703 | **never** | pt.6 below |
| `dartzen_payments` | 1708 | **never** | pt.7 below |
| `dartzen_ai` | 2322 | **never** | pt.8 below |

The last three "never" rows in the upper block were already decided in the MANIFESTO and the
ROADMAP's "Explicitly out of scope", but **the deferred list never named them**, and an unnamed
package is exactly what makes Step 8's `grep` gate ambiguous. They are restated here so the census
is closed rather than merely believed to be.

**2. The six deferred packages are a closed dependency island, and its root has no consumers.**
This single measurement decides most of what follows. Counting every `pubspec.yaml` dependency and
every `package:` import across the whole donor, outside each package's own directory:

- `dartzen_ai` depends on cache, executor, telemetry, localization, transport, core. Its own
  consumers: **none**, in any package or app, including ZenDemo.
- `dartzen_executor` consumers: `dartzen_ai` only. `dartzen_cache` consumers: `dartzen_ai` only.
- `dartzen_payments` consumers: **none**.
- `dartzen_telemetry` consumers: `dartzen_ai`, `dartzen_payments`, `dartzen_jobs`.
- `dartzen_storage` consumers: `dartzen_server` and `dartzen_demo_server`, **both already deleted by
  decisions taken** (MANIFESTO; ROADMAP step 4).

So four of the six have no live consumer even in the donor; telemetry's only surviving consumer
path was `dartzen_jobs`, which jZen ported as `zen-jobs` **without** it (ADR-008), proving by
construction that it was not required; and storage's consumer count in jZen terms is zero by
construction. The island exists to serve a package nothing uses.

**3. `dartzen_telemetry` is not ported, and no `zen-telemetry` library is created.** ADR-008 already
removed its stated rationale. What remains does not survive its own evidence: `TelemetryStore` is
two methods, `TelemetryClient` is a four-method pass-through over it, and the only implementation is
`FirestoreTelemetryStore` - the package's `pubspec.yaml` declares a dependency on
`dartzen_firestore`. "The one clean store abstraction in DartZen" is an abstraction over the one
backend jZen discarded at MANIFESTO level.

Its semantic-event model (`auth.login.success` with user, session, and correlation ids) *is*
genuinely additive over what jZen has: `zen_jobs` rows are per-job operational state, Micrometer
counters are aggregates that cannot be queried per user, and structured logs are not queryable at
all. That is why this is a decision and not an oversight. It is nonetheless **not framework work**,
on ADR-001's axis: *which* events matter is product content, exactly as wording was for email
(ADR-007) and job identity was for scheduling (ADR-008). The mechanism a framework would own here is
Panache plus Flyway, which every jZen application already inherits. A `server/zen-telemetry` claiming
Flyway band 200-299 would ship a framework-owned table that **no framework code writes to**.

It also does not arrive free: per-user event rows land directly on `users.analytics_consent`, a GDPR
column the framework already carries, and would have to be anonymised by `UserRetentionService`
alongside the profile. Taking on a compliance obligation for a table with no consumer is the
opposite of what step 7a spent its effort discharging.

> **Trigger.** When a jZen application needs to answer a question about user behaviour over time
> that `zen_jobs` rows, Micrometer counters, and structured logs cannot answer, it defines its own
> event table in its own application migration band (1000+) and honours `users.analytics_consent`.
> It is promoted to `server/zen-telemetry` with a reserved band only when a **second** application
> needs the same table - the same evidence bar ADR-008 set for promoting `JobClock` into `zen-core`.

**4. `dartzen_executor` is not ported: it solves a constraint jZen does not have.** Its entire
`light` / `medium` / `heavy` taxonomy is a Dart event-loop concern. `light` runs inline, `medium`
runs in a `dart:isolate` with an enforced timeout, and `heavy` dispatches to `dartzen_jobs`. The
middle tier exists because a Dart server is single-threaded and CPU work blocks the event loop.
Quarkus has no such constraint: a JAX-RS resource already runs on a worker thread pool, and
`@Blocking` / `@NonBlocking` / `ManagedExecutor` are platform primitives. The `heavy` tier is
`zen-jobs`, already shipped - and ADR-008 already declined the donor's `endpoint` (Cloud Tasks) job
type that heavy dispatch targets, so the routing decision this package exists to make has no
remaining destinations.

It would also resurrect retired code: `ZenExecutor`'s constructor takes a `ZenLocalizationService`,
the mechanism ADR-009 deleted. **This is TA-3's shape exactly** - the technique was right for the
donor's runtime, the runtime is not jZen's, and the indirection goes with it. There is no trigger:
the capability is the JVM's.

**5. `dartzen_cache` is not ported.** Two implementations sit behind a four-method `CacheClient`
(`set`/`get`/`delete`/`clear`): an in-memory map, and `MemorystoreCache`, a **hand-written RESP
protocol client over a raw `dart:io` Socket** carrying `@visibleForTesting` socket-factory injection
hooks in the production file. STANDARDS "Deployment model" states that at `--max-instances=1`
in-process state is *valid by construction*, and that raising max-instances is the documented
trigger to externalize. So the Redis half solves the problem jZen deliberately does not have, and
the in-memory half is `quarkus-cache` - one annotation against 750 LOC.

**The Java precedent is zero, not substantial.** The BugEater files matching "cache" are
`Cache-Control` HTTP *response headers*, an unrelated concept; there is no `io.quarkus.cache`, no
`@CacheResult`, and no Redis anywhere in that codebase. The existing trigger in STANDARDS is
sufficient and needs no restatement: **raising `--max-instances` above 1 is the trigger to
externalize state**, and at that point the answer is the `quarkus-redis-client` extension, not a
hand-written RESP client.

**6. `dartzen_storage` is not ported, and `server/zen-storage` is not created now.** The package is
a read-only `ZenStorageReader.read(key)` over the GCS and Firebase SDKs, and its own barrel states
it is "explicitly GCS-focused" and "NOT a multi-cloud abstraction" - so it structurally cannot
front Supabase Storage, which is what jZen runs.

The Java evidence answers the "abstraction or passthrough?" question empirically, and answers it
against a library: BugEater's *entire* object-storage implementation is `SupabaseStorageClient`, a
**34-line `@RegisterRestClient` interface with two `GET` methods that differ only in `@Produces`**.
The ~60 remaining matches are call sites building public URL strings. A `zen-storage` library would
be that passthrough. MANIFESTO settles it directly: real dependencies are first-class and "not
smuggled behind a portability layer that no second implementation will ever justify."

> **Trigger.** An application that needs object storage declares its own `@RegisterRestClient`
> against Supabase Storage (or an S3 SDK, since the service is S3-compatible) in its own app server.
> Promote it to `server/zen-storage` only when a **second** application needs the same client.

**7. `dartzen_payments` is not ported, and payments is an application concern.** 1708 LOC across 25
files with **zero consumers anywhere in the donor**, wired to Adyen and Strapi, depending on
`dartzen_localization` (retired) and `dartzen_telemetry` (never ported), and shipping its
`TestExecutor` / `LocalExecutor` scaffolding inside the public API. The Java side has **no
implementation to harvest**: three incidental matches, none a payment flow.

Where there is no Java precedent, "port" is the wrong word - it would be greenfield Java design
merely *informed* by an unconsumed Dart package, a different order of cost and a different claim
about provenance. And on ADR-001's axis it is application work: a provider, its currencies, its tax
treatment, and its webhook contract are product policy. The framework share would be
`quarkus-rest-client` plus a table, which is not a mechanism worth a library until a second
application shares it.

> **Trigger.** When a jZen application sells something, it implements checkout in its own app server
> against its chosen provider's SDK, and writes its own migrations in the application band (1000+).
> `server/zen-payments` is created only when a **second** application needs the same integration.

**8. `dartzen_ai` is not ported.** 2322 LOC hard-wired to GCP Vertex AI and Gemini, with **zero
consumers** and **zero Java precedent**. It is the sole reason cache, executor, and telemetry exist
in the donor, so porting it means porting the whole island of pt.2. Its stated contract is that
"All AI operations MUST be executed via ZenExecutor" - a mandate that only makes sense under the
event-loop constraint pt.4 just retired. A provider-specific client written against one vendor's
2025 API is also the fastest-ageing code in the donor.

> **Trigger.** When a jZen application needs a model, it uses a maintained Quarkus extension in its
> own app server. jZen does not write its own vendor client.

**9. Micrometer stays in the application, not the framework.** `quarkus-micrometer-registry-prometheus`
is declared in `apps/zen_demo/zen_demo_server/pom.xml` and belongs there. A *registry* binding is a
deployment choice - which system scrapes you, on what protocol - and by ADR-001's axis that is
policy, not mechanism. Promoting it to a framework library would force every jZen application to
expose Prometheus metrics whether or not its host scrapes them. This is the same reasoning that
keeps mail wording (ADR-007) and job identity (ADR-008) application-side.

**10. Resolving this list before Step 8 is itself part of the decision.** Step 8 strips every donor
reference from the repository and rewrites these docs to stand alone, which makes the ordering
load-bearing rather than incidental:

- A package ported **after** Step 8 either reintroduces the citations Step 8 just removed, or is
  ported with no citation at all, violating STANDARDS "cite the source - for now."
- Leaving an open-ended "port when demanded" list **through** Step 8 is worse: as written it points
  at `../DartZen/packages/...` paths that Step 8 exists to erase, so **Step 8 could not honestly
  complete while the list stood**. A deferral that cites a path the next step deletes is not a
  deferral, it is a dangling reference.

That is why "never" had to be an available answer and why most of the list receives it. Every
trigger above is phrased in jZen's own terms - an application, a second application, a
`--max-instances` value - and none names a donor package or path, so Step 8 can strip citations
without re-opening any of these decisions.

### What this supersedes, and why

- **"Deferred package ports - port only when a consumer needs them"** and the five-package line
  **"`dartzen_executor`, `dartzen_payments`, `dartzen_ai`, `dartzen_cache`, `dartzen_storage`
  (→ Supabase Storage / S3) - no committed target until demanded"** (ROADMAP Step 7) → **closed and
  replaced by the table above.** *Why:* "deferred with no trigger" is indistinguishable from "not
  decided", and it was the last thing blocking Step 8 (pt.10). Each package now has a verdict, and
  each surviving capability has a testable trigger.
- **"`dartzen_telemetry` → a Panache-backed store (its `TelemetryStore` is the one clean store
  abstraction in DartZen). Pairs naturally with 7a, which needs somewhere to record job runs"**
  (ROADMAP Step 7) → **retired in both halves.** ADR-008 already answered the second clause ("Job
  runs are recorded in the `zen_jobs` row they belong to"); pt.3 answers the first: the abstraction
  is two methods over Firestore, the backend jZen discarded. *Why:* the sentence outlived both of
  its premises and would otherwise have been carried into a standalone document as a plan.
- **"A telemetry store remains deferred on its own merits, not as a prerequisite of this step"**
  (ADR-008, "What this supersedes") → **resolved.** Those merits were weighed here and did not
  carry; pt.3 records what a store would genuinely add and why it is still application work.
- **"These are defaulted/nullable now and their behavior is wired in later steps (email deletion
  warnings in step 6, payments in step 7)"** (BLUEPRINT "Persistence") and **"`is_premium` both
  exempts an account from that cycle and awaits payments in step 7"** (`User.java` javadoc) →
  **corrected.** Payments is not a step-7 deliverable and is not coming as framework work (pt.7).
  The **column stays and is already load-bearing**: `UserRetentionService` reads it for the premium
  exemption and `AdminUserResource` exposes it for administration. *Why:* a doc that promises a
  capability the next ADR declines would be carried verbatim into Step 8's standalone rewrite, which
  is precisely the drift this log exists to stop. Both wordings are updated to match.
- **`dartzen_firestore`, `dartzen_server`, and `dartzen_ui_admin` as decisions recorded only in
  prose** (MANIFESTO "What jZen explicitly discards"; ROADMAP "Explicitly out of scope"; ROADMAP
  step 5) → **unchanged in substance, entered into the census.** *Why:* the decisions were already
  correct; they were simply absent from the one list Step 8 will check against, and a package named
  nowhere cannot be verified as handled.

### Consequence

**Nothing is ported, and the port list is empty.** ROADMAP Step 7 is complete: 7a (`zen-jobs`), 7b
(typed client i18n), and 7c (this census) are all discharged, with no open sub-item. No framework
module is created, **no Flyway band is claimed** (200-299 remains free and the STANDARDS table is
unchanged), no Taskfile target is added, and no dependency enters any `pom.xml` or `pubspec.yaml`.
Lockstep versioning is unchanged at `0.1.0`.

The four surviving capabilities each have a trigger that is a testable condition rather than a
sentiment - a second application, an application that sells something, an application that needs a
model, a `--max-instances` above 1 - and none of them names a donor package, so they survive Step 8
verbatim.

**Step 8 is unblocked.** Its scope is now measured rather than assumed: 111 files carry a `dartzen`
or `bugeater` reference (excluding `.git`, `target`, `node_modules`, `.dart_tool`, and `build`), and
none of them is now a deferral pointing at a path Step 8 must delete.

Verified: no behaviour changed - the diff is three architecture documents plus one javadoc in
`User.java` - so the verification is that the baseline holds, measured before the edits and re-run
after rather than assumed. `task build` exits 0 and
`task test` exits 0 at their existing numbers: the backend suite is **50 tests, 0 failures**;
`task test:client` is **262** (`zen_core` 88, `zen_identity` 45, `zen_transport` 47,
`zen_ui_identity` 39, `zen_ui_navigation` 41, navigation example 2); `task test:apps:client` is
**11**; and `task test:e2e` is **10/10** against live Supabase + Quarkus. `task sync:contracts`
reports contracts in sync, including the ADR-009 check that generated localizations stay untracked.
Every figure matches what ADR-009 recorded, which is the point: no code changed.

---

## ADR-009 — Client i18n is typed and generated: `flutter gen-l10n` per package, and `zen_localization` is retired

**Date:** 2026-07-23. **Status:** accepted. **Discharges:** ADR-004.

### Decision

Six coupled choices for the Step-7b client-i18n capability, all following from one asymmetry
ADR-004 recorded and deliberately parked: the server went **typed and generated** for messages
(ADR-002, Qute `@MessageBundle`) while the client stayed **stringly-typed** - a hand-rolled
`ZenLocalizationService` looking string keys up at runtime in per-locale JSON. The two stacks now
make the same choice.

1. **The generator is Flutter's own: `intl` + ARB + `flutter gen-l10n`, not `slang`.** ADR-004
   named both as idiomatic; the tie-breaker is the reasoning ADR-002 already used. The server did
   not pick the best available i18n library, it picked **the platform's own typed mechanism**, so
   the client's answer is the one that ships inside the Flutter SDK. Three consequences follow and
   all of them matter here: no third-party dependency in a framework package; STANDARDS "only
   industry-standard, inspectable generators" is satisfied without argument; and the generated
   class plugs into `MaterialApp.locale` / `Localizations`, so **a runtime locale switch re-renders
   by the framework's own mechanism** rather than by a global mutable setting (`slang`'s
   `LocaleSettings`) that the widget tree has to be taught to observe.

2. **`zen_localization` is retired, not wrapped.** ADR-004 offered replace / wrap / retire. Every
   capability the package had is subsumed: the runtime JSON load, the string-key lookup, the
   dev-versus-prod merged-bundle split, `{param}` interpolation, the cache, and the
   conditional-import loader. A wrapper would have preserved the string-key API *this step exists to
   delete*, so it earns nothing. The package leaves `client/pubspec.yaml`'s workspace list and all
   four consuming pubspecs, and its **12 test files go with the mechanism they tested** - they
   asserted that a key reached a lookup table, and there is no lookup table now. What was worth
   keeping became typed tests instead (below).

   **This also makes TA-3 moot.** That assessment made `flutter` a dev-only dependency and kept the
   `loader_flutter` / `loader_io` / `loader_stub` conditional import so *Dart-only server packages*
   could consume localization. That constraint was the donor's: jZen has no Dart server, and every
   consumer of these strings - `zen_ui_identity`, `zen_ui_navigation`, both examples,
   `zen_demo_client` - is a Flutter package. The indirection was solving a problem jZen does not
   have, and it is gone with the package.

3. **Each package generates its own accessors; the application composes delegates.** `zen_ui_identity`
   owns `IdentityLocalizations`, `zen_ui_navigation` owns `NavigationLocalizations`, an app client
   owns its own (`DemoLocalizations`), each from its own `lib/src/l10n/*.arb` and its own `l10n.yaml`.
   An app registers the set it renders:

   ```dart
   localizationsDelegates: const [
     ...DemoLocalizations.localizationsDelegates,   // plus Flutter's Material/Cupertino/Widgets
     IdentityLocalizations.delegate,
     NavigationLocalizations.delegate,
   ],
   ```

   This is the gen-l10n norm and keeps a framework package able to render its own UI without an
   application supplying its wording - the same axis ADR-007 drew for email and ADR-008 for jobs.
   It also **fixes a live defect**: `zen_demo`'s merged `en.json`/`uk.json` hand-duplicated ~28
   identity and navigation keys, two copies of the same wording with nothing keeping them equal.
   Those keys are simply gone from the app.

4. **The generated output is BUILT, NOT TRACKED - the opposite of the `.pb.dart` rule, for the same
   reason.** STANDARDS "Code generation" tracks an artifact exactly when the toolchain that consumes
   it cannot produce it. `protoc` + `protoc-gen-dart` are a *system* install a Flutter developer
   would not otherwise have, so the Dart messages are committed; `flutter gen-l10n` is **part of the
   Flutter SDK that every consumer of these packages already runs**, so there is no boundary to
   carry the result across. `**/l10n/generated/` is gitignored, `task generate:l10n` produces it,
   and `build:client` / `build:apps:client` / `test:client` / `test:apps:client` run that task
   first so a clean checkout never analyzes a missing file.

   **It lives under `lib/src/`**, beside the ARB files and exactly where the retired JSON bundles
   sat - the same place `zen_transport` keeps its committed protobuf output. Generated code is
   implementation, so it belongs in `src/` like the rest of a package's implementation, reached
   publicly only through the barrel `export`. It also keeps every intra-package import one level
   deep (`../l10n/generated/…`, matching the sibling `../state/`, `../widgets/`, `../theme/`)
   rather than the `../../` a `lib/l10n/` output directory forces. Relative, not `package:`, is
   deliberate: Effective Dart prefers relative imports within a package's own `lib/`, and the
   enabled lints (`flutter_lints`) forbid only reaching *across* packages
   (`avoid_relative_lib_imports`, `implementation_imports`). The `zen_ui_navigation` example is the
   one exception, at `lib/l10n/`, because it has no `lib/src/` layer at all.

   **The gate is inverted to match.** `sync:contracts` asks of the proto/OpenAPI artifacts "did
   regeneration change a committed file?"; for the localizations it asks the mirror question, "is
   any of this output tracked?", and fails if so. That is the enforceable form of this decision: a
   generated file that is not in git cannot be hand-edited into the build. Drift between an ARB and
   its call sites needs no gate at all - it is a compile error, which is the entire point of going
   typed.

5. **`{en, uk}` parity is real, and there is one client-side declaration of it.** `zen_ui_identity`
   and `zen_ui_navigation` shipped **English only**; their Ukrainian wording already existed, copied
   into `zen_demo`'s merged `uk.json`, so the modules were half-localized while the app looked
   complete. Both now ship both locales, taken from those existing strings verbatim, and so does the
   navigation example (which gains a language toggle, since a locale nothing can select is not
   shipped). Alongside them, **`ZenLocales` in `zen_core`** mirrors the server's
   `zen.core.i18n.ZenLocales`: `supported = [en, uk]`, `fallback = en`, and `resolve(tag)` matching
   on the primary subtag. Each localized package has a test asserting its generated
   `supportedLocales` equals `ZenLocales.supported`, so a package whose ARB set drifts fails the
   suite instead of silently offering a language the server will not answer in.

6. **This reinforces TA-7; it is not an exception to it.** Typed generated strings are Dart
   constants compiled into the binary and tree-shaken per build, which is *more* compile-time than
   what they replace: the runtime JSON path is gone, `assets/l10n/` and the per-package l10n asset
   declarations are gone, and with them the app's localization boot phase (`zen_demo` no longer
   shows a spinner waiting for bundles - there is nothing to fetch before the first frame). Nothing
   in the l10n path is platform-conditional any more, so there is no web/native bundle split for
   locale data to leak across. `ZEN_ENV` / `ZEN_PLATFORM` are untouched: the locale is *app state*,
   not config, which is exactly why it stays runtime-selectable while config does not.

**The ambient locale (ADR-007) is preserved end to end, and is now one value doing both jobs.**
`languageProvider` (a `String`) becomes `localeProvider` (a `Locale`, typed over stringly-typed like
everything else here). It is `MaterialApp.locale`, so switching it re-renders every screen through
`Localizations`; and `main.dart` still hands `ZenClient` a *callback* over the same notifier -
`() => container.read(localeProvider).languageCode` - so a mid-session switch still reaches the next
request as `Accept-Language`, including `POST /auth/register`, where the server seeds
`users.language` and every later localized email follows from it. The language-code conversion
happens once, at that seam.

**Screens resolve their own wording.** `zen_ui_identity`'s screens no longer take a `messages:`
argument; each calls `IdentityLocalizations.of(context)`. That deletes the threading layer in
`app.dart`, `HomeShell`, `AuthFlow` and both examples, and it is what makes a locale change a single
rebuild rather than a re-plumbing. The one part of `IdentityMessages` that was never a message -
mapping a `ZenError` to *which* message it deserves - survives as `IdentityErrorText.errorText`, an
**extension on** the generated class: logic does not belong inside generated output, and an
extension keeps it typed without touching it.

### What this supersedes, and why

- **"Keep `zen_localization` for now ... evaluate migrating to `intl`/`gen-l10n` or `slang`"**
  (ADR-004, status *deferred*) → **discharged.** ADR-004 is now historical; the evaluation it asked
  for is pt.1 above and its three-way question is answered by pt.2. It stays in this log unedited,
  as the record of a deferral that was honoured rather than forgotten.
- **"Typed, generated client i18n ... deferred but committed to a plan"** (ROADMAP Step 7,
  "Framework improvements") → **delivered**, and marked done with the verification below.
- **TA-3's resolution, "keep its existing conditional-import pattern ... and move `flutter` to a
  dev-only dependency so `zen_localization` is Dart-pure"** (BLUEPRINT) → **obsolete, not reversed.**
  The technique was correct for the constraint; the constraint was the donor's and does not exist in
  jZen (pt.2). TA-3 is now annotated as closed by the retirement.
- **"`client/` ... `zen_core`, `zen_transport`, `zen_identity`, `zen_localization`, `zen_ui_*`"**
  (ADR-001; BLUEPRINT layout; CLAUDE.md) → **one package shorter.** The framework client libraries
  are `zen_core`, `zen_transport`, `zen_identity`, `zen_ui_*`.
- **The donor's `dartzen_localization`** (`../DartZen/packages/dartzen_localization`) → **superseded
  on the client.** Its port is deleted rather than evolved. *Why:* STANDARDS forbids carrying donor
  limitations forward, and stringly-typed lookup with a production mode that silently returns the
  key on a miss is precisely such a limitation - the missing string reached the user as
  `login.title`. Under generated accessors that failure cannot be written.
- **`zen_demo`'s merged bundles as the app's localization model** (`assets/l10n/{en,uk}.json`, the
  "production-mode localization: a single merged file per language" comment in `DemoMessages` and
  `providers.dart`) → **deleted.** *Why:* pt.3 - the merge existed only because packages could not
  own their strings, and it made every framework string an app's copy-paste responsibility.

### Consequence

Adding a locale to jZen is now symmetric on both stacks and needs no code edit on either: server -
a `@Localized` bundle variant plus its templates; client - one ARB file per localized package; then
the tag in `ZenLocales` on each side. Adding a *string* to a framework package no longer touches any
application. A new localized package declares an `l10n.yaml`, sets `flutter: generate: true`, and is
picked up by `task generate:l10n` automatically (it discovers by `l10n.yaml`, not by a list). Two new
dependencies appear in the localized packages, `flutter_localizations` (SDK) and `intl` pinned to the
`0.20.2` that `flutter_localizations` itself pins, so an app composing several jZen packages resolves
one `intl`. Lockstep versioning is unchanged at `0.1.0`.

Two latent defects surfaced when real wording replaced key strings and were fixed in passing: the
navigation example's home screen overflowed its viewport (it had only ever rendered bare keys,
because its bundles were never actually loaded) and is now scrollable; and
`AuthorityRolesScreen` had two hardcoded English literals (`"Not authenticated"`, `"No roles
assigned"`) inside a framework package, which are now ARB entries in both locales.

Verified: `task doctor` clean. `task build:client` and `task build:apps:client` analyze clean after
`generate:l10n`; `task build:apps:server` and `task test:apps:server` green (**50 tests, 0
failures**, unchanged - the server side of i18n was not touched). `task test:client` is **262 tests,
0 failures** (`zen_core` 88, `zen_identity` 45, `zen_transport` 47, `zen_ui_identity` 39,
`zen_ui_navigation` 41, navigation example 2), plus `task test:apps:client` **11**. The typed
behaviour is proven where the string-key tests used to be: `identity_localizations_test.dart` pumps
a real `LoginScreen`, asserts the English wording, pumps the same tree at `uk`, and asserts every
string re-rendered in Ukrainian and none of the English survived; `navigation_mobile_test.dart` does
the same for the overflow label the package owns; `demo_localizations_test.dart` proves one `Locale`
change re-renders **all three packages** at once *and* that the same provider read is what
`ZenClient` will send as `Accept-Language`. Three suites assert their generated `supportedLocales`
against `ZenLocales.supported`. `task sync:contracts` is green, including the new
tracked-localizations check, and rejects a generated l10n file that is added to the index.
`task test:e2e` is **10/10** against live Supabase + Quarkus, the "localized surface (en vs uk)"
case unchanged - the picked locale still reaches the server. `grep` for `ZenLocalizationService` over the tree returns nothing;
`zen_localization` survives only as prose recording its retirement (these docs, `CLAUDE.md`, and the
comment in `client/pubspec.yaml`'s workspace list).

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

---

## ADR-008 — Guaranteed scheduled work: an external trigger, due-ness from `last_run_at`, and no erasure without a delivered warning

**Date:** 2026-07-22. **Status:** accepted.

### Decision

Seven coupled choices for the Step-7a scheduling capability (`zen-jobs`), all following from one
fact already recorded in STANDARDS "Deployment model": under `--min-instances=0` the container
exists only while it is serving a request, so **in-process state is sound but in-process time is
not**.

1. **`zen-jobs` is a framework library; the application registers what to run.** The mechanism
   (`ZenJob`, `JobScheduler`, `JobState`, `JobTriggerResource`) lives in `server/zen-jobs`, and the
   trigger is a framework-owned JAX-RS resource served from the Jandex-indexed jar, exactly like
   `AuthResource` and `AdminUserResource` (ADR-001 pt.3). **`zen-identity` does not depend on
   `zen-jobs`**: it offers `UserRetentionJob.runCycle()` as a plain callable and knows nothing about
   scheduling, while `zen-jobs` knows how to run due work and nothing about users. The application
   joins them, in one 20-line class (`zen.demo.jobs.UserRetentionZenJob`). This is the same axis
   ADR-007 drew for email — the framework decides *that* something is due, the application decides
   *what* it is — and it keeps identity usable without the jobs table, the migration, and the
   trigger endpoint coming along.

2. **Due-ness is computed from `last_run_at`, never from "the timer fired."** `JobSchedule.isDue` is
   a pure function of the recorded last run, the interval, and an injected `now`. Nothing in the
   system observes ticks, so a tick missed while scaled to zero, mid-deploy, or during a scheduler
   outage costs nothing: the next tick sees a stale timestamp and the job is still due. This single
   property is what turns best-effort into a guarantee, and it is the reason a legal obligation can
   rest on it.

3. **Missed ticks coalesce: a due job runs once, not once per missed interval.** A job last run nine
   hours ago on an hourly interval runs exactly once, and `last_run_at` is stamped with that run's
   start rather than advanced interval by interval. jZen's jobs are reconciliations over current
   state ("anonymise every account whose final warning has expired"), not per-period batches, so
   replaying a backlog would repeat identical work. Stated once in `JobSchedule` as the framework
   contract for every job.

4. **The trigger authenticates with a shared secret header, not Google OIDC.** Cloud Scheduler sends
   `X-Zen-Job-Token`, compared in constant time against `zen.jobs.trigger.token`. Cloud Run serves
   jZen `--allow-unauthenticated` (Taskfile `deploy:cloudrun`), so this endpoint is internet
   reachable and platform IAM cannot guard it. Verifying Cloud Scheduler's OIDC token was rejected:
   `mp.jwt.token.header=Cookie` points SmallRye JWT at the Supabase session cookie, so a bearer
   token in `Authorization` is never parsed at all, and a second issuer would mean hand-wiring a
   second parser plus a live JWKS fetch that no hermetic test could satisfy. **The endpoint fails
   closed** — the framework declares no default token, so an unconfigured deployment rejects every
   call rather than accepting every call — and **a Supabase session is never sufficient**, admin
   included, which `JobTriggerResourceTest` asserts.

5. **One trigger endpoint with master-style batching**, ported from the donor's coordinator
   (`../DartZen/packages/dartzen_jobs/lib/src/master_job.dart`). N scheduler entries would mean N
   cold starts, fighting the single-instance cost model. Jobs run **sequentially**, each recording
   `last_run_at` / `last_status` / duration / error, and the tick returns a `JobTickResult` proto so
   a run is visible without reading the database. The **overlap guard is an in-process flag**, valid
   for the same reason in-process rate limiting is valid — at most one instance ever runs — and
   raising `--max-instances` above 1 is the documented trigger to move it to a Postgres advisory
   lock. `last_run_at` records that a job *ran*, not that it succeeded, so a failing job waits out
   its interval instead of retrying on every tick and hammering whatever broke it.

6. **No account is anonymised without a warning that was actually delivered**, and the modules stay
   decoupled. The retention cycle is inverted from *stamp, then fire asynchronously* to **find,
   notify, then stamp**: `UserRetentionService.findAccountsDue*Warning()` only reads,
   `UserRetentionJob` fires `AccountDeletionWarning` **synchronously**, and `stamp*Delivered()` is
   called only when the observer confirmed the event's `DeliveryReceipt`. `zen-identity` still names
   nothing in `zen-email`; it learns only that *something* confirmed delivery, so an application may
   warn users by any channel. The fire is synchronous because a retention cycle has no user waiting
   on it — the latency argument that made registration mail asynchronous does not apply — and only a
   synchronous fire can carry an answer back within the cycle that asked. **The failure mode is now
   safe by construction:** an undelivered warning leaves the timestamp null, so the account is found
   again next cycle instead of ageing toward erasure, and an application that observes nothing can
   never have its users erased.

7. **The clock is injectable, but scoped to `zen-jobs`.** `JobClock` produces a `Clock` (UTC) that
   `JobScheduler` injects, so due-ness, catch-up, and the recorded `last_run_at` are asserted at
   chosen instants rather than waited for. It was **not** promoted into `zen-core`: that module is
   deliberately zero-dependency pure Java ("Do not add framework deps here") and would have had to
   become a CDI bean archive to host a producer. `zen-jobs` is the only module that needs a
   controllable clock today — `UserRetentionService` keeps `OffsetDateTime.now()` because its tests
   are already deterministic by backdating rows — and a second consumer is the trigger to promote
   it, on evidence.

**Also settled, and written into STANDARDS:** each framework library owns a **reserved Flyway
version band** (`zen-identity` 1-99, `zen-jobs` 100-199, next library 200+, applications 1000+), so
two libraries can ship migrations to the same classpath `db/migration` without ever colliding on a
version. A location per module was rejected because it does not actually solve the problem: Flyway
versions must be unique across every location sharing one schema history, so it would need the band
convention anyway, plus per-application configuration.

### What this supersedes, and why

- **"`%prod` pins it off ... This leaves the GDPR obligation undischarged in production,
  deliberately and on the record"** (ADR-007 pt.4; ROADMAP Step 6; `application.properties`) →
  **discharged.** Retention now runs in production, driven from outside the container. The
  `zen.identity.retention.cron` property is **deleted** rather than re-pointed.
- **`UserRetentionJob`'s `@Scheduled` binding and `zen-identity`'s `quarkus-scheduler` dependency**
  (ROADMAP Step 6) → **removed.** *Why:* keeping a second, unsafe scheduling path beside the working
  one would invite an app to choose the path ADR-007 proved cannot fire, and two triggers on one
  data-destroying job is worse than none. Retention is now scheduled exactly one way. `runCycle()`
  stays a plain public method, which is what made this a configuration change rather than a rewrite.
- **"`AccountDeletionWarning` ... Applications observe them with `@ObservesAsync`"** and **"The stamp
  is committed before the event is fired"** (ADR-007 pt.2; the event's javadoc) → **reversed for this
  one event.** It is now observed synchronously and stamped afterwards, for the reason in pt.6 above.
  `UserRegistered` is unchanged and stays `@ObservesAsync`: registration is a user-facing request
  that must not wait for SMTP, and nothing depends on its outcome.
- **"a warning that failed to send still advances the clock toward anonymisation, and gating that
  needs the durable delivery state 7a introduces"** (ADR-007 pt.4) → **fixed, and more cheaply than
  predicted.** No durable per-warning delivery table was needed: the existing timestamp columns
  became the record, because writing them *after* confirmed delivery makes their presence mean
  "warned" rather than "attempted".
- **"`dartzen_telemetry` ... Pairs naturally with 7a, which needs somewhere to record job runs"**
  (ROADMAP Step 7, deferred packages) → **not needed.** Job runs are recorded in the `zen_jobs` row
  they belong to and returned in the tick's response. A telemetry store remains deferred on its own
  merits, not as a prerequisite of this step.
- **The donor's `JobType` triad and most of its `JobConfig`**
  (`../DartZen/packages/dartzen_jobs/lib/src/models/{job_type,job_config}.dart`) → **not ported.**
  jZen ships only the `periodic` shape. `endpoint` needs Cloud Tasks, which jZen does not use, and
  `scheduled` (per-job cron) is what the master tick exists to avoid. Likewise dropped:
  `dependencies`, `priority`, `skipDates`, `startAt`/`endAt`, and `maxRetries` — unused weight, and
  the donor's five `skipped*` statuses only describe those absent features. *Why:* STANDARDS forbids
  carrying donor limitations forward, and a status that can never be written is not a status.

### Consequence

`zen-jobs` carries a Jandex index (it contributes CDI beans, an `@Entity`, and a JAX-RS resource, so
without one the whole module would silently do nothing — the rule `zen-transport` established). The
`%dev` in-process cron survives and drives **the same** `JobScheduler.tick()` the external trigger
drives, so local work needs no GCP and dev and prod differ only in who pulls the trigger. Deployment
gains one secret (`ZEN_JOBS_TRIGGER_TOKEN`) and one Cloud Scheduler entry, both documented in
`deploy:cloudrun`. Surfacing job runs in the admin panel is **deferred**: the columns and the tick
response already make a run visible, and the panel is not needed to discharge the obligation.
Lockstep versioning is unchanged at `0.1.0`.

Verified: `task build:server`, `build:client`, `build:apps` green; the backend suite is **50 tests,
0 failures** (16 new), plus **10 new framework unit tests** in `zen-jobs` — the first tests
`task test:server` has ever had to run. `JobScheduleTest` and `JobSchedulerTest` drive an injected
clock to prove due-ness, that nine missed ticks are caught up by exactly one run, that a disabled
job never runs however overdue, that a failure is recorded without aborting the tick, and that an
overlapping tick is refused (proven by re-entering the scheduler from inside a job, so no threads
and no sleeps). `JobTriggerResourceTest` proves a valid secret runs retention end to end while an
absent one, a wrong one, and an authenticated **admin session** are each rejected with a `ZenError`.
`RetentionDeliveryGateTest` proves an account whose warning could not be sent is never stamped and
never anonymised however many cycles run, while one warned before the outage still is.
`UserRetentionTest` adds the idempotency the contract requires. No test touches GCP, SMTP, or a real
scheduler.

---

## ADR-007 — Email: the framework sends, the application speaks; identity publishes events

**Date:** 2026-07-21. **Status:** accepted.

### Decision

Four coupled choices for the Step-6 email capability, all following the framework/apps axis
(ADR-001):

1. **`zen-email` is a mechanism, not content.** `EmailService.send(LocalizedEmail)` owns locale
   resolution, per-locale template lookup, rendering, and sending; it owns no wording, no branding,
   and no template. The application supplies the subject (from its own typed Qute
   `@MessageBundle`) and the per-locale bodies under `templates/mail/`. This is the same split as
   TA-1's OpenAPI merge, where a framework resource declares a schema by `$ref` and the app's
   static `META-INF/openapi.yaml` supplies it. The alternative - shipping default templates inside
   the library jar for apps to override - was rejected: a jar-resident Qute template has no clean
   override mechanism, and generic framework branding in a product's mailbox is a defect, not a
   default.

2. **`zen-identity` publishes CDI events; it never sends mail.** `IdentityService.register(...)`
   fires `UserRegistered` and the retention cycle fires `AccountDeletionWarning`; applications
   observe them with `@ObservesAsync`. So `zen-identity` gains **no** dependency on `zen-email`.
   The framework knows *that* a user registered; only the application knows what to say. Both
   events are fired **after** the triggering transaction has committed and are observed
   asynchronously, so mail is never sent for a change that rolled back and registration neither
   waits for SMTP nor can be failed by it. `EmailService.send` compounds that by never throwing: a
   missing template, a render error, or an unreachable relay returns `false` and logs.

3. **`ZenLocales` (in `zen-core`) is the single declaration of the supported set.** `SUPPORTED =
   {en, uk}`, `FALLBACK = en`, with `resolve(tag)` for stored preferences (`users.language`, which
   email reads because it has no request) and `fromAcceptLanguage(header)` delegating to the pure
   `AcceptLanguage` parser. `Accept-Language` on `POST /auth/register` seeds `users.language`; it
   stays a header rather than a `RegisterRequest` field because the locale is a property of the
   request, not of the identity, which leaves the proto contract untouched.

   **On the client the locale is likewise ambient**, supplied once to `ZenClient` as a
   `String Function()?` and emitted on every request beside `X-Request-ID` and `X-Zen-Transport`,
   rather than added as an argument to `registerWithEmail`. A callback, not a value, because the
   locale is live app state and a mid-session language switch must reach the next request; a
   per-call `headers:` entry still overrides it, so `DemoRepository`'s explicit locale is
   unaffected. Making it a repository argument was rejected: it would have changed the
   `IdentityRepository` interface (TA-5 requires the implementation to match it exactly) and every
   fake in the `zen_ui_identity` suite, to express something that is request context rather than
   an endpoint parameter - and it would have fixed only the one endpoint that happens to need it
   today.

4. **Data retention ships now, opt-in, and is never scheduled in prod.** `UserRetentionService` +
   `UserRetentionJob` in `zen-identity` use the `users` GDPR columns the scaffold already carried:
   warn, warn finally, then anonymise. The cron defaults to `off` in the library's own
   `META-INF/microprofile-config.properties` - a framework must never start erasing user data
   because an app depends on it - and `zen_demo_server` enables it in dev only.

   **`%prod` pins it off**, because an in-process cron is incompatible with the deployment model:
   Cloud Run runs `--min-instances=0`, so at 03:00 there is normally no instance alive to fire the
   trigger, and a run that does happen is an accident of traffic rather than a schedule. This is
   the mirror image of the documented "one instance makes in-process state valid" invariant, and
   is now recorded beside it in STANDARDS "Deployment model": in-process *state* is sound under
   this model, in-process *time* is not. The hazard is not merely a missed run - because
   `EmailService` is deliberately non-fatal, an unconfigured SMTP relay would skip the warnings
   while the timestamps advanced, anonymising accounts whose owners were never warned. A product
   that needs retention on Cloud Run drives `runCycle()` from an external trigger (which also wakes
   the instance); that is its own scheduling design and not part of this step, which is why
   `runCycle()` is a plain public method and the cron binding is a thin wrapper over it.

   **This leaves the GDPR obligation undischarged in production, deliberately and on the record.**
   The trigger is specified as **ROADMAP step 7a** (`zen-jobs`), modelled on the donor's
   `../DartZen/packages/dartzen_jobs`: an external scheduler calling one endpoint, job state in
   Postgres, and due-ness computed from `last_run_at` rather than from a timer having fired, so a
   tick missed while scaled to zero is caught up instead of lost. Step 7a also owns the related
   hole this ADR knowingly accepts: because `EmailService` is non-fatal, a warning that failed to
   send still advances the clock toward anonymisation, and gating that needs the durable
   delivery state 7a introduces.

   Windows (330 / 23 / 7 days) are config, and the countdown quoted in a message is derived from
   them, so wording and schedule cannot drift apart.

### What this supersedes, and why

- **"These are defaulted/nullable now and wired in later steps (email deletion warnings in ROADMAP
  step 6 ...)"** (`User` javadoc; BLUEPRINT "Persistence") → **delivered.**
  `deletion_warning_sent_at` / `final_warning_sent_at` are now written by `UserRetentionService`.
  *Why:* the warning emails are the reason the columns exist, and a warning flow with no terminal
  action would promise a deletion that never happens - so the anonymisation step ships with them.
- **"`dartzen_jobs` → Quarkus `@Scheduled`" listed under "port only when a consumer needs them"**
  (ROADMAP Step 7, deferred packages) → **promoted and reframed.** A Quarkus `@Scheduled` bean is
  not a port of `dartzen_jobs` at all: the donor package exists precisely because in-process timers
  do not survive a serverless runtime, and its answer is an external trigger plus persisted job
  state. That work is now **step 7a, required before production rather than deferred**, since the
  GDPR cycle Step 6 delivered cannot legally rely on a timer that may never fire.
- **"`AppMessages` + `AppMessagesUk`"** (BLUEPRINT "Email", localized templates) → **renamed.** The
  reference app's mail subjects are `MailMessages` + `MailMessagesUk`, bundle name `mail`. *Why:* a
  Qute bundle name must be unique per application and `DemoMessages` already holds the default; the
  name now says what the bundle is for.
- **"the two Qute templates at `templates/mail/{warningEmail,finalWarningEmail}.html`" is "what is
  genuinely portable"** (`zen-email/pom.xml` header comment) → **not ported.** The donor templates
  are English-only hardcoded strings; jZen writes six templates instead
  (`{welcome,deletion_warning,final_warning}_{en,uk}.html`). *Why:* STANDARDS forbids carrying the
  donor's limitations forward, and localized-from-the-start is the whole point of the step.
- **The donor's fourth retention phase, deleting unconfirmed identities through the Supabase admin
  API** (`UserCleanupService.deleteUnconfirmedAccounts`) → **not ported.** *Why:* it needs a
  service-role key on the server and reaches into `auth.users`, which jZen deliberately does not
  own (BLUEPRINT "Persistence"). Anonymising the local profile is the part jZen's own schema models.
- **The donor's re-activation bug** (`UserCleanupService.java:143`: a user who signs back in keeps
  their warning stamps and is deleted anyway) → **fixed on port.** `UserStore.upsertOnLogin` clears
  both stamps on every sign-in. *Why:* STANDARDS "Do not carry over donor bugs".

### Consequence

`zen-email` now carries a Jandex index (it contributes a CDI bean, so without one `EmailService`
would be invisible from the jar - the rule that made `zen-transport` the reference).
`UserStore.upsertOnLogin` returns `Upsert(user, created)` so a welcome message is sent once per
profile, never again on a repeat signup. Adding a locale stays a three-file change with no code
edit: a `@Localized` bundle variant, the matching templates, and the tag in `ZenLocales.SUPPORTED`.
Lockstep versioning is unchanged at `0.1.0`.

Verified: `task build:server` and the app build green; the backend suite is **34 tests, 0 failures**
(11 new) - `WelcomeEmailTest` asserts a Ukrainian subject *and* Ukrainian body for
`Accept-Language: uk-UA` and English for none or an unsupported tag, that the header seeds
`users.language`, and that a repeat signup sends nothing; `UserRetentionTest` walks first warning →
final warning → anonymisation with localized subjects, proves premium accounts are exempt, and
proves `anonymous@example.com` is still warned (the `anon!_%` escape - an unescaped `_` is an HQL
wildcard); `EmailFailureTest` injects an unreachable mailer as a CDI alternative and shows
registration still returns 200. No test touches SMTP. Manually verified against live Supabase +
Quarkus dev: registering with `Accept-Language: uk-UA` produced `users.language = uk` and a mock
mailer capture of "Ласкаво просимо до jZen", `en-US` produced `en` and "Welcome to jZen".

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
   (artifactId `zen-demo-server`, package `zen.demo`). *Why:* the app is an *assembly* of the
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
`Accept-Language` → locale resolution lives in `zen.core.i18n.AcceptLanguage` (a pure function,
reused by any module). Localized *documents* (the terms Markdown) stay as classpath `.md` files -
content, not messages.

**Supersedes** the interim Step-4 choice of a hand-rolled `.properties`-backed `DemoMessages` bean.
*Why:* `@MessageBundle` is the Quarkus-idiomatic, typed, generated mechanism and the direction
ROADMAP step 6 (localized email) already commits to; a third, hand-rolled l10n format was needless,
and locale resolution belongs in a shared framework utility, not a demo-local bean.

---

## ADR-003 — HTTP status codes: an extendable constant interface

**Date:** 2026-07-19. **Status:** accepted.

**Decision.** `@APIResponse(responseCode = …)` values reference `zen.core.http.ZenStatus`, an
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

---

## ADR-005 — Admin panel: a framework scaffold + per-app panels; framework CRUD resource; bare-array pagination

**Date:** 2026-07-20. **Status:** accepted.

### Decision

Three coupled choices for the Step-5 admin (`admin/`), made to keep the panel consistent with the
framework/apps split (ADR-001):

1. **Split scaffold from panel.** The reusable react-admin machinery is a **framework scaffold**,
   `@jzen/admin-core` (kept at top-level `admin/`): a credentialed data provider wired to jZen's
   `Content-Range` pagination, an auth provider backed by the framework's Supabase session, and a
   login page — all type-generic (bound to no app's schema). Each app assembles it into its **own
   panel** under `apps/<app>/<app>_admin`, which registers domain `<Resource>`s and owns its
   generated `openapi-typescript` schema. Today: `apps/zen_demo/zen_demo_admin`. This mirrors
   `client/`(framework libs) ↔ `apps/`(app clients) on the TypeScript tier.

2. **The users CRUD resource is a framework resource.** `AdminUserResource`
   (`GET`/`PUT /api/v1/admin/users`) lives in `zen-identity`, beside `AuthResource`, `User`, and
   `RoleAugmentor` — the auth precedent (ADR-001 pt.3). It is `@RolesAllowed("admin")`, so every
   app's admin inherits user administration rather than reinventing it. Its wire type is a new
   `AdminUser` message in `proto/zen/v1/admin.proto` (component schema merged via the app's static
   `META-INF/openapi.yaml`, TA-1).

3. **List endpoints return a bare JSON array + `Content-Range`**, the stock `ra-data-simple-rest`
   convention, rather than a wrapper proto. Each element is still the declared `AdminUser` proto,
   rendered with `JsonFormat` (proto3 canonical JSON, zero-valued fields kept for a stable key
   set); the array is composed in the resource. This needs **no** `List<Message>` body writer and
   leaves the transport seam untouched. `Content-Range`/`Accept-Ranges` are added to the app's CORS
   `exposed-headers` so a cross-origin panel can read the total. Because the admin is JSON-only, the
   list endpoint is `application/json` only (the get/update endpoints keep the dual-transport
   `Response`-wraps-proto TA-1 form).

**Linking mechanism.** The per-app panel imports the scaffold **from source** via a TypeScript
`paths` alias + a Vite `resolve.alias` (with `dedupe` of `react`/`react-admin`), **not** a pnpm
dependency edge. This is the source-level analog of the Dart `path:` dep into `client/` and the
Maven `<relativePath>` inheritance: it keeps the repository root language-neutral (no root
`pnpm-workspace.yaml`), gives the app the single copy of React, and avoids a build/publish step for
the scaffold.

### What this supersedes, and why

- **"Flesh out `admin/` (the react-admin app)"** (ROADMAP Step 5; MANIFESTO/BLUEPRINT/STANDARDS
  wording that treated `admin/` as *the* app) → **refined.** `admin/` is now the framework scaffold
  `@jzen/admin-core`; the runnable panel is `apps/zen_demo/zen_demo_admin`. *Why:* an admin panel is
  a client of a specific app's backend, so per ADR-001 the reusable parts are a framework library
  and the assembly is an app. Docs and the Taskfile (`DEMO_ADMIN_DIR`, repointed
  `deps/build/test/run/generate` admin tasks, the `generate:types` openapi path) are updated to match.
- **"reuse `PageRequest` for list requests"** (Step-5 brief) → **not used on this path.** The
  ra-data-simple-rest convention passes `range`/`sort`/`filter` as query params, not a request body,
  so there is no request message to declare; `PageRequest` (common.proto) stays available for
  body-paged endpoints elsewhere.

### Consequence

Lockstep versioning holds: `@jzen/admin-core` and `@jzen/zen-demo-admin` are `0.1.0`. A second app
gets its own `apps/<app>/<app>_admin` assembling the same scaffold, and any admin resource that is
domain-specific (rather than identity) lands in that app's server, while identity administration
stays framework-side. Verified: `task build:admin`/`test:admin` green across the two-package
source-link; `AdminUserResourceTest` (7 tests) covers the role gate, `Content-Range` pagination, a
role filter, the get/update round-trip, and the `ZenError` not-found path.

---

## ADR-006 — Java namespace realignment: `dev.zen` → bare `zen`

**Date:** 2026-07-20. **Status:** accepted.

### Decision

The Java package root and Maven `groupId` are **bare `zen`**, not the reverse-DNS `dev.zen`:
`groupId zen`, packages `zen.core` / `zen.transport` / `zen.identity` / `zen.demo` / …, and every
proto now emits `option java_package = "zen.proto.v1"` **derived from** its own `package zen.v1`
rather than overriding it to `dev.zen.proto.v1`.

### What this supersedes, and why

- **`groupId dev.zen`, `package dev.zen.*`, `java_package "dev.zen.proto.v1"`** (Steps 0-4) →
  **renamed** repo-wide to `zen`. *Why (three reasons, one direction):*
  1. **The Zen source convention.** BugEater — the backend jZen is harvested from — uses a
     **bare brand namespace**: `groupId jlogicsoftware`, `package jlogicsoftware.*`, no reverse-DNS
     prefix, sliced by feature. jZen's `dev.` prefix departed from that for no stated reason.
  2. **Internal consistency.** Everything else in jZen is already bare `zen`: the canonical proto
     `package zen.v1`, the Dart libraries `zen_core`/`zen_transport`/…, the Maven artifacts
     `zen-core`/`zen-identity`/`zen-parent`. Only the Java package and `groupId` carried `dev.`, and
     the protos even overrode their own `package zen.v1` to `dev.zen.proto.v1` — a `zen.v1` ↔
     `dev.zen` mismatch baked into the contract layer.
  3. **The MANIFESTO.** "The contract is the single source of truth." The contract declares
     `package zen.v1`; the Java namespace must *follow* it (`zen.proto.v1`), not invent a different
     root. `dev.zen` (reverse-DNS for a `zen.dev` domain that is not the brand — the brand is
     jZen / jZenDev) contradicted all three.

### Mechanics

A literal `dev.zen` → `zen` replacement across all `.java`, `.proto`, `pom.xml`,
`application.properties` (the log category `"dev.zen"` → `"zen"`; the `%dev.` profile prefix is
untouched), plus moving each module's `src/**/java/dev/zen` to `src/**/java/zen`, then
`task generate:proto`. The Dart generated code is unaffected (it keys off the proto `package zen.v1`,
which did not change) — verified: the existing `*.pb.dart` are byte-identical after regeneration, and
the OpenAPI schema/TS types are likewise unchanged (schema names, not Java packages).

### Consequence

Verified green after the rename: framework `install`, the app package, and the full backend suite
(23 tests across `zen.demo.*`), plus `task test:admin`/`build:admin`. Stale `dev.zen` artifacts in
the local `~/.m2` are harmless. Prior ADRs' `dev.zen.*` references (e.g. ADR-003's
`zen.core.http.ZenStatus`) now read as `zen.*`.
