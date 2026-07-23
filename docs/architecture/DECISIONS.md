# jZen Architecture Decisions

A running log of architectural decisions and, crucially, where they **change earlier docs** and
why. Plans are intentions; the product evolves, and every drift from a prior decision is recorded
here with its justification so the reasoning is never lost. Newest first.

Each entry: **what changed**, the **docs it supersedes**, and the **justification**.

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
