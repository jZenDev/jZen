# zen_ui_widgets

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**Shared adaptive widgets for jZen apps — one call, the right chrome on every platform.**

The home for adaptive UI that is neither navigation ([`zen_ui_navigation`](../zen_ui_navigation/README.md)) nor identity
([`zen_ui_identity`](../zen_ui_identity/README.md)). Store conflict screens and locking UI have their
own guides in [`zen_ui_store`](../zen_ui_store/README.md) and [`zen_ui_lock`](../zen_ui_lock/README.md). Controls choose the appropriate platform idiom within the framework, so an app does not
hand-roll a platform check. Apple builds generally use Cupertino; some controls intentionally use
a desktop-friendly Material picker on macOS. Other builds use Material.

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
- **List rows and actions** — `ZenListRow` opens an item with a platform-appropriate row
  interaction; `ZenListItemActions` adapts row actions to desktop, web, and native
  mobile while leaving labels and callbacks to the application.
- **Accessible by construction** — WCAG 2.2 AA: one announcement per control, a `FocusRing` that
  shows for keyboard and assistive technology and hides for a pointer, AA contrast in light and
  dark, text that reflows at 200%. Each control ships with semantics, keyboard and contrast tests.
- **Compile-time, tree-shaken** — the choice is made on `zen_core`'s platform constants, so each
  build keeps only the presentation it takes.
- **Bring your own content** — you supply the body; the overlay owns the surface, size limits,
  barrier and dismissal.

## Interactive Showcase

The reference app has an interactive **Showcase** page for trying these controls. Run
`task run:demo`, sign in, and select **Showcase** in the navigation. The examples use local page
state and are available in English and Ukrainian. See the
[demo instructions](../../apps/zen_demo/README.md#-running-it-showcase) and
[Showcase screen](../../apps/zen_demo/zen_demo_client/lib/src/screens/showcase_screen.dart).

## Widget guide

Examples below use application-owned state, callbacks and localized labels. Import
`package:zen_ui_widgets/zen_ui_widgets.dart`; Flutter types such as `Icons` come from Flutter.
Controllers shown here belong to the app and must be disposed with its state. Pass null callbacks
to disable controls where indicated. See the generated Dart API documentation for every parameter.

### ZenButton

A labelled action. Choose `primary`, `secondary` or `text`; `isLoading` prevents activation while
work runs. A null `onPressed` disables it.

```dart
ZenButton(label: messages.save, onPressed: save);
ZenButton(label: messages.cancel, onPressed: cancel, variant: ZenButtonVariant.text);
```

### AdaptiveInkWell

Make custom content tappable with keyboard activation and a visible focus ring. A null `onTap`
disables it. Supply an accessible label and a suitably sized child, plus a `Material` ancestor.
`borderRadius` shapes the Material ink; Apple builds suppress the ripple.

```dart
AdaptiveInkWell(
  borderRadius: BorderRadius.circular(12),
  onTap: openGoal,
  child: Padding(padding: const EdgeInsets.all(16), child: Text(messages.goal)),
);
```

### ZenIconButton

An icon-only action with a required accessible label and optional non-negative count badge.
A null `onPressed` disables it; a badge of zero is hidden.

```dart
ZenIconButton(icon: Icons.notifications, label: messages.notifications,
  badge: unreadCount, onPressed: openNotifications);
```

### ZenSwitchRow

An on/off setting whose entire row activates. `subtitle` is optional and null `onChanged` disables
it. The caller owns the value. Apple builds use a Cupertino switch without Material ripple.

```dart
ZenSwitchRow(label: messages.archived, subtitle: messages.archivedHelp, value: archived,
  onChanged: (value) => setState(() => archived = value));
```

### ZenListRow

An adaptive row with optional leading and trailing widgets. Supply `title` and `subtitle` as
strings, or use `titleContent` and `subtitleContent` for rich widgets. An omitted `onTap` makes
the row non-interactive; `enabled: false` disables row activation. Trailing controls remain
independently operable. Apple platforms use a Cupertino row; other platforms use Material.
On a narrow Apple row, trailing content moves below the subtitle so amounts and labels have room.
Wrap the row in `ZenListItemActions` to add platform-adaptive item actions.

```dart
ZenListRow(title: account.name, subtitle: account.description,
  onTap: () => openAccount(account));
```

### ZenSelect

Choose one item, or none. The app supplies item labels and owns the chosen value; `onChanged: null`
disables selection. iOS opens a wheel, while macOS and other platforms use a dropdown.

```dart
ZenSelect<Currency>(label: messages.currency, items: Currency.values,
  itemLabel: (currency) => currency.code, value: currency,
  onChanged: (value) => setState(() => currency = value));
```

### ZenSegmentedControl

Select one of two to four mutually exclusive options using `ZenSegment` values and labels.

```dart
ZenSegmentedControl<ViewMode>(
  segments: [ZenSegment(value: ViewMode.list, label: messages.list),
    ZenSegment(value: ViewMode.grid, label: messages.grid)],
  selected: mode, onChanged: (value) => setState(() => mode = value));
```

### ZenTextField

A labelled text input with optional validation, errors, autofill, obscuring and multiline input.
Use it inside a Flutter `Form` when form validation is needed; `enabled: false` disables input.

```dart
ZenTextField(label: messages.name, controller: nameController,
  validator: (value) => value == null || value.isEmpty ? messages.required : null);
```

### ZenDateField

A nullable date with optional bounds, clearing and error text. Null `onChanged` disables it.

```dart
ZenDateField(label: messages.date, value: date, clearable: true,
  onChanged: (value) => setState(() => date = value));
```

### ZenDateRangeField

A pair of dates with an open-ended endpoint allowed. The control checks their ordering and
reports invalid ranges; null `onChanged` disables both fields.

```dart
ZenDateRangeField(fromLabel: messages.from, toLabel: messages.to, from: from, to: to,
  onChanged: (start, end) => setState(() { from = start; to = end; }));
```

### ZenAmountField

A decimal input; `maxFractionDigits` limits precision and `allowNegative` controls the sign.
`onChanged` supplies canonical text or null when the input is not yet a number. The app owns
currency, minor units and rounding. `normalizeAmount` and `parseAmount` are available separately.

```dart
ZenAmountField(label: messages.amount, controller: amountController, maxFractionDigits: 2);
final canonical = normalizeAmount(amountController.text, maxFractionDigits: 2);
```

### ZenAmountRangeField

A minimum and maximum pair, with range validation and optional precision and sign constraints.
The app owns both controllers.

```dart
ZenAmountRangeField(minLabel: messages.minimum, maxLabel: messages.maximum,
  minController: minController, maxController: maxController, maxFractionDigits: 2);
```

### ZenPickerField

A read-only outlined field for an application-defined picker. Supply its displayed `valueText`,
optional placeholder or error, and the callback opening the picker; null `onTap` disables it.
Prefer `ZenSelect` or `ZenDateField` for those existing picker types.

```dart
ZenPickerField(label: messages.category, valueText: categoryName,
  placeholder: messages.chooseCategory, onTap: chooseCategory);
```

### ZenProgressIndicator

An indeterminate spinner for work of unknown length. It is decorative in the semantics tree;
provide a separate accessible status when progress needs to be announced.

```dart
ZenProgressIndicator(size: 24);
```

### ZenProgressBar

A named determinate measure. Values are clamped to 0–1 and announced as a localized percentage.
The application is responsible for contrast if it supplies a custom color.

```dart
ZenProgressBar(label: messages.budgetUsed, value: fractionSpent);
```

### ZenPageScaffold

A page with an adaptive top bar and body. Give the page a title and optional leading/back action
and trailing controls. The body can contain a scrollable list or form.

```dart
ZenPageScaffold(title: messages.accounts, actions: [
  ZenIconButton(icon: Icons.add, label: messages.add, onPressed: addAccount),
], body: accountsList);
```

### ZenDetailHost

Wrap the list once, then call `showZenDetail` from inside it. A wide window displays the detail
beside the list; a narrow window pushes a page. The future resolves with the value used to close it.

```dart
ZenDetailHost(child: Builder(builder: (context) => ZenListRow(
  title: account.name,
  onTap: () => showZenDetail<void>(context, builder: (_) => AccountPage(account: account)),
)));
```

### FocusRing

Use the default constructor inside a focusable custom control, or `FocusRing.wrapping` around
one whose focus node is inside its subtree. The ring appears for keyboard and assistive input.
Framework controls already include it; do not add a second ring around them.

```dart
FocusRing.wrapping(child: customFocusableControl);
```

### ZenListItemActions

Wrap each list item's content in `ZenListItemActions` and supply `ZenListItemAction`s.
For example, inside a `ListView.builder`:

```dart
final item = items[index];
return ZenListItemActions(
  key: ValueKey(item.id),
  showActionsLabel: messages.showActions,
  hideActionsLabel: messages.hideActions,
  child: Text(item.title),
  actions: [
    ZenListItemAction(
      icon: Icons.edit,
      label: messages.editItem,
      onPressed: () => editItem(item),
    ),
    ZenListItemAction(
      icon: Icons.delete,
      label: messages.deleteItem,
      variant: ZenListItemActionVariant.destructive,
      onPressed: () => confirmAndDeleteItem(item),
    ),
  ],
);
```

Import `Icons` from Flutter's Material library and the widget from
`package:zen_ui_widgets/zen_ui_widgets.dart`. The example's `messages`, `items`, and callbacks
belong to the application; use its localized strings for every action and both toggle labels.
A null `onPressed` disables an action. The widget invokes callbacks but does not delete data or
show a confirmation: the application decides when and how to confirm a destructive action.

| Build target (`ZEN_PLATFORM`) | How actions are revealed |
|---|---|
| `macos`, `windows`, `linux` | Continuously visible in the row. |
| `web` | Hover or keyboard focus reveals them with a fade. The visible actions toggle also works with touch. |
| `ios`, `android` | A `Dismissible` invokes the first action on a swipe toward the end and the second on a swipe toward the start. Screen readers can invoke all enabled actions on the item. Applications should also provide actions in item details where appropriate. |

The fade respects the system's reduced-motion setting. Hidden actions are excluded from pointer,
keyboard, and accessibility interaction. Action buttons have the supplied accessible labels and
focus indicators. The web toggle is a separate keyboard and assistive-technology control; do not add
another semantics wrapper around the buttons. Give rows stable keys when items can be reordered,
so state stays associated with the same item. On desktop and web each action reserves 48 logical
pixels even while hidden, so keep the action count appropriate for the available row width. On
mobile, additional actions remain available through accessibility and item details. The component
does not remove the row itself: callbacks own any confirmation and removal, and the row returns
to its original position if it remains in the list.
Use `ZenListItemActionVariant.destructive` for a mobile swipe background using the theme's error
colors; the default `standard` uses its primary colors. Desktop and web buttons retain their usual
appearance. Each background reveals its icon at the outside edge before its label.

The [demo dashboard](../../apps/zen_demo/zen_demo_client/lib/src/screens/dashboard_screen.dart)
shows an example with localized labels and callbacks. Its delete action only reports the selection;
a real application supplies its own confirmation and deletion behavior.

## Presentations, routes and messages

`showAdaptivePresentation<T>` opens a sheet on native mobile and a dialog on desktop and web.
The future returns the value passed to `Navigator.pop`, or null on dismissal. Set
`barrierDismissible: false` when dismissal must occur through the content's actions.

```dart
final saved = await showAdaptivePresentation<bool>(context,
  builder: (context) => EditForm(onSaved: () => Navigator.of(context).pop(true)));
```

`ZenPageRoute<T>` applies the framework's page transition to a pushed page. Set
`ZenPageTransitions.theme` on `ThemeData.pageTransitionsTheme` for other Material routes too.
`ZenFadePageTransitionsBuilder` is the low-level macOS fade builder; most apps use the theme.

```dart
Navigator.of(context).push(ZenPageRoute<void>(builder: (_) => const DetailsPage()));
final theme = ThemeData(pageTransitionsTheme: ZenPageTransitions.theme);
```

`showZenMessage` displays a temporary message (a toast on Apple, a snack bar elsewhere). Supply
both `actionLabel` and `onAction` together for an optional action.

```dart
showZenMessage(context, messages.saved, actionLabel: messages.undo, onAction: undo);
```

## Localization and platform selection

Register `zenWidgetsLocaleDelegate` alongside the app's other delegates in
`MaterialApp.localizationsDelegates` when using controls with framework-owned strings, including
date and amount fields. `ZenWidgetsLocalizations` exposes those typed strings; its exported English
and Ukrainian implementations can be subclassed for application overrides. Application-provided
labels, subtitles and messages must also be localized by the application.

```dart
import 'package:flutter_localizations/flutter_localizations.dart';

MaterialApp(localizationsDelegates: const [
  zenWidgetsLocaleDelegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
], supportedLocales: const [Locale('en'), Locale('uk')], home: const HomePage());
```

`ZEN_PLATFORM` selects the build-time idiom; configure it as shown below. The controls handle
focus and semantics themselves. Avoid wrapping them in another labelled `Semantics` node.

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
`ZenListItemActions` with `ZenListItemAction` for item actions; `ZenButton` (not
ElevatedButton/FilledButton/OutlinedButton/TextButton), `ZenSelect<T>` (not
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
