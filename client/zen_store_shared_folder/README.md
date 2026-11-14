# zen_store_shared_folder

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**Sync for a jZen Local application over a folder the person chooses**, kept in step by a sync
service of their own (Syncthing, Dropbox, OneDrive, Nextcloud, ...). It is the transport for
Android, Windows and Linux; CloudKit (`zen_store_cloudkit`) is the one for iOS and macOS. See
`docs/architecture/DECISIONS.md` ADR-075.

```
<folder>/<device id>/<64 hex>.zen        one file per record, written by that device only
```

- **One writer per file.** A device writes inside its own directory and reads everyone's, so a
  sync service never sees a file two devices changed: no "conflicted copy", no silent overwrite.
  Combining devices is `zen_store`'s per-field merge; a real conflict goes to the person.
- **Encrypted.** AES-256-GCM with a key derived from the shared sync key, the file's path as
  associated data, file names an HMAC of the record's name. The service sees ciphertext.
- **Tolerant.** A half-delivered, damaged, foreign-key, moved or newer-format file is skipped,
  named in `ZenSyncReport.problems` and read again next time; a "conflicted copy" is ignored by
  name. Writes are temp-file-then-rename.
- **Local.** Polling, plus the folder's watcher where the platform has one. No network code.

## Use

```dart
final store = (await ZenStore.open(dir, deviceName: name, key: storeKey)).dataOrNull!;
final sync = await ZenSharedFolderSync.start(
  store,
  ZenDirectoryAccess(chosenFolder), // desktop; Android supplies a SAF-backed ZenFolderAccess
  syncKey: syncKey,                 // null until the device is paired -> ZenSyncIssue.notPaired
);
// ZenSyncStatusBanner(transport: sync.dataOrNull!) shows why it stopped, if it did.
```

`ZenFolderAccess` is the seam: `dart:io` on desktop, the Storage Access Framework on Android
(ADR-075 records the choice of plugin and what is not yet verified on a device).

## Not here

The sync key reaches a device by pairing (a separate package), and the key store, folder picker
and transport selection by platform are the application's and later units' work.
