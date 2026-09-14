# Prompt: a multi-perspective code review of jZen's Dart/Flutter code

This file is **the brief you hand to the reviewing model**, not the review. Everything below the
`---` is the prompt; paste it whole, or point the agent at this file. The material above the `---`
is for the person commissioning it.

**Why this exists.** jZen's client (`client/zen_*` and each `apps/<app>/<app>_client`) is reviewed
piecemeal today — a PR diff here, a `/code-review` pass there. Nothing looks at the Dart/Flutter
surface as a whole, from more than one angle, on a schedule, across all six shipped targets
(Android, iOS, web, macOS, Linux, Windows). This prompt is that pass: it names the perspectives
explicitly (correctness, Dart/Flutter idiom, the compile-time-config seam's invariants, security,
vulnerability testing against OWASP references, state management, performance, testing, contract-
first hygiene, dependency hygiene, bundle/binary size, and release-build compilation hygiene) so a
reviewer does not collapse them into one generic "looks fine" sweep.

**Relationship to the Java/Quarkus review and the architecture security review.**
[`JAVA-QUARKUS-CODE-REVIEW-PROMPT.md`](JAVA-QUARKUS-CODE-REVIEW-PROMPT.md) is this review's mirror
on the server side — same structure, different lenses. Where a finding here is actually about the
*server's* behavior (a resource shape, an auth decision made server-side), it belongs in that
review, not this one; a client-side symptom of a server-side defect gets a one-line cross-reference
here, not a duplicate write-up. [`SECURITY-ARCHITECTURE-REVIEW-PROMPT.md`](SECURITY-ARCHITECTURE-REVIEW-PROMPT.md)
covers jZen's security at the level of a boundary (ASVS L2, the silent-failure census); this
prompt's security lens (§3.4) and its OWASP pass (§3a) work at the level of a file and a line — run
the architectural review first if it hasn't run recently, and cite its findings rather than
re-deriving them.

**Scope note for the commissioner.** This is a *code* review — it reads `client/` (the framework
libraries: `zen_core`, `zen_transport`, `zen_identity`, `zen_secure_store`, `zen_ui_identity`,
`zen_ui_navigation`) and every `apps/*/*_client` (today only `apps/zen_demo/zen_demo_client`), plus
each client's native platform runners (`android/`, `ios/`, `web/`, `macos/`, `linux/`, `windows/`)
for the size/compilation lens in §3c. It does not read `apps/*/*_admin` (React/TypeScript, not
Dart) or `server/`. Where a file violates a written rule in `CLAUDE.md` / `STANDARDS.md` /
`DECISIONS.md`, that is exactly the finding to report; the reviewer is not asked to re-derive or
second-guess the rules themselves.

**This review produces no code.** Its deliverable is a report. Fixing findings is a separate, later
pass — possibly `/code-review --fix` or a follow-up task against specific findings, run by a human
decision, not by this reviewer on its own initiative.

---

# You are conducting a multi-perspective code review of jZen's Dart/Flutter code

## 1. Your objective

Read every file under `client/` (the framework libraries: `zen_core`, `zen_transport`,
`zen_identity`, `zen_secure_store`, `zen_ui_identity`, `zen_ui_navigation`) and every
`apps/<app>/<app>_client` (today only `apps/zen_demo/zen_demo_client`) — including its
platform-runner directories (`android/`, `ios/`, `web/`, `macos/`, `linux/`, `windows/`) for the
size/compilation lens — and produce a ranked, evidence-backed list of defects and risks, each one
tagged with **which perspective surfaced it** (§3) and **which module it belongs to** (framework
code shared by every app, vs. application code scoped to `zen_demo`).

Your deliverable is `docs/plans/DART-FLUTTER-CODE-REVIEW.md`. `git status --porcelain` at the end
shows that one file and nothing else — you read code (and run read-only build/analysis commands),
you do not change source.

## 2. What makes this jZen's review, not a generic Dart/Flutter review

A finding that would read identically against any Flutter app is not wrong, but it is not this
review's point. Ground every finding you can in what is specific here:

- **The framework/app split.** A defect in `client/zen_*` is inherited by every application built
  on jZen, including ones that do not exist yet. The same class of defect in
  `apps/zen_demo/zen_demo_client` affects one app. Rank framework-scope findings above
  application-scope findings of equal severity, and say explicitly which scope each finding is.
- **Compile-time config is deliberate, not a limitation.** The client uses `String.fromEnvironment`
  (`ZEN_ENV`/`ZEN_PLATFORM` build defines) and `if (dart.library.io)` / `if (dart.library.js_interop)`
  conditional imports so the toolchain can tree-shake native-only code (the Protobuf binary path,
  `flutter_secure_storage`'s native backends) out of the web bundle, and web-only code out of the
  AOT-native binary. **Runtime config on the client is forbidden.** A finding that recommends
  reading config at runtime (a remote-config service, a `.env` loaded at startup, a runtime feature
  flag controlling which transport codec to use) contradicts this by design — flag the *opposite*:
  any place config already leaked to runtime that should have been a build define.
- **The `dart.library.io`/`dart.library.js_interop` seam is easy to get backwards.**
  `zen_secure_store`'s seam (`secure_token_store.dart` → `_io.dart`/`_web.dart`/`_stub.dart`) keys
  on `dart.library.js_interop`, **never** `dart.library.html` — the latter is also true for some
  non-browser compile targets and would wrongly select the web branch there. Any new
  platform-conditional file added since should be checked against this precedent, not `html`.
- **`zen_transport`'s dual-mode codec is the client half of the server's transport seam.** It must
  send `X-Zen-Transport` and choose Protobuf vs. JSON (de)serialization consistently with what it
  asked for; a response decode failure must surface as a `ZenResult`/`ZenError`, never a null/empty
  payload treated as "no data." Cross-check this against `CLAUDE.md`'s description of the seam
  before assuming a mismatch is a server bug.
- **The client talks to one server, and it is ours — no exceptions.** No client package may call
  Supabase (or any third party) directly, not with `supabase_flutter`, not with a hand-rolled HTTP
  call. `SUPABASE_URL`/`SUPABASE_KEY` are server-side only and must never appear in client code, a
  build define, or a bundled asset. This fails **silently** if broken — the app still authenticates,
  every test still passes, while the backend stops being the only place a session is minted and the
  only place a role is resolved. This is the single highest-value grep in this entire review; see
  §3.4 and §3a (`API1`/`API2`).
- **Client i18n is typed and generated, not hand-written strings.** Every package that renders text
  owns `lib/src/l10n/*.arb` + `l10n.yaml` and generates typed accessors via `flutter gen-l10n`; an
  app composes the delegates and supplies no wording of its own. This generated output
  (`**/l10n/generated/`) is **gitignored, built on demand** — unlike the `.pb.dart` proto messages,
  which *are* committed. Flag a committed `l10n/generated/` file as a contract-drift-gate violation,
  and flag any hand-written user-facing string bypassing the `.arb` files.
- **`.pb.dart` messages are committed, hand-editing one is a defect.** Fix the `.proto` and
  regenerate (`task verify:contracts` is the drift gate); a hand-patched generated Dart message is
  the same class of bug as a hand-patched Java DTO in the server review.
- **The supported locale set is `ZenLocales` in `zen_core`** (`{en, uk}`, fallback `en`), mirroring
  server `zen.core.i18n.ZenLocales`; the chosen `Locale` is also what `ZenClient` sends as
  `Accept-Language`. A widget or repository hard-coding a locale, or a locale check that doesn't
  route through `ZenLocales`, is a drift risk against the server's mirrored list.
- **Riverpod (or whatever the app's state layer is) owns app state; widgets should not.** A
  `StatefulWidget` holding business/session state that belongs in a provider is both a correctness
  risk (state lost on rebuild/navigation) and a maintainability finding, not a style nit.

## 3. Perspectives — review from each of these explicitly

Work through the same code from each of these lenses. A file can and should generate findings from
more than one lens. Do not merge them into one pass and lose the tagging.

1. **Correctness.** Logic errors, null-safety violations papered over with `!`, incorrect
   equality/`hashCode` on value objects, async/`Future` misuse (unawaited futures doing real work,
   a `Future` swallowed instead of awaited or explicitly fire-and-forgotten with a comment saying
   why), `ZenResult`/`ZenError` short-circuits that drop a failure, locale/timezone handling against
   `ZenLocales`, widget lifecycle bugs (`setState` after `dispose`, missing `mounted` checks after
   an `await`).
2. **Dart/Flutter idiom.** `const` correctness and constructor use, `BuildContext` used across an
   `await` without a `mounted` guard, over-broad `Consumer`/`ref.watch` causing unnecessary rebuilds,
   `StatefulWidget` vs. `StatelessWidget`+Riverpod choices, proper use of `Freezed`/`copyWith`-style
   immutability if in use, whether `dart.library.*` conditional imports are structured per the
   documented pattern (default file = stub, not a real implementation with a platform guess).
3. **The compile-time-config and transport seams' own invariants (§2).** Every build-define read
   goes through `String.fromEnvironment`, never `Platform.environment` (which doesn't tree-shake and
   isn't available on web); every native-only import is actually behind a `dart.library.io` /
   `dart.library.js_interop` conditional rather than a runtime `Platform.isX` check that still pulls
   the native package into the web bundle; `zen_transport`'s codec choice and `X-Zen-Transport`
   header stay consistent within one request/response pair.
4. **Security.** No Supabase URL/key or other server-only secret anywhere in `client/`,
   `apps/*/*_client`, a build define, an asset, or a native platform config file
   (`android/app/build.gradle*`, `ios/Runner/Info.plist`, `web/index.html`, `.env*` files shipped in
   any platform runner). Secure storage actually used for tokens (`zen_secure_store`, not
   `shared_preferences`/`localStorage`/an in-memory singleton that outlives its intended scope on
   web). No token or PII logged via `print`/`debugPrint`/a logger left at a verbose level in a
   release build. TLS/cert-pinning posture of any HTTP client construction. Deep-link/URL-scheme
   handling (`app_links` and similar) validates the incoming URI before acting on it — an unvalidated
   deep link is a classic mobile injection vector. Treat this lens as the entry point into the
   dedicated OWASP vulnerability pass in §3a — every finding here should end up mapped to an OWASP
   category there, not left as a standalone note.
5. **State management and concurrency.** Race conditions between two in-flight requests updating the
   same provider, a provider that outlives the screen that created it and leaks (a `StreamSubscription`
   or `Timer` never cancelled in `dispose`/`ref.onDispose`), shared mutable state read/written from
   more than one isolate without a defined ownership rule, `Future`s that should be cancelled on
   navigation-away but aren't.
6. **Performance.** Unnecessary widget rebuilds from overly broad `watch`/`Consumer` scope, expensive
   work (JSON/proto decode, image processing) run on the UI isolate instead of `compute`/an isolate,
   missing `const` on unchanging subtrees, list views without `.builder`/keys causing full rebuilds,
   unbounded image decode sizes (no `cacheWidth`/`cacheHeight` on large network images).
7. **Testing and maintainability.** Test coverage gaps in framework packages (a `zen_*` package with
   real logic and no `test/`), widget tests that pump-and-settle without asserting anything
   meaningful, golden tests (if any) that are stale relative to the widget, dead code, duplicated
   logic across `zen_*` packages that should be shared, naming/doc rot, comments explaining *what*
   instead of *why*.
8. **Contract-first hygiene.** Any hand-edited file under a generated path (`.pb.dart` messages,
   anything `flutter gen-l10n` produces if it were ever accidentally committed), any client-side
   model that duplicates a proto message instead of using the generated one, drift between a
   package's declared `IdentityRepository`-style contract and what its Supabase-backed (server-
   routed) implementation actually does.

## 3a. Security & vulnerability testing (OWASP)

This is not a ninth item in the list above — it's where every §3.4 security finding gets mapped,
tested, and given a standard reference, so severity isn't a guess.

**Standards to use, and how:**

- **OWASP Top 10 (2021)** — vocabulary and triage for anything reachable through the web target
  specifically (`A03 Injection` via an unvalidated deep link or `Uri.parse` misuse, `A05 Security
  Misconfiguration` in `web/index.html`/CSP, `A07 Identification & Authentication Failures` in how
  tokens are stored/attached, `A08 Software & Data Integrity Failures` for any unpinned/unverified
  update or asset-fetch mechanism). It's a prevalence ranking, not a checklist — don't stop at "no
  A03 found" without having actually traced the deep-link/URL-handling code.
- **OWASP Mobile Application Security Verification Standard (MASVS)**, current version — the primary
  checklist for the Android/iOS targets. Pull the code-verifiable requirements: `MASVS-STORAGE`
  (tokens/PII never in plaintext `SharedPreferences`/`NSUserDefaults`/unencrypted files — confirm
  `zen_secure_store`'s native backends are actually reached, not silently falling back to a plain
  store), `MASVS-CRYPTO` (no hand-rolled crypto, TLS actually enforced), `MASVS-AUTH` (session/token
  handling matches server expectations, no long-lived credential cached beyond what
  `zen_secure_store` is meant to hold), `MASVS-NETWORK` (cleartext traffic disabled — check
  `android:usesCleartextTraffic` / `NSAppTransportSecurity` in `Info.plist` aren't loosened for
  convenience and left that way), `MASVS-PLATFORM` (deep link/intent-filter/URL-scheme validation,
  WebView usage if any is hardened — no `javaScriptEnabled`+arbitrary-URL combination).
- **OWASP Mobile Top 10 (2024)** as the companion prevalence list to MASVS, same role the Top 10 and
  API Security Top 10 play in the server review — tag findings `M1`–`M10` where it sharpens a MASVS
  finding.
- **CWE** as a secondary tag where it sharpens a finding beyond its OWASP/MASVS category (e.g.
  CWE-312 cleartext storage of sensitive information, CWE-295 improper certificate validation,
  CWE-939 improper authorization in a handler for a custom URL scheme) — optional, never a substitute
  for tracing the actual code path.

**Static tooling — run what's available, name what you couldn't run:**

- `task audit` (if it exists and you're allowed to hit the network) — the framework's own dependency
  vulnerability gate, which also covers Dart/pub dependencies. Run it and report its output
  verbatim; do not re-derive CVEs by hand for dependencies it already covers.
- `dart analyze` / `flutter analyze` across `client/` and each `apps/*/*_client` — not a security
  tool by itself, but a lint failure (e.g. an `avoid_print` violation on a path that logs a token)
  is often the fastest route to a real finding here.
- A Dart-aware static analyzer if one is installed or quick to add in a throwaway, uncommitted local
  run — `semgrep --config p/owasp-top-ten` has partial Dart support; note its coverage gaps rather
  than trusting a clean run. If you can't run one (no network, no time budget), say so explicitly in
  the report rather than silently skipping this category — an unrun tool is a gap, not a pass.
- Grep-based checks that need no tool at all: `grep -rn "SUPABASE" client apps/*/*_client`
  (anything beyond a comment referencing the server-side name is a finding), `supabase_flutter` in
  any `pubspec.yaml` under `client/`/`apps/*/*_client` (should never appear — that package is a
  server-only integration point per `CLAUDE.md`), `print(`/`debugPrint(` near anything token/session/
  password-shaped, `http://` literals, `NSAllowsArbitraryLoads`/`usesCleartextTraffic` set `true`,
  hard-coded API keys or secrets in `lib/`, any `.env` file tracked under a platform runner.

**Dynamic/vulnerability testing — local only, never production:**

Any hypothesis from the static pass that needs confirming against a running app is tested against
`task run:demo` (the local Supabase + Quarkus + zen_demo stack) — **never** the deployed Cloud Run
instance or the hosted Supabase project. This mirrors both the server review and the architectural
review's rule of engagement, for the same reason: a single-instance production backend does not
tolerate probing, and a client-side proof-of-concept (e.g., confirming a token really is
plaintext-readable on a test device/emulator, or that a malformed deep link really is accepted) must
point at `localhost`/a local emulator, never a real account or the deployed service. If a finding
would benefit from a proof-of-concept, describe the exact steps (build define used, platform,
inspection method — e.g. `adb shell run-as <pkg> cat ...` for an Android storage check) and include
the actual local result in the finding's evidence — a hypothesis you didn't run is a lead, not a
finding.

**If you find something live and exploitable against the production backend or hosted Supabase
project from client code, stop and report it immediately** rather than holding it for the final
write-up.

## 3b. Third-party SDK and dependency-surface security

jZen's client uses a small number of native-bridging packages (`flutter_secure_storage`, `app_links`,
`protobuf`) whose Dart API is a thin wrapper over platform code this review doesn't otherwise read.
Treat their *usage* as in scope even though their internals aren't:

- **`flutter_secure_storage`** — confirm `zen_secure_store` configures it with the strongest option
  per platform it exposes (e.g. Android `EncryptedSharedPreferences`, iOS Keychain
  accessibility level appropriate for a session token — not `whenUnlockedThisDeviceOnly` where a
  looser default was actually intended, or vice versa) rather than accepting silent defaults.
- **`app_links`** (or any deep-link package) — confirm the received URI is validated (scheme, host,
  and any token/code parameter) before it's used to complete an auth flow or navigate; an app that
  trusts any URI matching its scheme is exploitable by another app registering the same scheme.
- **`protobuf`** — confirm decode failures on attacker-reachable input (a response from a
  compromised or MITM'd network path, if TLS were ever disabled per §3a) raise rather than silently
  producing a zero-valued message that the app then treats as legitimate data.
- **Any new dependency added since the last review** — check its `pubspec.yaml` version constraint
  isn't pinned to a version with a known advisory `task audit` would have caught if run against the
  current lockfile, and that it doesn't duplicate a capability `zen_core`/`zen_transport` already
  provides (a second HTTP client, a second secure-storage wrapper).

## 3c. Bundle/app size and release-build compilation hygiene (all six targets)

This lens is unique to this review — the server review has no analog, because a JVM native image
doesn't ship to an end-user device across six different packaging formats. Cover **web, Android,
iOS, macOS, Linux, and Windows** explicitly; a finding scoped to only one target must say so.

**Bundle/binary size:**

- **Web:** confirm the build actually uses the WebAssembly or CanvasKit/HTML renderer deliberately
  chosen for this app (check for a stale `--web-renderer` flag or default that's larger than
  necessary), that tree-shaking of icons is enabled (`--tree-shake-icons`, on by default in release
  but confirm nothing disables it), and that no debug-only package (e.g. a devtools/inspector
  package) ships in the web dependency graph reachable from `apps/zen_demo/zen_demo_client`'s
  `pubspec.yaml`. Run `flutter build web --release --analyze-size` (or inspect
  `build/web/flutter_build_bundle.json`/the size report Flutter emits) and report the actual
  numbers, not an estimate.
- **Android:** confirm ABI splitting or an App Bundle (`.aab`) is the actual release artifact rather
  than a universal fat APK bundling every ABI, `minifyEnabled`/R8 and resource shrinking are on for
  the release build type in `android/app/build.gradle*`, and no debug `google-services.json`/debug
  signing config leaks into a release flavor. Run `flutter build appbundle --analyze-size` (or
  `apk --analyze-size`) and report actual output size.
- **iOS:** confirm bitcode/App Thinning posture is current for the Flutter/Xcode versions in use,
  unused asset catalogs/architectures aren't bundled, and `flutter build ipa` (or `ios --release`)
  is run with `--analyze-size` to get an actual number rather than an estimate.
- **macOS/Linux/Windows (desktop):** confirm the release bundle doesn't carry debug symbols by
  default (see below), that bundled native libraries are the release variant, and that any
  desktop-only asset (installer icons, etc.) isn't duplicated across build output unnecessarily.
- **Cross-platform:** run `flutter build <target> --release --analyze-size` for every target that's
  actually buildable in the review environment; for targets that require hardware/toolchains this
  environment doesn't have (a Windows build from macOS, for instance), say so explicitly rather than
  silently skipping — an unmeasured target is a gap, not a pass. Compare against the app's own
  history if prior size numbers exist anywhere (a CI artifact, a prior report) rather than judging
  size in a vacuum.
- **Assets and fonts:** unused assets declared in `pubspec.yaml`'s `flutter:` section, unsubset fonts
  where only a handful of glyphs are ever used, duplicate images shipped at every resolution when the
  app only ever needs a subset, any asset that's clearly a development/placeholder artifact
  (a `.psd`, an oversized source PNG next to its optimized copy) shipped in `assets/`.

**Maximum-performance release compilation, with debug artifacts removed:**

- **Every build invocation reviewed here must be `--release`** (or `--profile` only where the task
  explicitly calls for profiling, never `--debug`) — confirm no build script/CI config that's
  supposed to produce a shippable artifact accidentally uses a debug or profile build.
- **AOT compilation is actually happening** for every native target (Android/iOS/macOS/Linux/Windows
  compile to native ARM/x64 via `dart2native`/Flutter's AOT pipeline in release mode by default —
  confirm nothing in a build script forces JIT/interpreted mode, which would be both slower and
  larger).
- **Debug symbols are split and *not* bundled into the shipped artifact** — `flutter build ... 
  --release --split-debug-info=<dir> --obfuscate` is the mechanism; confirm whether it's in use, and
  if it isn't, flag it as a size *and* a reverse-engineering-hardening finding (unobfuscated Dart
  symbol names in a shipped release binary make the app's logic trivially readable). If
  `--split-debug-info` is used, confirm the symbol directory it produces is never itself shipped to
  users or committed to the repo.
- **No debug-only code path can execute in a release build** — grep for `kDebugMode`/`assert(...)`
  guarding anything that shouldn't run in production (a debug banner override, a fake/mock identity
  repository, a verbose logger) and confirm the guard is actually structured so tree-shaking removes
  it, not just conditionally skipped at runtime (a runtime `if (kDebugMode)` check still compiles the
  debug code into the release binary; that's a size finding, not just a correctness one, unless
  Dart's tree-shaker can prove the branch dead — verify which is actually true here rather than
  assuming).
- **`flutter build` warnings about unoptimized/oversized output** (font tree-shaking skipped,
  R8/ProGuard warnings, App Thinning notices) are read from the actual build log, not assumed absent.
- **Web-specific debug leakage:** confirm `--dart-define=ZEN_ENV=dev`-style debug build defines are
  never baked into a `--release` web build (this would also be a §3.4/§3a finding, since a dev-mode
  build define could disable a security check meant for production).
- **Compare release-mode compile flags against `task build`'s actual invocation** (read
  `Taskfile.yml`) rather than assuming the ideal flags are the ones in use — a gap between
  documented best-practice flags and what the Taskfile actually runs is itself a top-tier finding
  for this lens.

## 4. Method

1. **Inventory.** List every package under `client/` and every `apps/*/*_client`, with its
   `pubspec.yaml` dependencies, declared platforms (check for `android/`, `ios/`, `web/`, `macos/`,
   `linux/`, `windows/` directories), and whether it owns an `l10n.yaml`. This is your map for §3.3,
   §3c, and §2.
2. **Read package by package**, framework libraries first (`zen_core` → `zen_transport` →
   `zen_secure_store` → `zen_identity` → `zen_ui_identity`/`zen_ui_navigation`), then the app
   client(s). Reading in dependency order means you already know a lower package's contracts before
   judging whether a higher one honors them.
3. **For each file, sweep all eight lenses from §3** before moving on — do not do a correctness-only
   pass over the whole tree and then a security-only pass over the whole tree; that's how the
   compile-time-config-seam-specific checks (§2, §3.3) get skipped the second time around.
4. **Cross-reference `STANDARDS.md`** and the relevant `DECISIONS.md` ADRs for anything that looks
   like a deliberate but unusual choice before flagging it as a defect — compile-time config, the
   `dart.library.js_interop` (not `html`) seam, and the framework/app split are all intentional.
5. **Run what's cheap to run.** `task deps` then `task test:client` and `flutter analyze`/`dart
   analyze` across every package to confirm current state before reasoning about it; grep for
   `supabase_flutter`/`SUPABASE_` across every `pubspec.yaml` and `lib/`; grep for `Platform.environment`
   where `String.fromEnvironment` should be used instead.
6. **Run the §3a security/vulnerability tooling** — `task audit`, a static analyzer if available, and
   the grep-based secret/cleartext/deep-link checks — as their own step, not an afterthought after
   the reading pass. Record what ran, its version, and what you could not run.
7. **Run the §3c size/compilation measurements** — `flutter build <target> --release --analyze-size`
   for every buildable target in this environment, plus the debug-symbol/obfuscation and
   `kDebugMode`-tree-shaking checks — as their own step. Report actual numbers from actual build
   output; name explicitly any target this environment cannot build.
8. **Confirm any exploitability hypothesis locally**, per §3a/§3b's dynamic-testing rule — `task
   run:demo` or a targeted widget/integration test, never the deployed instance or the hosted
   Supabase project.
9. **Do not run `task deploy:*` and do not touch production or the hosted Supabase project** — every
   dynamic check in this review runs against a local stack, and every build check produces local
   artifacts only.

## 5. What a finding must contain

- **Perspective(s)** — which of the eight lenses in §3 surfaced it (a finding can name more than
  one), plus §3c tagged separately as `size`/`compilation` where relevant.
- **OWASP/MASVS/CWE tag** — required for any §3.4/§3a security finding: the OWASP Top 10, Mobile Top
  10, and/or MASVS category, plus a CWE id where it sharpens the finding. Not applicable to a pure
  correctness/performance/style finding — leave it off those rather than forcing a tag.
- **Scope** — `framework` (shared by every app) or `application` (`zen_demo` only).
- **Platform(s)** — required for any §3c finding: which of web/Android/iOS/macOS/Linux/Windows it
  applies to; a finding scoped to one target must say so rather than implying it's universal.
- **Location** — file and line/method, or the build command/config file for a §3c finding.
- **Failure scenario** — concrete input/state that triggers the defect, or the concrete cost (bytes,
  attack surface, reverse-engineering ease) if it's a size/hardening/maintainability finding rather
  than a bug.
- **Evidence** — the code path you traced or the command output (actual `--analyze-size` numbers,
  actual grep hits, actual `flutter analyze` output). Not a citation of a document as if that alone
  were proof.
- **Fix** — what changes, and what it costs (touches a generated file, a native platform config, an
  ADR-protected invariant, a build-time-vs-runtime-config tradeoff, etc.). "Nothing" is valid only if
  you checked.

**Ranking:** severity × how many perspectives independently flagged the same code, framework scope
breaks ties upward. Group findings by module, ranked within each module, with an overall top-10
across the whole review at the top of the report.

## 6. What would make this review worthless

- Reporting the same finding once per lens as if they were independent (merge and tag instead).
- Flagging deliberate architecture (compile-time client config, the `dart.library.js_interop` seam,
  the framework/app split itself, active-record-style server ownership of Supabase) as a defect
  without engaging with the ADR/doc that chose it.
- A generic Flutter style checklist with no jZen-specific finding at all.
- Recommending the client call Supabase directly, add runtime config, or add a remote-config/feature-
  flag service — all three contradict documented, deliberate choices (§2).
- Fixing something instead of reporting it.
- Skipping the compile-time-config-seam invariants (§2, §3.3) because they require reading
  `CLAUDE.md` first.
- Naming OWASP/MASVS categories in the abstract without tracing an actual code path (§3a).
- Sending any request — proof-of-concept or otherwise — to the deployed production instance or the
  hosted Supabase project (§3a).
- Estimating bundle size or claiming a release build is optimized without running the actual
  `--analyze-size` build and reporting real numbers (§3c).
- Treating "it's in `pubspec.yaml`" or "it builds" as inherently safe/optimal without checking what
  it actually ships or what flags actually ran (§2, §3b, §3c).
- A long report where a ranked top-10 would have said as much.
