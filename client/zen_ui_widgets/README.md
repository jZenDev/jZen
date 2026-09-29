# zen_ui_widgets

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**Shared adaptive widgets for jZen apps — one call, the right chrome on every platform.**

The home for adaptive UI that is neither navigation (`zen_ui_navigation`) nor identity
(`zen_ui_identity`). Every widget here renders **Cupertino on Apple platforms (iOS and macOS)**
and **Material everywhere else**, so an app never hand-rolls a platform check.

> Part of the [jZen](https://github.com/jZenDev/jZen) monorepo. Inside the repo it is a path
> dependency in the `client/` pub workspace (versioned in lockstep with the product); this
> README also stands on its own for a reader who meets the package by itself.

## 📊 Features

- **Adaptive presentation** — `showAdaptivePresentation` shows a form or detail overlay as a
  sheet on native mobile and a dialog on desktop and web.
- **Compile-time, tree-shaken** — the choice is made on `zen_core`'s platform constants, so each
  build keeps only the presentation it takes.
- **Bring your own content** — you supply the body; the overlay owns the surface, size limits,
  barrier and dismissal.

## 📦 Installation

Inside the jZen client workspace, depend on it by path:

```yaml
dependencies:
  zen_ui_widgets:
    path: ../zen_ui_widgets
```

## 🚀 Quick start

```dart
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

final saved = await showAdaptivePresentation<bool>(
  context,
  builder: (context) => EditForm(onSaved: () => Navigator.of(context).pop(true)),
);
```

| Platform            | Presentation          |
|---------------------|-----------------------|
| Android             | Material bottom sheet |
| iOS                 | Cupertino sheet       |
| macOS               | Cupertino dialog      |
| Linux, Windows, web | Material dialog       |

Web gets the dialog, not the sheet: `zenIsMobile` separates "touch-first native" from everything
else, and a browser on a phone is not native. There is no `MediaQuery` listener; the decision is
a constant.

## 📱 Platform support (compile-time)

Specify the platform with the `ZEN_PLATFORM` define, as for every jZen UI package
(`docs/architecture/STANDARDS.md`); a debug assertion fails when it is unset:

```bash
flutter run --dart-define=ZEN_PLATFORM=ios
flutter run -d chrome --dart-define=ZEN_PLATFORM=web
```

Supported values: `ios`, `android`, `web`, `macos`, `windows`, `linux`.

## 🍎 Cupertino on macOS

Flutter's `Cupertino*` widgets emulate iOS Human Interface Guidelines, not macOS AppKit. Using
them on macOS is a deliberate approximation — closer to native than Material on a Mac, not
pixel-correct AppKit. A dedicated macOS design kit is a separate, later decision.

## 📄 License

Apache License 2.0 — see [LICENSE](LICENSE).
