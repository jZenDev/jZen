# jZen Dart/Flutter Code Review

**Date:** 2026-09-14
**Scope:** `client/` (`zen_core`, `zen_transport`, `zen_secure_store`, `zen_identity`, `zen_ui_identity`,
`zen_ui_navigation`) and `apps/zen_demo/zen_demo_client` including its platform runners
(`android/`, `ios/`, `web/`, `macos/`, `linux/`, `windows/`).
**Method:** every non-generated `.dart` file under the above was read; `docs/architecture/CLAUDE.md`,
`STANDARDS.md` and the relevant `DECISIONS.md` ADRs (016, 017, 018, 019, 044) were read first and
cross-checked before any finding was written up. Tooling actually run is listed in §0. This review
changed no source file; its only output is this document.

**Headline result:** the framework packages (`zen_core` → `zen_ui_navigation`) are unusually
disciplined — every platform seam is documented with *why*, every `dart.library.*` guard correctly
keys on `js_interop` rather than `html`, `flutter analyze` is clean everywhere, every test suite
passed, and `task verify:boundaries` confirms the client never reaches Supabase directly. The
material findings below are concentrated in two places: the **Xcode project files for
`zen_demo_client`'s iOS/macOS runners, which are currently broken from a clean checkout**, and a
handful of smaller gaps (dead/buggy code, a missing dependency-audit path for Dart, an Android
debug-signed release build, a missing font asset).

---

## 0. What actually ran (and what did not)

| Check | Result |
|---|---|
| `task deps` | Green. |
| `flutter analyze` — all 6 framework packages + `zen_demo_client` | **No issues found**, every package, individually. |
| `task test:client` (`zen_core`, `zen_transport`, `zen_secure_store`, `zen_identity`, `zen_ui_identity`, `zen_ui_navigation`, `zen_ui_navigation/example`) | **All tests passed** in every package (58 in `zen_ui_identity` alone, 42 in `zen_ui_navigation`, full listing in the run log). |
| `task test:apps:client` (`zen_demo_client`) | **All tests passed** (11 tests: `demo_repository_test.dart`, `demo_localizations_test.dart`). |
| `task verify:boundaries` | **Green** — "no client or admin package depends on a provider SDK", "no provider host or credential in client or admin code", "the only base URL in client and admin code is the compile-time one". |
| `task audit` | **Does not cover Dart.** Reading `Taskfile.yml` shows `audit:` runs only `audit:server` (Maven/OSV) and `audit:admin` (pnpm). There is no `audit:client`. This is itself Finding #2 below. As a substitute, this review queried `api.osv.dev` directly (Pub ecosystem) for the five native-bridging/networking packages named in §3b of the brief — `flutter_secure_storage@10.3.1`, `app_links@7.2.1`, `protobuf@6.0.0`, `http@1.2.2`, `web_socket_channel@3.0.1` — **no advisories found** for any of them at their pinned versions. This is a point-in-time, ad hoc check, not a substitute for a real gate. |
| `semgrep --config p/owasp-top-ten` | **Not run — named gap.** Not installed; `pip install semgrep` refused (Homebrew's externally-managed-environment guard, PEP 668) and installing via `pipx`/a venv was judged out of scope for a read-only review. No Dart-aware static analyzer was substituted. |
| Grep-based checks (§3a): `SUPABASE`, `supabase_flutter`, `print(`/`debugPrint(` near secrets, `http://` literals outside tests/comments, `NSAllowsArbitraryLoads`/`usesCleartextTraffic`, `Platform.environment`, hard-coded keys, tracked `.env*` | **All clean.** The one `Platform.environment` hit is in `integration_test/e2e_test.dart`, a pure-Dart-VM test harness reading its target URL at runtime — not shipped client code, and explicitly documented in the file as exempt from the compile-time-config rule for that reason. |
| `flutter build web --release --wasm` | **Succeeded.** Real bundle measured (§ Bundle size below). Note: `--analyze-size` **is not a supported flag for `flutter build web`** in this Flutter version (3.47.2) — the brief's suggested invocation does not exist; size was measured with `du` on the real output instead. |
| `flutter build appbundle --release --analyze-size --target-platform=android-arm64` | **Succeeded.** Real `--analyze-size` breakdown captured (§ Bundle size below). |
| `flutter build macos --release --analyze-size` | **Failed — a real, reproducible defect.** See Finding #1. |
| `flutter build ios --debug --no-codesign --simulator` (the same invocation `task build:apps:runners` uses) | **Failed identically.** See Finding #1. `--release` for the simulator is refused by Flutter itself ("Release mode is not supported for simulators"), and a signed `--release` IPA needs a distribution certificate this machine does not have — consistent with the repo's own `macos/Runner/*.entitlements` comments, which name an unsigned local run as the accepted MVP boundary. Both are named gaps, not silent skips. |
| `flutter build linux` / `flutter build windows` | **Not run — named gap, not a skip.** This host is macOS; Flutter refuses `build linux` off Linux and `build windows` off Windows by name (confirmed in `STANDARDS.md` "Client config is compile-time" and `Taskfile.app.yml`'s own `build:runners` task, which treats this exactly the same way and reports each unbuildable target explicitly rather than silently). No number is reported for these two targets. |
| `--split-debug-info`/`--obfuscate` release build of any runner | **Not run.** No task in the reviewed Taskfile paths exercises these flags for the *client* (the equivalent exists for the server). See Finding #10. |

---

## Top 10 findings (whole review, ranked)

Ranking: severity × number of independent lenses that flagged the same code; framework scope breaks
ties upward per §5 of the brief.

| # | Finding | Scope | Severity |
|---|---|---|---|
| 1 | iOS and macOS runners fail to build from a clean checkout (stale CocoaPods `Frameworks` references survive the SPM migration) | application (pattern is framework-relevant) | **High** |
| 2 | `task audit` silently does not cover Dart/pub dependencies | framework | **High** |
| 3 | Android release build type is signed with the debug keystore | application | Medium |
| 4 | `CupertinoIcons` glyphs used by shared navigation code are not bundled — confirmed by the build's own warning | framework (defect) / application (missing dep) | Medium |
| 5 | `IdentityContract.toJson`/`.fromJson` are dead code and lose `emailVerified` on round-trip | framework | Medium |
| 6 | Native deep-link handler forwards any URI with no scheme/host check of its own | application | Low–Medium |
| 7 | `zen_logger_test.dart` asserts nothing | framework | Low |
| 8 | Weak, duplicated client-side email regex across three screens instead of the shared validator | framework | Low |
| 9 | Web bundle size measured: 48 MB (CanvasKit ~41 MB, app code ~5.3 MB) — as designed, reported for the record | application | Informational |
| 10 | No task anywhere exercises `--release --obfuscate --split-debug-info` for any client runner | framework | Low |

---

## Findings by module

### Cross-cutting / build & platform runners (`apps/zen_demo/zen_demo_client/{ios,macos,android,web}`)

#### Finding 1 — iOS and macOS runners do not build from a clean checkout
- **Perspective(s):** compilation (§3c), correctness.
- **Scope:** application (`zen_demo_client`'s own Xcode projects); the *pattern* — a partial
  CocoaPods→SPM migration leaving stale `Frameworks` build-phase entries — is a trap any jZen app's
  runner could repeat, so it is worth fixing at the reference level.
- **Platform(s):** iOS, macOS. (Android and web are unaffected and build cleanly — see below.)
- **Location:** `apps/zen_demo/zen_demo_client/ios/Runner.xcodeproj/project.pbxproj` and
  `apps/zen_demo/zen_demo_client/macos/Runner.xcodeproj/project.pbxproj`, `Frameworks` build phase
  and `PBXFileReference` sections (`Pods_Runner.framework`, `Pods_RunnerTests.framework`).
- **Failure scenario:** anyone cloning the repo fresh and running `task build:apps:runners`, or
  `flutter build macos --release`, or `flutter build ios --simulator` gets a hard failure before
  any app code is even reached.
- **Evidence (actual command output, this review's environment — Xcode 26.6, CocoaPods 1.17.0
  present and working):**
  ```
  $ flutter build macos --release --analyze-size ...
  ld: framework 'Pods_Runner' not found
  ** BUILD FAILED **

  $ flutter build ios --debug --no-codesign --simulator ...
  Error (Xcode): Framework 'Pods_Runner' not found
  Error (Xcode): Linker command failed with exit code 1
  ```
  `pod install` in `macos/` reports `[!] No 'Podfile' found in the project directory.` — confirmed
  with `git ls-files`: **no `Podfile` is tracked anywhere in the repo**, for either `ios/` or
  `macos/`, and neither is listed in any `.gitignore` (only `**/Pods/` output and
  `**/Flutter/ephemeral/` are ignored — a `Podfile` itself is normally committed). At the same
  time, both `project.pbxproj` files already show a completed migration to Swift Package Manager
  (`FlutterGeneratedPluginSwiftPackage`, `XCLocalSwiftPackageReference` sections present and
  correctly wired) — so the CocoaPods `Podfile` was deliberately removed, but the **`Frameworks`
  build phase and `PBXFileReference` entries for `Pods_Runner.framework` /
  `Pods_RunnerTests.framework` were not removed along with it**, leaving the linker looking for a
  framework nothing produces any more.

  This is not a new class of bug for this repo — `Taskfile.yml`'s own `build:apps:runners`
  documentation names the *exact* failure mode as a lesson already learned once:
  > "removing the CocoaPods integration after that plugin moved to Swift Package Manager, which
  > could have broken both Apple runners with nothing to say so."

  It appears to have recurred. `git log --diff-filter=A -- '**/Podfile'` shows a `Podfile` was
  added once (commit `63b61cc1`, native session persistence / ADR-023) and is not present today,
  confirming it was later removed without the matching pbxproj cleanup.
- **Fix:** remove the `Pods_Runner.framework` / `Pods_RunnerTests.framework`
  `PBXBuildFile`/`PBXFileReference` entries and their `Frameworks`-phase references from both
  `project.pbxproj` files (Xcode's own "remove reference" on the two frameworks does this cleanly).
  Costs nothing architecturally — it is deleting dead references to a build system the project no
  longer uses — but it is hand-editing a semi-generated Xcode project file, so verify with a real
  `flutter build macos --release` and `flutter build ios --simulator` afterward, and consider
  adding that verification to CI given it has silently regressed at least once already.

#### Finding 9 — Web bundle size (measured, not estimated)
- **Perspective(s):** size (§3c).
- **Scope:** application, but the CanvasKit contribution is inherent to any jZen web build
  (framework-level, per ADR-016).
- **Platform(s):** web.
- **Location:** `flutter build web --release --wasm --tree-shake-icons` output, this review's run.
- **Evidence:**
  ```
  48M  build/web  (total)
  41M  build/web/canvaskit/       (skwasm.wasm 3.4M, skwasm_heavy.wasm 5.0M, canvaskit.wasm 6.9M,
                                    wimp.wasm 3.4M, plus .js.symbols debug maps ~6.1M combined)
   3.0M build/web/main.dart.js     (the automatic dart2js fallback ADR-016 documents)
   2.3M build/web/main.dart.wasm   (the actual dart2wasm app code jZen ships)
  1.4M build/web/assets
  144K build/web/icons
   32K build/web/main.dart.mjs
  ```
  This matches ADR-016's own stated number ("~40 MB of the bundle" is CanvasKit) almost exactly,
  and confirms both the Wasm output and its dart2js fallback are present as designed — this is
  **architecture-as-built, not a defect**, reported here because §3c requires a real measured
  number rather than an assumption that the documented figure still holds. One real, minor gap:
  the build log warns `Font asset "MaterialIcons-Regular.otf" was tree-shaken … reducing it from
  1645184 to 8660 bytes` but also warns `Expected to find fonts for (MaterialIcons,
  packages/cupertino_icons/CupertinoIcons), but found (MaterialIcons)` — see Finding 4, which this
  warning is the evidence for.
- **Fix:** none needed for the CanvasKit number itself (deliberate, ADR-016). See Finding 4 for the
  font warning's actual fix.

#### Android release build (measured, not estimated) — no separate top-10 entry, folded into Finding 3
- **Perspective(s):** size/compilation (§3c).
- **Platform(s):** Android.
- **Evidence:** `flutter build appbundle --release --analyze-size --target-platform=android-arm64`
  succeeded:
  ```
  ✓ Built build/app/outputs/bundle/release/app-release.aab (18.6MB)
  app-release.aab (total compressed)                18 MB
    BUNDLE-METADATA/debugsymbols                      9 MB  (bundle metadata only — Play strips
                                                                this before delivering to a device)
    BUNDLE-METADATA/obfuscation (R8 mapping file)    564 KB  (confirms R8 minification DID run —
                                                                withdrawing an earlier draft
                                                                assumption that it was absent)
    base/lib (native libs, pre-ABI-split)              8 MB
    Dart AOT symbols, decompressed                     6 MB  (package:flutter 3 MB, zen_ui_identity
                                                                48 KB, zen_transport 30 KB,
                                                                zen_demo_client 29 KB, …)
  ```
  R8/minification is active by Flutter's own Gradle-plugin default for a release build even though
  `android/app/build.gradle.kts` sets no explicit `minifyEnabled`/`shrinkResources` — this review
  initially expected to flag their absence, but the actual build output (the obfuscation mapping
  file, the tree-shaken font) shows shrinking is genuinely happening. That expectation is corrected
  here rather than reported as a false finding. 18.6 MB compressed is an unremarkable size for a
  Flutter/Riverpod/protobuf app and is not itself a concern.

#### Finding 3 — Android release build is signed with the debug keystore
- **Perspective(s):** security (§3a/§3b), compilation (§3c).
- **OWASP/MASVS/CWE tag:** MASVS-CODE (release-build hardening) / OWASP Mobile Top 10 2024 **M8
  Security Misconfiguration**; CWE-798 is a loose fit (the "hard-coded" credential here is the
  well-known, publicly-distributed Flutter debug keystore, not a secret unique to this app, but the
  effect — anyone can produce a build that verifies against the same signer — is the same shape).
- **Scope:** application.
- **Platform(s):** Android.
- **Location:** `apps/zen_demo/zen_demo_client/android/app/build.gradle.kts`:
  ```kotlin
  buildTypes {
      release {
          // TODO: Add your own signing config for the release build.
          // Signing with the debug keys for now, so `flutter run --release` works.
          signingConfig = signingConfigs.getByName("debug")
      }
  }
  ```
- **Failure scenario:** every `.aab`/`.apk` this repo can currently produce with `--release` is
  signed with the shared, public Flutter debug key. It cannot be uploaded to the Play Store as-is
  (Google rejects debug-signed release artifacts), and if it were ever distributed by another
  channel, anyone holding the same debug key (every Flutter developer, by default) could produce a
  build that verifies as "the same signer" to any code that checks the signing certificate.
- **Evidence:** confirmed by direct read of `build.gradle.kts` (quoted above) and by the successful
  `flutter build appbundle --release` in this review, which used exactly this signing config.
- **Fix:** generate a real upload/release keystore and reference it from `build.gradle.kts` (the
  standard Flutter pattern: a `key.properties` file, gitignored, read into a `signingConfigs.create
  ("release")` block). This is a local, `zen_demo`-specific decision (a keystore is a secret, never
  committed) — the framework has nothing to change here, but the demo's own TODO should not still
  be open by the time it is used as a "living reference."

#### Finding 4 — CupertinoIcons glyphs used by shared navigation code are not bundled
- **Perspective(s):** correctness (§3.1), size (§3c) — confirmed by real build output, not
  speculation.
- **Scope:** framework defect (the icon usage lives in `zen_ui_navigation`), surfaced as an
  application-level missing dependency (neither `zen_ui_navigation`'s nor `zen_demo_client`'s
  `pubspec.yaml` declares `cupertino_icons`).
- **Platform(s):** iOS and macOS specifically — the affected code paths are gated on `zenIsIOS`.
- **Location:** `client/zen_ui_navigation/lib/src/widgets/navigation_mobile.dart:64`
  (`CupertinoIcons.ellipsis` for the "more" tab icon) and
  `client/zen_ui_navigation/lib/src/widgets/navigation_more.dart:57`
  (`CupertinoIcons.checkmark_alt` for the selected-item indicator), both reached only when
  `zenIsIOS` is true.
- **Failure scenario:** on a real iOS build, the "more" bottom-nav icon and the selection checkmark
  in the overflow page render as a missing-glyph box (tofu) instead of the intended icon, because
  the font asset that defines those glyphs is never shipped.
- **Evidence:** `grep -rn cupertino_icons client/zen_ui_navigation/pubspec.yaml
  apps/zen_demo/zen_demo_client/pubspec.yaml apps/pubspec.lock` — **no hits**. The dependency is
  present only in `client/pubspec.lock` (a different pub workspace, pulled in transitively by
  something in `client/`, not by the app that actually ships). The `flutter build web --release`
  run in this review printed, verbatim:
  ```
  Expected to find fonts for (MaterialIcons, packages/cupertino_icons/CupertinoIcons),
  but found (MaterialIcons).
  ```
  confirming the font is genuinely absent from the app's own dependency graph, not merely
  tree-shaken.
- **Fix:** add `cupertino_icons: ^1.x` to `zen_ui_navigation/pubspec.yaml` (the package that
  actually imports `flutter/cupertino.dart` and uses `CupertinoIcons.*`) so every consumer gets the
  font transitively — cheap, and correct dependency hygiene regardless of which app renders it.

### `client/zen_identity`

#### Finding 5 — `IdentityContract.toJson`/`.fromJson` are dead, and lose `emailVerified`
- **Perspective(s):** correctness (§3.1), testing/maintainability (§3.7 — dead code).
- **Scope:** framework.
- **Location:** `client/zen_identity/lib/src/identity_contracts.dart:117-131`.
- **Failure scenario:** if any future caller (framework or app) starts persisting or transmitting
  an `IdentityContract` via these methods — a natural thing to reach for, since they exist and look
  complete — a round trip silently drops whether the account's email is verified, which is exactly
  the field `zen_ui_identity`'s `RegisterScreen` branches on to decide whether to show the "check
  your email" screen (`identity.emailVerified` in `register_screen.dart:67`).
- **Evidence:**
  ```dart
  factory IdentityContract.fromJson(Map<String, dynamic> json) => IdentityContract(
    id: json['id'] as String,
    lifecycle: IdentityLifecycleContract.fromJson(json['lifecycle'] as Map<String, dynamic>),
    authority: AuthorityContract.fromJson(json['authority'] as Map<String, dynamic>),
    createdAt: json['createdAt'] as int,
    // emailVerified is never read — defaults to false regardless of input.
  );

  Map<String, dynamic> toJson() => {
    'id': id, 'lifecycle': lifecycle.toJson(), 'authority': authority.toJson(),
    'createdAt': createdAt,
    // emailVerified is never written.
  };
  ```
  `grep -rn "IdentityContract.fromJson"` across `client/` and `apps/` finds **no caller anywhere**
  outside this file — the actual wire path (`SupabaseIdentityRepository._toContract`) maps directly
  from the protobuf `Identity` message and correctly carries `emailVerified` through; these two
  methods are unused.
- **Fix:** either delete both methods (nothing depends on them, and the wire format is proto, not
  JSON, per this codebase's own transport design) or, if a genuine JSON round-trip need exists
  somewhere not yet built, fix the bug by including `emailVerified` in both directions. Deleting is
  the lower-risk option given STANDARDS' "no custom magic" bias and the fact that keeping unused,
  silently-lossy serialization code around is itself a latent trap.

#### Finding 8 — Duplicated, weaker client-side email validation
- **Perspective(s):** Dart/Flutter idiom (§3.2), testing/maintainability (§3.7 — duplicated logic).
- **Scope:** framework.
- **Location:** `client/zen_ui_identity/lib/src/screens/login_screen.dart:160`,
  `register_screen.dart:133`, `restore_password_screen.dart:111` — each independently validates
  with `if (!value.contains('@')) return messages.validationEmail;`.
- **Failure scenario:** not a security bug (the server re-validates and the actual auth call goes
  through `SupabaseIdentityRepository`, which validates with `EmailValidator.validate` before
  sending), but it is a maintenance trap: `zen_core.EmailAddress.create` already exists, is unit
  tested, and uses the same `email_validator` package the repository layer uses — yet the UI layer
  re-implements a strictly weaker check (`a@` passes `.contains('@')` but would fail
  `EmailAddress.create`) in three separate places that can drift independently.
- **Evidence:** `client/zen_core/lib/src/value_objects/common_types.dart` (`EmailAddress.create`,
  using `EmailValidator.validate`) vs. the three `.contains('@')` call sites above.
- **Fix:** have the three `validator:` callbacks call `EmailAddress.create(value).isFailure` (or
  expose a thin `bool` helper) instead of the ad hoc substring check. Small, contained change,
  touches only the three widget files.

#### Finding 6 — Native deep-link handler performs no scheme/host validation of its own
- **Perspective(s):** security (§3.4/§3a), third-party SDK usage (§3b).
- **OWASP/MASVS/CWE tag:** MASVS-PLATFORM (deep-link/URL-scheme handling); OWASP Mobile Top 10 2024
  is a loose fit here (closest is **M4 Insufficient Input/Output Validation**); CWE-939 (Improper
  Authorization in Handler for Custom URL Scheme) describes the shape of the gap, though the actual
  exploitability is bounded — see below.
- **Scope:** application (`zen_demo_client`'s `auth_deep_links_native.dart`), but the pattern
  (`ZenAuthLink.parse` itself, in `zen_identity`) is framework-level.
- **Platform(s):** Android, iOS, macOS (the three targets that register the `zendemo://` custom
  scheme and wire `app_links`).
- **Location:** `apps/zen_demo/zen_demo_client/lib/src/auth_deep_links_native.dart:18-37` (forwards
  every URI from `AppLinks().getInitialLink()` and `.uriLinkStream` unconditionally to
  `consumeAuthLink`), and `client/zen_identity/lib/src/auth_link.dart:72-103` (`ZenAuthLink.parse`
  — the `confirmedWithoutSession` branch in particular requires only `query['auth'] ==
  'email-confirmed'`, no token, no signature, no origin check of any kind).
- **Failure scenario:** the repo's own comments (`AndroidManifest.xml`) already document that "any
  app may register 'zendemo' and receive a link carrying a live refresh token" (RFC 8252 §8.6) — the
  App Links / autoVerify `https` filter is the accepted mitigation for the *dangerous* half of this
  (an access/refresh token), and that mitigation is present and well documented. What is **not**
  mitigated at the client layer is the harmless-looking `?auth=email-confirmed` case: any other app
  able to send the device a `zendemo://…?auth=email-confirmed` intent (trivial — no token needed)
  makes `zen_demo` show its "your email is confirmed" banner regardless of whether the user actually
  confirmed anything. Actual session/account compromise is **not** possible through this path — the
  one case with a real token (`accessToken`) is always re-validated against Supabase server-side
  before any cookie is issued (ADR-018's design, confirmed by reading
  `SupabaseIdentityRepository.exchangeLinkSession`, which explicitly never inspects the token
  itself: *"No local inspection of the token… only the backend's check against the identity
  provider means anything"*). So this is a real gap exactly where §3b asks to look, but a UI/trust
  confusion issue, not an auth bypass.
- **Fix:** low-value to over-engineer given the bounded impact, but the cheapest hardening is
  scheme/host filtering in `auth_deep_links_native.dart` itself (reject anything whose `scheme`
  isn't `zendemo` or whose `host` isn't `auth-callback` before calling `onLink`), which costs
  nothing and would also filter out any other deep link a future feature might introduce on the
  same custom scheme. Worth noting: this finding does **not** ask for anything at odds with
  ADR-018/ADR-019's deliberate design — the token-bearing path is already correctly handled
  server-side; this is only about the token-less confirmation banner.

### `client/zen_core`

#### Finding 7 — `zen_logger_test.dart` asserts nothing
- **Perspective(s):** testing/maintainability (§3.7).
- **Scope:** framework.
- **Location:** `client/zen_core/test/zen_logger_test.dart` (both tests in the file).
- **Failure scenario:** a regression in `ZenLogger`'s actual formatting (e.g. the `[DEBUG]`/`[INFO]`
  prefix logic, the `internalData` interpolation, the `origin` handling in the IO strategy) would
  not be caught by this test — it only checks that the calls do not throw, never inspects what was
  produced.
- **Evidence:** the file (quoted in full in the read) contains `ZenLogger.instance.debug(...)` etc.
  with **zero `expect()` calls** anywhere in either test body — confirmed by
  `grep -L "expect(" client/*/test/*.dart`, which flags this file and no other test file in the
  entire framework tree (one other hit, `zen_ui_identity/test/support/localized_app.dart`, is a test
  *helper*, not a test, and legitimately has no assertions of its own).
- **Fix:** either assert on captured output (inject a fake `ZenLoggerStrategy` and assert the
  formatted string/level/origin it received) or, if the intent really is just "does not throw,"
  rename the test to say so and accept it as a smoke test — as written it reads like behavioral
  coverage it is not providing.

### `client/zen_transport`, `zen_secure_store`, `zen_ui_navigation` — no material findings

These three packages were read in full, including every platform-seam file
(`zen_codec_selector*.dart`, `session_client*.dart`, `ws_channel*.dart`, `secure_token_store*.dart`,
`navigation_*.dart`). All of the following were specifically checked and are **correct as built**:

- Every `dart.library.*` conditional import keys on `js_interop`, never `html` (verified with
  `grep -rn dart.library.html` — every hit is a comment explaining why `html` is *not* used, none is
  an actual guard).
- `ZenClient._buildResult` never returns a null payload on a decode failure — every error path
  (network failure, unrecognized `X-Zen-Transport` header, non-2xx with no body, decode exception)
  returns a `ZenResult.err` carrying a typed `ZenTransportError`.
- `zen_secure_store`'s web branch **throws** rather than silently falling back to
  `window.localStorage` — the fix for the architectural review's F4 finding is fully in place and
  well-defended (`secure_token_store_web.dart`, `secure_token_store_stub.dart`).
- The CSRF double-submit echo (`csrf.dart`, `session_client_io.dart`, `session_client_web.dart`) is
  implemented identically in shape on both platforms and is exercised end-to-end by
  `integration_test/e2e_test.dart`'s "the CSRF check" group against a live server, including the
  negative case (wrong token → 403, session survives) and the positive case (real token echoed
  automatically, GET never asked for one).
- `CookieJarClient` only persists the refresh token (never the access token), reads it back with
  expiry checking, and reports (never throws through to the caller) a keystore failure — matching
  the documented OWASP MASVS-STORAGE-1 rationale in the file's own comments.
- `zen_ui_navigation`'s platform builder correctly asserts `zenPlatform.isNotEmpty` rather than
  guessing, and the mobile/desktop/web layouts were all exercised by widget tests that assert real
  structure (`NavigationRail`, `BottomNavigationBar`, overflow routing), not just
  pump-and-settle-with-no-assertion.

### `apps/zen_demo/zen_demo_client` (app code, excluding platform runners covered above)

No material findings beyond those already listed. Specifically checked and clean:
`main.dart`'s wiring of the shared session client across `SupabaseIdentityRepository` and
`DemoRepository` (the same `ZenSessionClient` instance, not two), the `mounted` guards after every
`await` in `login_screen.dart`/`register_screen.dart`/`dashboard_screen.dart`/`terms_screen.dart`,
`dispose()` correctly cancelling the WebSocket subscription and closing the socket in
`dashboard_screen.dart`, and the locale/`Accept-Language` propagation path
(`localeProvider` → `ZenClient.language` callback → server).

One very low-severity, unconfirmed-as-reachable nit: `profile_screen.dart:71`
(`subject.substring(0, 1)`) would throw `RangeError` if `identity.id.value` were ever an empty
string. The wire contract (`SupabaseIdentityRepository._toContract`) always populates `id` from a
non-empty Supabase user id, so this is not currently reachable, but it is one unguarded assumption
away from a crash if that contract ever changes. Not ranked in the top 10; noted for completeness
since §3.1 explicitly asks about unguarded operations on server-supplied strings.

---

## Finding 10 — no task exercises `--release --obfuscate --split-debug-info` for any client runner
- **Perspective(s):** compilation/hardening (§3c).
- **Scope:** framework (`Taskfile.app.yml`'s `build:runners`, reused by every jZen app).
- **Platform(s):** all five native targets (Android, iOS, macOS, Linux, Windows) — web debug
  symbols are a separate, already-solved concern (`build:web`'s own comment documents that
  `canvaskit/**/*.symbols` is deliberately excluded from the served bundle).
- **Location:** `Taskfile.app.yml:738-790` (`zen:build:runners`) — every `build_target` call passes
  `--debug`, none passes `--release`, `--obfuscate`, or `--split-debug-info`.
- **Failure scenario:** this task's own documentation is explicit that it is "a COMPILE check" and
  the artifacts are "throwaway," so building in `--debug` is not wrong on its own stated terms — but
  it means the *hardened release* compile path (obfuscated symbol names, split debug info kept out
  of the shipped binary) has never actually been proven to succeed for any native client target,
  anywhere in this repo's own tooling. If it were broken — a plugin whose obfuscation-incompatible
  reflection usage only surfaces under `--obfuscate`, for instance — nothing here would catch it
  before a real release build did.
- **Evidence:** read of `Taskfile.app.yml`'s `build:runners` task in full; no other task in
  `Taskfile.yml`/`Taskfile.app.yml` was found (via `grep -n "split-debug-info\|--obfuscate"
  Taskfile*.yml`) to reference either flag for the client. (The **server** has an analogous
  release-hardening story — the native image build — which is out of this review's scope.)
- **Fix:** not urgent (this task's debug-only scope is a documented, deliberate trade against build
  time), but worth a follow-up task or a periodic manual check that
  `flutter build <target> --release --obfuscate --split-debug-info=<dir>` still succeeds for at
  least one native target before the first real distribution build is attempted — cheaper to find
  that gap now than at release time.

---

## What would have made this review worthless (self-check against §6)

- No deliberate architecture was flagged as a defect: compile-time config, the
  `dart.library.js_interop` seam, the framework/app split, and the client-talks-to-one-server rule
  were all cross-checked against `STANDARDS.md`/`DECISIONS.md` before writing anything up, and the
  review explicitly corrects one of its own early hypotheses (Android R8/minification) once real
  build output contradicted it, rather than reporting a plausible-sounding but false finding.
- Every §3c finding is backed by real command output (`du`, the actual `--analyze-size` JSON
  summary, the actual linker error), not an estimate.
- The `task audit` gap and the two unbuildable-host limitations (Linux/Windows) are named
  explicitly rather than silently skipped.
- Nothing in this review recommends a runtime-config service, a direct Supabase call, or a
  remote-feature-flag mechanism.
