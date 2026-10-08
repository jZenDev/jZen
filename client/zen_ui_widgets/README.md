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
- **Details and pushed pages** — `showZenDetail` opens a list item's detail beside the list when the
  window is wide (an in-layout pane on Apple, a side sheet elsewhere) and as a full-screen push when
  it is narrow; wrap the list in a `ZenDetailHost`. `ZenPageRoute` and `ZenPageTransitions.theme`
  give a pushed page the iOS slide on iOS and a short fade, navigation bar included, in a native
  macOS build; a web build, even in a browser on a Mac, keeps Flutter's own default.
- **Controls** — `ZenButton` (primary, secondary, text), `ZenSwitchRow`, `ZenSegmentedControl`,
  `ZenSelect`, `ZenDateField`, `ZenTextField`, `ZenAmountField`, `ZenProgressIndicator`, `ZenProgressBar`, and the paired `ZenDateRangeField` /
  `ZenAmountRangeField`, which enforce `from <= to` / `min <= max` in one place.
- **Accessible by construction** — WCAG 2.2 AA: one announcement per control, a `FocusRing` that
  shows for keyboard and assistive technology and hides for a pointer, AA contrast in light and
  dark, text that reflows at 200%. Each control ships with semantics, keyboard and contrast tests.
- **Compile-time, tree-shaken** — the choice is made on `zen_core`'s platform constants, so each
  build keeps only the presentation it takes.
- **Bring your own content** — you supply the body; the overlay owns the surface, size limits,
  barrier and dismissal.

## 🧩 Controls

```dart
ZenButton(label: 'Save', onPressed: save);
ZenButton(label: 'Cancel', onPressed: cancel, variant: ZenButtonVariant.text);

ZenSelect<Currency>(
  label: 'Currency',
  items: Currency.values,
  itemLabel: (c) => c.code,
  value: currency,
  onChanged: (c) => setState(() => currency = c),
);

ZenDateRangeField(
  fromLabel: 'From',
  toLabel: 'To',
  from: from,
  to: to,
  onChanged: (f, t) => setState(() { from = f; to = t; }),
);

ZenAmountField(label: 'Amount', controller: amount, maxFractionDigits: 2);
final String? canonical = normalizeAmount(amount.text, maxFractionDigits: 2); // "1234.5" or null
```

The amount field is the *field and validation shape* only. What a number means — minor units,
currency — stays with your app, which reads the canonical text.

The controls' few strings (validation errors, "Select a date") come from
`ZenWidgetsLocalizations`; register `zenWidgetsLocaleDelegate` in `MaterialApp`. An app using only
`showAdaptivePresentation` needs no delegate.

| Control | Apple platforms | Elsewhere |
|---|---|---|
| `ZenButton` | `CupertinoButton` | Filled / Outlined / Text button |
| `ZenSwitchRow` | `CupertinoSwitch` row | `SwitchListTile` |
| `ZenSegmentedControl` | sliding segmented control | `SegmentedButton` |
| `ZenSelect`, `ZenDateField` | wheel picker on **iOS**; macOS keeps the dropdown / calendar | dropdown / calendar dialog |
| `ZenTextField`, `ZenAmountField` | `CupertinoTextField` (label above, outlined, shared focus ring) — on iOS and macOS | outlined `TextFormField` |
| `ZenProgressIndicator` | `CupertinoActivityIndicator` | `CircularProgressIndicator` |
| `ZenProgressBar` | rounded bar in the theme's primary | `LinearProgressIndicator` |

## 🤖 For applications and their coding agents

**Build screens from these controls, not raw Material.** A product on jZen should not hand-roll an
`ElevatedButton`, `DropdownButton`, `showDatePicker` or a `showDialog` for a form — use the control
above. The framework owns the platform idiom, the focus ring, the announcement and the contrast; fixing
one of them here fixes every app. The full rule and the widget-for-widget table are in the jZen repo:
`docs/architecture/STANDARDS.md`, "Client UI: the framework's controls first".

Copy this into your application's `CLAUDE.md` (or equivalent agent instructions):

```markdown
## UI controls

Build Flutter screens from the jZen framework's controls, never raw Material equivalents:
`ZenButton` (not ElevatedButton/FilledButton/OutlinedButton/TextButton), `ZenSelect<T>` (not
DropdownButton), `ZenSegmentedControl<T>`, `ZenSwitchRow`, `ZenDateField` / `ZenDateRangeField` (not
showDatePicker), `ZenTextField` (not TextField/TextFormField), `ZenAmountField` / `ZenAmountRangeField`
(+ `normalizeAmount`), `ZenProgressIndicator` (not CircularProgressIndicator), `ZenProgressBar` (not LinearProgressIndicator), and
`showAdaptivePresentation` (not showDialog/showModalBottomSheet), all from
`package:zen_ui_widgets/zen_ui_widgets.dart`. Sign-in and the shell come from `zen_ui_identity` and
`zen_ui_navigation`. Never branch on platform to pick Cupertino vs Material. Do not wrap these in
`Semantics(label:, button:)`: they already announce once. Money semantics (minor units, currency)
stay in the app; read `normalizeAmount(text)`. If a generic control is missing, add it to
`zen_ui_widgets` upstream rather than hand-rolling it in the app.
```

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
