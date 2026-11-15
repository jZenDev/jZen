# Flutter 3.50 / Dart 3.14 migration: analysis and plan

**Issue:** #212. **Toolchain verified on the dev machine:** Flutter 3.50.0 (stable, framework
`ab2912035e`), Dart 3.14.0. **Decision record:** ADR-082.

Sources read (not recalled): the Flutter [breaking changes index](https://docs.flutter.dev/release/breaking-changes),
the guides it links for 3.50 (`material-ui-and-cupertino-ui`, `dropdownbuttonformfield-enabled-parameter`),
the Flutter 3.50.0 release notes, and the Dart SDK `CHANGELOG.md` section for 3.14.0.

## 1. What affects jZen

| Change | Source | Touches jZen? | Action |
|---|---|---|---|
| `package:flutter/material.dart` and `cupertino.dart` formally deprecated; replaced by the standalone `material_ui` / `cupertino_ui` packages (`deprecated_member_use` infos from the analyzer) | Flutter 3.50 breaking change | **Yes, the only large one.** 193 Dart files in 9 packages and both apps imported them; the analyzer reported 210 infos | `dart fix --apply --code=migrate_design_widgets` (205 + 39 fixes), then `material_ui`/`cupertino_ui` added to each package that imports them |
| Material/Cupertino/Widgets localization delegates move into `material_ui`; `GlobalMaterialLocalizations.delegates` bundles all three | same | Yes: 4 test harnesses and the `zen_ui_identity` / `zen_ui_widgets` docs listed the three delegates one by one | Replaced with `...GlobalMaterialLocalizations.delegates`. `flutter_localizations` stays a dependency: `flutter gen-l10n` output and `intl` pinning still come through it |
| `DropdownButtonFormField.enabled`, `onChanged` optional (`material_ui` 1.8.0) | breaking change guide | `ZenSelect` uses `DropdownButtonFormField`; the change is backward compatible | None |
| `MaterialUiCompatibilityBridge` for dependencies that still import the SDK libraries | guide | No dependency of ours imports them (the analyzer finds no remaining use) | None |
| `describeEnum` removed (3.47), `onReorder` deprecated, `cacheExtent` deprecated, `IconData` final, `TextInputConnection.setStyle` deprecated (3.44) | breaking change index | Searched `client/` and `apps/`: no use | None |
| Semantics `header`/`headingLevel` on iOS and Android (3.47), soft hyphens, `WidgetSpan` RTL order, web `viewport-fit=cover` `SafeArea` | breaking change index | Behavioural, not compile-time; covered by the accessibility suites and the e2e/widget tests | Run suites |
| Android: stricter entrypoint `Intent` verification, restricted engine flags in release, built-in Kotlin (3.44), AGP 9 | breaking change index / release notes | `zen_demo_local` already builds on AGP 9.3.1 + `org.jetbrains.kotlin.android` | Verified by CI `android-runner` only (no device build here) |
| Dart 3.14: `dart:mirrors` deprecated, `dart2wasm` requires `wasm:js-string`, `dart.library.isolate` is `false` for wasm, `dart:js_interop` additions, `dart pub upgrade pkg@constraint` | Dart changelog | No use of `dart:mirrors`; the compile-time `if (dart.library.io/html)` seams are unchanged; `isolate` is not a conditional import key here | `test:client:matrix` and the web build prove it |
| New lints: `prefer_initializing_formals` now flags private named parameters (Dart 3.12 private named parameters), `deprecated_member_use` for `axisAlignment` (`SizeTransition`) and `pipelineOwner` | analyzer | 4 infos | Fixed (`this._key`, `alignment: AlignmentDirectional(1, -1)`, `rootPipelineOwner`) |
| `flutter gen-l10n`, pub workspaces, `.pb.dart` | release notes | Release notes list only the decoupled-localizations deprecation for gen-l10n; workspaces unchanged | `task verify:contracts`: regeneration produced no drift |
| Generated `XLocalizations.localizationsDelegates` (gen-l10n) still register the **SDK's** `GlobalMaterialLocalizations`, which `material_ui`'s `MaterialApp` does not look up | found by the suite (`zen_ui_navigation`, locale `uk`: "A MaterialLocalizations delegate that supports the uk locale was not found") | **Yes, a runtime break, not a lint** | Every composition of a generated list now appends `...GlobalMaterialLocalizations.delegates` from `material_ui` (apps, examples, tests, docs) |
| Flutter 3.50's Gradle plugin refuses Gradle < 9.3.1 | found by `task build` (`zen_demo_client` was on Gradle 9.1.0, AGP 9.0.1, Kotlin 2.3.20) | Yes | `zen_demo_client` aligned with `zen_demo_local_client`: Gradle 9.5.0, AGP 9.3.1, Kotlin 2.4.20 |
| `identity_text_field_test` looked for Material's `TextField` on an Apple host, where the field is Cupertino | found by `task test` on macOS (fails identically on `main`) | Test defect, independent of the SDK | The test finds `CupertinoTextField` on Apple platforms |
| Third-party plugins (`protobuf`, `flutter_secure_storage`, `local_auth` + the Windows stand-in, SAF/folder, QR/scanner, CloudKit SwiftPM, file watchers) | pub resolution | `flutter pub get` resolves unchanged for both workspaces; no constraint was loosened | Verified by suites; native builds by CI |

## 2. Plan and package order

1. Pins: `.fvmrc`, CI (`subosito/flutter-action` x5), every `environment.sdk` to `>=3.14.0 <4.0.0`,
   `zen_ui_widgets` `flutter: >=3.50.0`, `task doctor` (reads `.fvmrc`, so it follows).
2. Baseline: `dart analyze` on both workspaces to see the new infos.
3. Imports, bottom-up through the dependency order: `zen_ui_widgets` -> `zen_ui_navigation`,
   `zen_ui_identity`, `zen_ui_lock`, `zen_ui_store` -> `zen_demo_client`, `zen_demo_local_client`.
   `zen_core`, `zen_transport`, `zen_identity`, `zen_store*`, `zen_secure_store` import neither library.
4. Delegates, docs, lint fixes.
5. Gates: `verify:contracts`, `verify:widget-files`, `build`, `test` (includes `test:client:matrix`,
   `test:e2e`, `test:apps:server`), then CI on all runners.

## 3. Risks

- **Type identity.** `material_ui` types are distinct from `flutter/material.dart` types. A dependency
  that exposes the old types in its public API would fail to type-check; none does here.
- **Package versions float.** `material_ui` moves to weekly releases; the lockfiles pin what was tested.
- **Native runners** (Android, Windows, macOS/iOS CloudKit SwiftPM) cannot all run on this machine;
  they are verified by CI, and anything CI cannot show is listed in the PR.
- **Formatter.** The committed layout is from an older Dart formatter; this migration does not reformat.

## 4. Server

The Java server (Quarkus 3.38.2, Java 25) is untouched: a Flutter/Dart upgrade does not reach it. It is
rebuilt and tested by `task test:apps:server` as part of `task test`.
