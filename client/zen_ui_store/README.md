# zen_ui_store

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**When two devices disagree, the person decides — and this is the screen where they do.**

`zen_store` never settles a conflict on its own (ADR-065): it keeps every device's version and
refuses writes to the record until someone chooses. This package is where they choose, so a Local
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
ZenConflictBanner(store: store, sources: sources, issues: issues)
```

**Your own cross-record problems** (a goal below zero after two withdrawals, a record on an account
deleted elsewhere) go in the same place. Re-check your rules and return what is wrong now; they
count in the banner and appear in the list beside the field conflicts, each with your action
buttons. Never fix one silently.

```dart
final issues = [
  ZenIssueSource(
    issues: () => [
      for (final goal in goals.list().dataOrNull!)
        if (goal.balance < 0)
          ZenIssue(
            id: 'goal-${goal.id}',
            title: '${goal.name} is below zero',
            description: 'Two withdrawals on two devices took it to ${goal.balance}.',
            actions: [ZenIssueAction(label: 'Set it to zero', run: () => zeroGoal(goal))],
          ),
    ],
  ),
];
```

An action can need something from the person first. `ZenIssueAction.choose` takes
`choices: [(id, label), ...]` and a `run: (id) => ...`; `ZenIssueAction.text` takes a `fieldLabel` and
a `run: (text) => ...`. The issue screen asks (a list of choices, or a text field, in the platform's
sheet or dialog) and calls `run` only once the person confirms. `choices` may hold a single candidate,
which the person still picks and confirms, so there is no need to branch on the count; it may not be
empty, so leave the action out when there is nothing to choose. A text is trimmed, and one that is
empty or only whitespace cannot be confirmed. `ZenIssueAction` is sealed (plain, choice, text), so a
`switch` over it is exhaustive. Cancelling runs nothing and the issue
stays; a failed `run` is shown on the screen like any other action's.

```dart
ZenIssueAction.choose(
  label: 'Move to…',
  choices: [(savings.id, 'Savings'), (wallet.id, 'Wallet')],
  run: (accountId) => moveRecord(record, accountId),
),
ZenIssueAction.text(label: 'Bring it back', fieldLabel: 'Name', run: (name) => restore(id, name)),
```

Register `storeLocaleDelegate` in `MaterialApp.localizationsDelegates`.

## 🧩 What the person sees

- **The banner**: "2 items were changed on two devices and need your choice", with **Review**. It
  takes no space when there is nothing to decide.
- **The list** (`ZenConflictsScreen`): each record by the app's own title, with the devices
  involved, each named once ("Phone (2 versions)" where one device has two). It refreshes when the
  store changes, so a conflict settled on another device leaves on its own.
- **The versions** (`ZenConflictResolveScreen`): one card per version — the device's name, when it
  wrote, and the disputed fields' values — each with **Keep this version**. Cards under one name
  are numbered ("Phone, version 1 of 2"): a device can have several versions in dispute
  (ADR-089), and two devices can be named alike. For a delete against an edit,
  one card says "Deleted on this device" (**Keep it deleted**), and the other shows every field of
  the edited record, so the person sees what deleting would throw away. A choice is saved only
  against the versions shown: when a sync has changed the record since, nothing is written, and
  the screen says so and shows what is there now, or that it was already settled.
- **The sync status** (`ZenSyncStatusBanner`): while sync is stopped, why, in words the person can
  act on — not signed in to iCloud, iCloud Keychain off, a different account, the cloud data
  deleted, storage full, an app update needed. It takes no space while sync works: a sync that
  stops quietly would leave the person believing their other devices see their edits.

- **Adding a device** (`ZenAddDeviceScreen`, `ZenJoinScreen`, ADR-077): the old device shows a
  QR code and 77 typed characters only after "Show Code", counts down five minutes, and withdraws
  the code at expiry, on Cancel and when the app leaves the screen. The new device scans it (pass a
  `ZenQrScannerBuilder` built on `mobile_scanner` where there is a camera) or types it in a hidden
  field; a typo is reported by group. The screen hands the key to your `onKey`; the code is never
  logged, put in a URL or copied, and **it is the sync key**, so show it only to yourself.

Only `title` is required. A field is shown by its proto name and value until `fieldLabel` and
`fieldValue` give the app's words and formatting.

## 🧪 Test

```sh
cd client/zen_ui_store && flutter test --dart-define=ZEN_PLATFORM=ios
```

The suite builds real conflicts between two real stores and resolves them through the screens,
under the iOS, Android and macOS idioms, with AA contrast, target size and 200% text checks.
