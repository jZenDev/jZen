---
name: use-zen-ui
description: Build or change a Flutter screen in a jZen app with the framework's controls instead of raw Material, one widget class per file. Use whenever you write or edit UI code under apps/*/*_client or a zen_ui_* package - a button, dropdown, date or amount input, segmented control, switch, dialog or bottom sheet, or a focus indicator. Encodes the widget-for-widget table, the one-widget-per-file rule, the accessibility bar, and what to do when a control is missing.
---

# Using jZen's UI controls

An application's screens are **assembled from the framework's UI packages**; the app supplies content
and callbacks, the framework owns how a control looks per platform, how it is announced, and where
focus shows. The rule and its reasoning are in `docs/architecture/STANDARDS.md`
"Client UI: the framework's controls first" (ADR-055). This is the working version.

## Reach for the framework control first

Import `package:zen_ui_widgets/zen_ui_widgets.dart` and use:

| You need | Use | Not |
|---|---|---|
| Dialog or sheet for a form/detail | `showAdaptivePresentation<T>(context, builder: ...)` | `showDialog`, `showModalBottomSheet` |
| Action button | `ZenButton(label:, onPressed:, variant:)` - `primary`, `secondary`, `text`; `isLoading`, `icon` | `ElevatedButton`, `FilledButton`, `OutlinedButton`, `TextButton` |
| One choice from a list | `ZenSelect<T>(label:, items:, itemLabel:, value:, onChanged:)` | `DropdownButton(FormField)` |
| Few exclusive options | `ZenSegmentedControl<T>(segments: [ZenSegment(value:, label:)], selected:, onChanged:)` | `SegmentedButton` |
| Boolean setting | `ZenSwitchRow(label:, value:, onChanged:)` | `SwitchListTile`, `Switch` |
| A date | `ZenDateField(label:, value:, onChanged:, clearable:)` | `showDatePicker` |
| A from/to period | `ZenDateRangeField(fromLabel:, toLabel:, from:, to:, onChanged:)` | two date fields |
| A text input (name, email, password) | `ZenTextField(label:, controller:, validator:, obscureText:)` | `TextField`, `TextFormField` |
| A loading spinner | `ZenProgressIndicator(size:)` | `CircularProgressIndicator` |
| A decimal number | `ZenAmountField(label:, controller:, maxFractionDigits:)`; read with `normalizeAmount(text)` | `TextField` + numeric keyboard |
| A min/max pair | `ZenAmountRangeField(minLabel:, maxLabel:, minController:, maxController:)` | two amount fields |
| Focus ring on your own control | `FocusRing` / `FocusRing.wrapping` | a hand-drawn focus border |
| Sign-in / register / profile | `zen_ui_identity` screens | hand-built forms |
| Navigation shell | `ZenNavigation` | per-screen `NavigationBar`/`NavigationRail` |

Register `zenWidgetsLocaleDelegate` (beside the other jZen delegates) once the app uses a date or
amount field - they speak a few strings of their own. Never pass an app-written error string for a
condition the control already reports (bad number, reversed range).

## Do not

- **Do not branch on platform to choose Cupertino or Material** for these controls. The package does it
  on a compile-time constant so the other idiom is tree-shaken. Re-implementing the branch defeats that.
- **Do not put minor-units, currency or rounding logic in a control.** `ZenAmountField` is the field
  shape; `normalizeAmount` returns canonical text (`"1234.5"`) and the app owns what it means.
- **Do not wrap a control in `Semantics(label:, button:, selected:)`.** The controls already announce
  once; wrapping makes a screen reader read them two or three times (STANDARDS "Accessibility").
- **Do not check a range at the call site.** `from <= to` and `min <= max` live in the range widgets.

## One widget per file

A widget class gets **its own file, named for the class in snake_case** (`DemoSplash` ->
`demo_splash.dart`), as with Java's one class per file. This binds a screen's helper widgets too:

- Extract a helper as a **public** class in its own file. Do not leave a private `_Foo` widget at the
  bottom of the screen that uses it - that is the pattern `task verify:widget-files` exists to catch.
- **Exception: a `StatefulWidget` and its own private `State` stay together** in one file. Flutter
  needs `State` private to and beside its widget, so the pair is one unit.
- Notifiers, painters and param objects are not widgets and are outside the rule.
- Do not add an exemption to get the gate green. An entry in a suppressions file needs a reason that
  says what the file carries that splitting would lose; "awkward to split" is not one. Split it.

`task verify:widget-files` runs in `task test` and as the first step of `zen:test:client`, so a
consuming app gets it from `Taskfile.app.yml`. STANDARDS "One widget per file" has the reasoning.

## If the control you need is not there

That is a **framework gap, not permission to hand-roll**. Decide by concern:

- Generic (a chip, a stepper, a search field) -> add it to `client/zen_ui_widgets`, Cupertino on Apple
  and Material elsewhere behind the `zenIsApplePlatform` constant, then use it from the app.
- Navigation- or identity-specific -> `zen_ui_navigation` / `zen_ui_identity`.
- Specific to one screen's domain (a chart, a transaction row) -> the app's own widget; it still meets
  the accessibility bar and uses `FocusRing`.

A new `zen_ui_widgets` control ships with its suite in the same change. Copy the shape of
`client/zen_ui_widgets/test/widgets/zen_button_test.dart`: build **both idioms directly** (a run only
reaches the host's branch), and check the merged semantics tree (one node, named once, right state),
Tab/Enter/Space and the ring, `meetsGuideline(textContrastGuideline)` across the four `auditThemes`,
and 200% text. Then run `task test:client`, and the package under `--platform chrome`.

Things a widget that merely wraps a stock one gets wrong, found by that suite: a disabled
`CupertinoButton` still advertises a tap and no disabled state; a web `CupertinoButton` ignores Enter;
swapping a bare child for a `Stack` when focus arrives remounts the control and drops focus; a text
field's error text sits on a node a screen reader never lands on unless the field is `MergeSemantics`.
