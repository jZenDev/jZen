# client/ — the Dart/Flutter framework libraries

`client/` is the Dart/Flutter side of the jZen **framework**: a [pub
workspace](https://dart.dev/tools/pub/workspaces) of reusable **library** packages. The
applications that assemble them live under [`apps/`](../apps/zen_demo/README.md), a *second*
workspace that path-depends into these libraries. The two workspaces resolve independently, and
the repository root stays language-neutral (ADR-001).

Every package shares one product version (`0.1.0` today) — jZen is versioned in lockstep
(STANDARDS "Versioning").

## Packages

| Package | Responsibility |
|---|---|
| `zen_core` | Universal result types (`ZenResult`/`ZenError`), value objects, logging, and `ZenLocales` (the supported-locale declaration). Framework-free — depends only on `meta` and small standard libraries, and that isolation is defended, not tolerated. |
| `zen_transport` | The dual-mode `ZenClient` and `ZenWebSocket`, the compile-time codec selector, and the generated Protobuf messages (`lib/src/generated/`). |
| `zen_identity` | The `IdentityRepository` contract and its Supabase-backed implementation, called over `zen_transport`. |
| [`zen_ui_identity`](zen_ui_identity/README.md) | Adaptive Flutter UI for the identity flows (login, register, profile, roles). Speaks the `zen_identity` contract only. |
| [`zen_ui_navigation`](zen_ui_navigation/README.md) | Adaptive, responsive navigation layer (`ZenNavigation`). |

`zen_core`, `zen_transport`, and `zen_identity` are documented here; the two `zen_ui_*` packages
carry their own READMEs because they are shaped for eventual pub.dev publication (they already
ship their own `LICENSE`), which gives them an audience the monorepo view does not serve. Each
`zen_ui_*` package also has an `example/` app demonstrating it in isolation.

## Client config is compile-time (the load-bearing rule)

The Dart/Flutter client keeps **compile-time config** (`String.fromEnvironment`) and
`if (dart.library.io)` / `if (dart.library.html)` conditional imports. This is not a
limitation: it is what lets the toolchain **tree-shake** native-only code (the Protobuf binary
path) out of the JS/Wasm web bundle, and web-only code out of the AOT-native binary. No native
code in a web bundle, and vice versa.

Consequently, **runtime config on the client is forbidden.** The build defines are:

| Define | Values | Meaning |
|---|---|---|
| `ZEN_ENV` | `dev` / `prd` | selects the default wire codec (dev → JSON; prd native → Protobuf; prd web → JSON). |
| `ZEN_PLATFORM` | `ios` / `android` / `web` / `macos` / `windows` / `linux` | the target platform; the UI packages assert it is set. |
| `ZEN_API_URL` | a URL | the backend base URL a runnable app or the e2e suite targets. |

The default codec is **computed** by `selectDefaultCodec()`, never hardcoded — a literal
default would silently disable the negotiation seam on whichever platform it is wrong for
(STANDARDS "Failures surface"). See
[`../docs/architecture/STANDARDS.md`](../docs/architecture/STANDARDS.md) "Client config is
compile-time".

## Localization is typed and generated

Every package that renders text owns its own `lib/src/l10n/*.arb` and generates typed accessors
with `flutter gen-l10n` — never a runtime string-key lookup (ADR-009). The supported set is
`ZenLocales` in `zen_core` (`{en, uk}`, fallback `en`), mirroring the server. An application
composes the delegates in `MaterialApp.localizationsDelegates` and supplies **no wording**.

Unlike the generated Protobuf messages, this output is **built, not committed** (gen-l10n ships
inside the Flutter SDK, so there is no toolchain boundary to carry it across). `task
generate:l10n` produces it; `task sync:contracts` fails if any of it is ever tracked.

## Building, testing, running

From the repository root:

```bash
task deps:client     # resolve the pub workspace
task build:client    # flutter pub get, generate l10n, then dart analyze the whole workspace
task test:client     # run every package's Dart/Flutter tests
```

`task test:client` iterates the workspace members (neither `dart test` nor `flutter test`
aggregates a workspace): a Flutter package runs under `flutter test` with the host `ZEN_PLATFORM`
and `ZEN_ENV=dev`; a pure-Dart package runs under `dart test`. To run one package's tests
directly:

```bash
cd client/zen_transport && dart test test/zen_client_test.dart
```

The transport codec selector is compile-time, so it is tested by **recompiling** per
env/platform: `task test:client:matrix` runs the `dev → json`, `prd native → protobuf`,
`prd web → json` rows.

To run a package's `example/` app on a given platform, pass the define (see each `zen_ui_*`
README):

```bash
cd client/zen_ui_navigation/example
flutter run -d chrome --dart-define=ZEN_PLATFORM=web
```
