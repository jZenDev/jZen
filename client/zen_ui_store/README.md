# zen_ui_store

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**When two devices disagree, the person decides — and this is the screen where they do.**

`zen_store` never settles a conflict on its own (ADR-065): it keeps every device's version and
refuses writes to the record until someone chooses. This package is where they choose, so a light
app does not have to build its own.

## 🚀 Use

```dart
final sources = [
  ZenConflictSource<Record>(
    collection: records,
    title: (r) => '${r.note}, ${formatDate(r.date)}',          // how the person recognises it
    fieldLabel: (field) => switch (field) { 3 => 'Amount', 5 => 'Category', _ => null },
    fieldValue: (r, field) => field == 3 ? formatMoney(r.amount) : null,
  ),
  ZenConflictSource<Account>(collection: accounts, title: (a) => a.name),
];

// Above the main screen's content, where they are seen on every launch:
ZenSyncStatusBanner(transport: sync)
ZenConflictBanner(store: store, sources: sources)
```

Register `storeLocaleDelegate` in `MaterialApp.localizationsDelegates`.

## 🧩 What the person sees

- **The banner**: "2 items were changed on two devices and need your choice", with **Review**. It
  takes no space when there is nothing to decide.
- **The list** (`ZenConflictsScreen`): each record by the app's own title, with the devices
  involved. It refreshes when the store changes, so a conflict settled on another device leaves on
  its own.
- **The versions** (`ZenConflictResolveScreen`): one card per device — its name, when it wrote,
  and the disputed fields' values — each with **Keep this version**. For a delete against an edit,
  one card says "Deleted on this device" (**Keep it deleted**), and the other shows every field of
  the edited record, so the person sees what deleting would throw away.
- **The sync status** (`ZenSyncStatusBanner`): while sync is stopped, why, in words the person can
  act on — not signed in to iCloud, iCloud Keychain off, a different account, the cloud data
  deleted, storage full, an app update needed. It takes no space while sync works: a sync that
  stops quietly would leave the person believing their other devices see their edits.

Only `title` is required. A field is shown by its proto name and value until `fieldLabel` and
`fieldValue` give the app's words and formatting.

## 🧪 Test

```sh
cd client/zen_ui_store && flutter test --dart-define=ZEN_PLATFORM=ios
```

The suite builds real conflicts between two real stores and resolves them through the screens,
under the iOS, Android and macOS idioms, with AA contrast, target size and 200% text checks.
