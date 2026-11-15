# zen_store_sync

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**The one call a jZen Local application makes to start sync.** The build's `ZEN_PLATFORM` and
`ZEN_SYNC` choose the transport at compile time; the application reads neither.

```dart
final sync = await ZenSync.start(
  store,
  cloudKitContainerId: 'iCloud.com.example.app',   // iOS, macOS
  sharedFolder: access,                            // Android, Windows, Linux: the chosen folder
  syncKey: pairedKey,                              // null until the device is paired
);
```

| `ZEN_PLATFORM` | `ZEN_SYNC` unset | `folder` | `cloudkit` |
|---|---|---|---|
| `ios`, `macos` | CloudKit | `ZenFolderCloud` | CloudKit |
| `android`, `windows`, `linux` | shared folder | `ZenFolderCloud` | refused |
| `web`, unset, unknown | refused | refused | refused |

A refusal is a `ZenValidationError` that says which define is wrong, never a transport that syncs
nothing. `ZEN_SYNC=folder` also needs `ZEN_SYNC_FOLDER`.

This is the only package that names both `zen_store_cloudkit` and `zen_store_shared_folder`, so
neither depends on the other. Why, and what is not verified: ADR-079.

The package imports `dart:io`, so a web compile fails at that import rather than at runtime; the
web is refused either way (ADR-073).
