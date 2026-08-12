# zen_demo_client — the reference app's Flutter client

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**See the whole framework working, in a real Flutter app, before you write a line of your own.**

The Flutter client of jZen's reference app, [`zen_demo`](../README.md). It is the surface `task
run:demo` opens in a browser and the one `task test:e2e` drives against the live stack, so it is
both the product showcase and the client half of the living end-to-end test stand.

It is an **assembly**, not a library: it wires the framework's client packages against the real
backend and owns no reusable mechanism of its own. The reusable pieces are documented with the
framework in [`client/`](../../../client/README.md); this app composes them:

- **`zen_transport`** — the dual-mode `ZenClient` and `ZenWebSocket`.
- **`zen_identity`** — `SupabaseIdentityRepository`, injected into the UI.
- **`zen_ui_identity`** / **`zen_ui_navigation`** — the adaptive screens and navigation shell.
- **`flutter_riverpod`** — provider wiring; **`flutter_localizations`** + a generated
  `DemoLocalizations` — its own typed strings (`lib/src/l10n/demo_*.arb`, ADR-009), composed
  alongside the packages' own delegates.

## 🚀 Running it

The client reads its backend URL and platform as **compile-time** defines (jZen keeps client
config compile-time so the toolchain can tree-shake — STANDARDS "Client config is
compile-time"), so start the backend first, then pass the defines. The one-command path does
all of this for you:

```bash
task run:demo     # boots Supabase + backend, then runs this client in Chrome pointed at it
```

To run it by hand against an already-running backend:

```bash
cd apps/zen_demo/zen_demo_client
flutter run -d chrome \
  --dart-define=ZEN_ENV=dev \
  --dart-define=ZEN_PLATFORM=web \
  --dart-define=ZEN_API_URL=http://localhost:8085
```

## 🛠️ What each target needs installed

The web build needs only Flutter. Every other target adds something, and each of these was found
by a build failing in a way that did not name the cause — so they are written down here.

| Target | Needs | Failure if missing |
|---|---|---|
| **Web** | Flutter | — |
| **macOS** | Xcode | — |
| **iOS Simulator** | Xcode **and a simulator runtime matching its SDK** (`xcodebuild -downloadPlatform iOS`) | Xcode reports *zero* eligible destinations and the build says only "Unable to find a destination"; it never mentions the runtime |
| **Android** | A **non-GraalVM** JDK selected with `flutter config --jdk-dir` — Java 25 is fine, so the version matches the server; the emulator, and a **complete** system image | A `jlink` stack trace from AGP's `jdkImage` transform that names neither the JDK nor the reason |

```bash
# Android, once per machine. The setting is machine-wide and outranks JAVA_HOME,
# GRADLE_OPTS and org.gradle.java.home — all three were tried and ignored.
sdk install java 25.0.3-tem
flutter config --jdk-dir "$HOME/.sdkman/candidates/java/25.0.3-tem"
```

It is the **distribution** that matters, not the version: GraalVM fails at 17, 21 and 25 alike,
and a standard Java 25 builds cleanly. So the whole product stays on one Java version, and the
repo's pinned GraalVM CE 25 still builds the server. `task run:demo:native` checks this before
building and prints the commands rather than letting Gradle fail obscurely.

Two traps worth knowing, both of which cost real time here:

- An **incomplete Android system image** presents exactly like an out-of-date emulator ("No initial
  system image for this configuration"). Check for `system.img` in
  `$ANDROID_HOME/system-images/<api>/<tag>/<abi>/`; if it is absent, reinstall the image — updating
  the emulator will not help.
- A **sandboxed macOS app cannot make outgoing requests** without
  `com.apple.security.network.client` in its entitlements. `flutter create` does not add it, and
  the failure is silent: the app simply looks permanently logged out. jZen's runner has it in both
  `DebugProfile` and `Release` entitlements — do not remove it.

## 📧 Email links on every platform

A confirmation or recovery link signs the user in wherever the app runs. On the web it lands on
`/auth/callback` and the app reads the tokens out of the URL fragment (ADR-018). On native the
operating system hands the app a `zendemo://auth-callback` URL, `AuthDeepLinks` passes it to
`IdentitySessionStore.consumeAuthLink`, and the rest of the path is identical (ADR-021).

Verified on macOS, the iOS Simulator and the Android emulator, for links that arrive **cold** (the
tap launches the app) and **warm** (it was already running). Three things make it work, and each is
a place it breaks if changed:

- **The scheme is registered in three manifests** - `ios/Runner/Info.plist`,
  `macos/Runner/Info.plist` (`CFBundleURLTypes`) and `android/.../AndroidManifest.xml` (an
  `intent-filter` with `BROWSABLE`). A custom scheme, not Universal/App Links: those need a domain
  serving a verification file and a paid Team ID, and prove nothing extra here.
- **The same string appears in three places or the flow fails silently**: the manifests, the build
  define `--dart-define=ZEN_AUTH_REDIRECT_URI=zendemo://auth-callback`, and the server's
  `AUTH_REDIRECT_URIS` - which accepts a client-named return address only on an *exact* match,
  because that address is where a live session token gets mailed (ADR-019).
- **A cold start is not a warm arrival.** `IdentitySessionStore.build()` only sees the launch URL
  on the web, since off the web `Uri.base` is a file path. The initial link is fetched from the
  plugin and replayed - `lib/src/auth_deep_links_native.dart`.

You do not need email to test it. Take one real token, then replay every case with
`xcrun simctl openurl booted`, `adb shell am start -a android.intent.action.VIEW -d`, or `open`
on macOS.

## 🧪 Testing

Two suites, deliberately kept apart:

| Suite | Command | What it is |
|---|---|---|
| Unit tests (`test/`) | `task test:apps:client` | Fast, offline widget/logic tests. Run headless with the host `ZEN_PLATFORM`. |
| End-to-end (`integration_test/e2e_test.dart`) | `task test:e2e` | The release gate. A **pure-Dart** suite on the VM against the **live** Supabase + Quarkus stack — no mocks. |

The e2e suite is pure Dart (`package:test`, not `flutter_test`) on purpose: it stays headless
and cheap, and because the VM is a `dart:io` platform it exercises the real native cookie jar.
Its base URL comes from `ZEN_API_URL` at runtime — this is a test harness, not the shipped
bundle, and `dart test` does not forward compile-time defines to the compiled test anyway, so
reading it at runtime does not bend the compile-time-config rule (which is about tree-shaking
the *app* bundle). See [`../README.md`](../README.md) for the full list of what it asserts.
