# zen_core

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**The one dependency every other package can afford: zero magic, zero framework, just results and value objects.**

The framework-free core of the jZen client: universal result types, value objects, logging, and
the supported-locale declaration. It is the one package everything else can depend on without
inheriting a framework — it depends only on `meta` and small, standard, inspectable libraries,
and that isolation is **defended, not tolerated** (it is what lets every other module use the
result types without pulling Flutter or a transport in).

> Part of the [jZen](https://github.com/jZenDev/jZen) monorepo. Inside the repo it is a path
> dependency in the `client/` pub workspace, versioned in lockstep with the product; this README
> also stands on its own for a reader who meets the package by itself.

## 🧘 What it provides

- **`ZenResult` / `ZenError`** — a success-or-failure result type. A caller must be able to tell
  "the server said nothing" from "I could not understand what the server said", so failures are
  values, never a null payload.
- **Value objects and ids** — small typed wrappers instead of bare strings.
- **`ZenLocales`** — the single declaration of the locales jZen itself **ships** strings for
  (`shipped = {en, uk}`, fallback `en`), mirrored by the server's `zen.core.i18n.ZenLocales`. Every
  localized package tests its own locale set against this, so an ARB set cannot drift from the
  strings the package claims to have. It is an inventory, **not** a limit on what an application
  supports: that set is the app's, and `resolve(tag, against:)` takes it (ADR-044).
- **Logging** — a small logger with a platform-appropriate strategy chosen by conditional import.

## 🚀 Using it

Inside the jZen client workspace, depend on it by path (the distribution mechanism until the
package is published — see [`../README.md`](../README.md)):

```yaml
dependencies:
  zen_core:
    path: ../zen_core
```

```dart
import 'package:zen_core/zen_core.dart';

final result = ZenResult.ok(42);
result.fold((v) => print('value: $v'), (e) => print('error: ${e.code}'));
```

## 🧪 Testing

From the repository root, `task test:client` runs this package's suite (pure Dart, `dart test`).
Directly: `cd client/zen_core && dart test`.
