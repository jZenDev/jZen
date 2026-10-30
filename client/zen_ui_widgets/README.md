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
- **Controls** — `ZenButton` (primary, secondary, text), `ZenSwitchRow`, `ZenCheckboxRow`,
  `ZenRadioGroup`, `ZenSegmentedControl`, `ZenSelect`, `ZenFilterChip`, `ZenSlider`,
  `ZenRangeSlider`, `ZenSearchField`, `ZenActionMenu`, `ZenExpandableSection`, `ZenDateField`, `ZenTextField`, `ZenAmountField`, `ZenProgressIndicator`, `ZenProgressBar`, and the paired `ZenDateRangeField` /
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

### ZenContentWidth

Center a page body with an app-chosen maximum width and a minimum horizontal gutter. Choose a
larger `maxWidth` for charts or other wide content. Put the boundary inside the page body so the
app bar and navigation remain full width. Place `ZenDetailHost` outside it: the host then chooses
between a pane and a push using its available width. Wrap detail and pushed page bodies separately;
each boundary measures its own pane or page. `MediaQuery` remains the window's size.

```dart
ZenDetailHost(
  child: ZenContentWidth(maxWidth: 720, gutter: 16, child: accountsList),
);
// In the detail page's body:
ZenContentWidth(maxWidth: 960, child: chart);
```

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

### ZenCheckboxRow

A labelled checkbox for an independent choice, a consent, or one item of a multiple selection —
not an on/off setting, which is `ZenSwitchRow`. The whole row is one tap target and one tab stop.
The caller owns `value`: `true` and `false` are a plain checkbox, and **`null` is the mixed state**
("some of the items below"), drawn as a dash and announced as "mixed". A tap always asks for a
definite answer — a mixed or unchecked row reports `true`, a checked one `false` — so a parent
checkbox over a list becomes "all selected" on its first tap; the control never cycles back into
mixed by itself, because only the app knows what its group holds. `subtitle` is read after the
label, and a null `onChanged` disables the row. Apple builds draw a Cupertino checkbox with no
Material ripple.

```dart
ZenCheckboxRow(label: messages.acceptTerms, subtitle: messages.acceptTermsHelp,
  value: accepted, onChanged: (value) => setState(() => accepted = value));

// A parent over a list: null while only some children are selected.
ZenCheckboxRow(label: messages.selectAll, onChanged: selectAll,
  value: selected.length == items.length ? true : (selected.isEmpty ? false : null));
```

### ZenRadioGroup

One choice from a longer list than `ZenSegmentedControl` fits (more than four), without the
pop-up of `ZenSelect`. Pass the group's `label` (its accessible name), `ZenRadioOption`s and the
selected `value`. **A null `value` means nothing is chosen yet**: no option is selected and
`onChanged` stays silent until the user picks one. The group never reports null — once chosen, an
answer can be changed but not cleared, so offer a "None" option when that is a real answer. A
`ZenRadioOption` with `enabled: false` is shown and announced as disabled and the keyboard skips
it; a null `onChanged` disables the whole group. Option values must be unique.

Tab enters the group on the selected option (the first when none is selected) and leaves it with
one more Tab; the arrow keys move the choice, skipping disabled options and wrapping at the ends.
Each option is announced as one radio button ("Yearly, radio button, selected"), and the group by
its label. Apple builds draw Cupertino radios.

```dart
ZenRadioGroup<Plan>(
  label: messages.billing,
  options: [
    ZenRadioOption(value: Plan.monthly, label: messages.monthly),
    ZenRadioOption(value: Plan.quarterly, label: messages.quarterly, enabled: false),
    ZenRadioOption(value: Plan.yearly, label: messages.yearly, subtitle: messages.twoMonthsFree),
  ],
  value: plan, // null: nothing chosen yet
  onChanged: (value) => setState(() => plan = value));
```

### ZenFilterChip

A compact labelled choice that is on or off **independently of its neighbours** — a filter or a
tag. Several can be selected at once. It is a *filter* chip only: an action is a `ZenButton`, and
a single choice among several is a `ZenRadioGroup` or `ZenSegmentedControl`, so each says what it
is to a screen reader. The caller owns `selected`; `onSelected` receives the opposite value, and
null disables the chip. Selection shows as a check mark and a filled capsule — never colour alone
— and is announced as "selected". A long label wraps inside the chip, and chips flow onto new
lines when laid out in a `Wrap`. Material builds use a Material filter chip; Apple builds a
Cupertino capsule (Flutter has none), without Material ripple, at least 44 points tall.

```dart
Wrap(spacing: 8, runSpacing: 4, children: [
  for (final tag in tags)
    ZenFilterChip(label: tag.name, selected: chosen.contains(tag),
      onSelected: tag.available
          ? (on) => setState(() => on ? chosen.add(tag) : chosen.remove(tag))
          : null),
]);
```

### ZenSlider

A labelled slider for one number between `min` and `max` (`min < max`, both finite). The caller
owns `value` and chooses what it means: **`valueFormatter` writes it as text** — for the caption
beside the label and for the screen reader — so units, rounding and separators stay with the app
(the default prints plain numbers). `divisions` makes it stepped: only the `divisions + 1` evenly
spaced values are reported. `onChanged` only ever receives a value inside `[min, max]`; a `value`
outside it is drawn at the nearest end and a NaN at `min` (in debug builds these, and an invalid
range, are assertions). A null `onChanged` disables it.

It is announced once — "Volume, slider, 40 dB" — and a screen reader's increment and decrement
move it a step. Arrow keys move a step (a division, or a tenth of the range), Page Up and Page
Down a page, Home and End to the ends; a focus ring marks keyboard focus. Apple builds draw a
Cupertino slider, whose track is Cupertino's own pale grey: the value shown in text beside it is
what carries the reading, not the track.

```dart
ZenSlider(label: messages.volume, value: volume, min: 0, max: 100,
  valueFormatter: (v) => messages.decibels(v.round()),
  onChanged: (value) => setState(() => volume = value));

ZenSlider(label: messages.rating, value: rating, min: 1, max: 5, divisions: 4, // 1, 2, 3, 4, 5
  onChanged: (value) => setState(() => rating = value));
```

### ZenRangeSlider

A lower and an upper bound within `min`..`max`. Pass `values` as a Flutter `RangeValues` and a
`startLabel` and `endLabel` that name the two thumbs ("Minimum price", "Maximum price"); `label`
names the pair, and `valueFormatter` and `divisions` work as for `ZenSlider`. **The invariant is
`min <= start <= end <= max`, enforced.** The thumbs may meet — `start == end` is a valid, narrow
range — but never cross: the start thumb stops at the end value and the end thumb at the start
value, and moving one never changes the other. When both sit together, a drag moves the thumb
that can go in the dragged direction. A null `onChanged` disables the slider.

Each thumb is its own control: its own tab stop, its own announcement ("Minimum price, slider,
€20") and its own increment/decrement, with Home and End going as far as that thumb may — the
other thumb, not the slider's end. Neither platform's stock range slider can name its two thumbs,
so both idioms are drawn by the framework from one set of rules; the track, the thumb and the
colours are what differ.

```dart
ZenRangeSlider(
  label: messages.price, startLabel: messages.minPrice, endLabel: messages.maxPrice,
  values: price, min: 0, max: 500, divisions: 50,
  valueFormatter: (v) => '€${v.round()}',
  onChanged: (range) => setState(() => price = range));
```

### ZenSearchField

A labelled search input with a clear button — a rounded outlined field on Material, a capsule on
Apple platforms. It is only the input: the data, the ranking and when to search stay with the app,
which filters from `onChanged` (or the controller) and shows its own empty-result state. Pass a
`controller` and it is yours to dispose; pass none and the field owns one. The clear button — named
by the localized "Clear search" (register `zenWidgetsLocaleDelegate`) — appears once there is
text; it is a separate tab stop from the field, empties the controller, reports `''` through
`onChanged` and returns focus to the field. Escape clears a non-empty field too. A disabled
field (`enabled: false`) keeps its text and offers no clear button. `label` is the accessible name;
`hint` is shown while the field is empty. For any other text use `ZenTextField`.

```dart
ZenSearchField(label: messages.searchAccounts, hint: messages.nameOrNumber,
  onChanged: (query) => setState(() => results = accounts.where(matches(query)).toList()));
```

### ZenActionMenu

An icon button named by `label` that opens a menu of `ZenMenuAction`s beneath it — "More actions",
"Language". Each action has a `label`, an optional `icon`, an `onPressed` (null **disables** the
action: shown, announced as disabled, skipped by the keyboard, never fired), `selected` for the
current choice of a set, and `destructive`. Choosing an action closes the menu and runs it once;
Escape or a tap outside closes without running anything, and focus returns to the trigger. Enter,
Space, a click or Down Arrow opens it, and a menu opened from the keyboard puts focus on its first
action; the arrows move through the items. The framework keeps the menu on screen in a narrow
window and wraps long labels. Material builds use a Material menu, Apple builds a Cupertino one.

```dart
ZenActionMenu(label: messages.language, icon: Icons.translate, actions: [
  for (final locale in supported)
    ZenMenuAction(label: locale.name, selected: locale == current,
      onPressed: () => setLocale(locale)),
]);
```

### ZenExpandableSection

A labelled header that shows or hides the content beneath it. The caller owns `expanded`;
`onChanged` receives the opposite value when the header is activated, and null disables the header
(it stays readable and the content stays as `expanded` has it). **Collapsed content is not
painted, not focusable and not read by a screen reader**, so a collapsed field is never a hidden
tab stop. By default the content is discarded once the section closes and rebuilt, fresh, when it
opens; `maintainState: true` keeps it mounted — a half-typed field, a scroll position — while out
of sight. The header is one control ("Advanced options, button, expanded") and a long title
wraps. The content opens with a short animation that is skipped when the system asks for reduced
motion. Apple builds draw a disclosure row with a turning chevron and no Material ripple.

```dart
ZenExpandableSection(title: messages.advanced, subtitle: messages.advancedHelp,
  expanded: open, onChanged: (value) => setState(() => open = value),
  child: AdvancedOptions());
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
DropdownButton), `ZenSegmentedControl<T>`, `ZenSwitchRow`, `ZenCheckboxRow` (not Checkbox),
`ZenRadioGroup<T>` (not Radio), `ZenFilterChip` (not FilterChip), `ZenSlider` / `ZenRangeSlider`
(not Slider/RangeSlider), `ZenSearchField` (not SearchBar), `ZenActionMenu` (not PopupMenuButton),
`ZenExpandableSection` (not ExpansionTile), `ZenDateField` / `ZenDateRangeField` (not
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
