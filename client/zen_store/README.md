# zen_store

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

**A light jZen app's data, encrypted on the user's own devices — and no edit is ever dropped
without them knowing.**

Proto messages stored by collection and id in a directory on this device, encrypted with a key the
app keeps in the Keychain, and kept in step with the user's other devices by a sync transport
(CloudKit, via `zen_store_cloudkit`). Every call answers with a `ZenResult`, as `ZenClient` does.
See `docs/architecture/DECISIONS.md` ADR-065.

## 🚀 Use

```dart
final store = (await ZenStore.open(
  directory,                       // the app's own, e.g. Application Support
  deviceName: "Alex's iPhone",     // what the other devices show in a conflict
  key: key,                        // 32 bytes from the Keychain (ZenKeychainStoreKey)
)).dataOrNull!;
final accounts = store.collection('accounts', Account.fromBuffer);

await accounts.put(store.newId(), Account(name: 'Cash'));
final all = accounts.list();             // ZenResult<List<Account>>, ordered by id
accounts.changes.listen((_) => ...);     // a local write or a sync changed it

// Optional: without a transport the store is local-only.
final sync = await ZenCloudKitSync.start(store);     // release
// final sync = await ZenFolderCloud.start(store, folder);   // development, ZEN_SYNC=folder
```

Sync runs on its own once started: a local write is handed to the transport at once, and other
devices' changes arrive and merge in the background. `store.conflictCount` says when the person
must choose; `zen_ui_store`'s `ZenConflictBanner` shows it.

## 💾 How it is stored on the device

**No database — not SQLite, not Hive or Isar.** The store is a set of files in the directory the
app passes to `ZenStore.open`:

| File | Holds |
|---|---|
| `device.id` | This device's random id, made on first open. |
| `meta.zen` | The device names, which records wait to be sent, and the transport's change token. |
| `records/00.zen` … `records/3f.zen` | The records, sharded by a hash of their name into 64 files, each record versioned per proto field. |

- **Encrypted, always.** Every file but `device.id` is AES-256-GCM with the key passed to `open`
  and a fresh nonce per write, the file's own name bound in as associated data so files cannot be
  swapped. The key lives in the Keychain, this device only, readable while the device is unlocked;
  this package takes it as bytes and never stores it. On iOS the directory also gets Data
  Protection `complete` (`ZenKeychainStoreKey.protectDirectory`).
- **Offline first, always.** Every read and write works with no network and no iCloud account.
- **Everything is held in memory.** `open` decrypts and parses the files; every read after that is
  a map lookup, which is why reads are synchronous.
- **A write rewrites only its shard, atomically**: a temporary file, flushed, then renamed over
  the old one, so a crash or a full disk leaves the previous file, never half of one. A write's
  future completes only once that is on disk.
- **Where:** the app's own data directory — `getApplicationSupportDirectory()` from
  `path_provider`, not `Documents` (visible in the Files app) and not a cache directory (which the
  system may empty).

Being pure Dart keeps the suite on the Dart VM running the real cipher (`cryptography`, which uses
CryptoKit on Apple platforms once `zen_store_cloudkit` registers it). `zen_ui_lock`'s PIN is a door
in front of the app, not the key to these files.

**Scale is not measured yet** for this layout; the numbers in ADR-065 describe the one-log-per-device
design it replaced.

## 🔄 How sync merges

- A transport implements `ZenSyncTransport`. The store tracks which records this device changed and
  no transport has confirmed (`unsent`), hands each out as an opaque payload — the record's whole
  state — merges each payload it receives, and keeps the transport's change token in `meta.zen`.
- A record is versioned **per proto field**. Each version carries a version vector — per device,
  how many of its writes it had seen — which tells an edit that *replaced* another from one made
  *alongside* it. Wall-clock time is shown to the person and never used to decide.
- **Merged on their own:** edits to different fields of one record; the same value set on two
  devices; anything edited after seeing the other device's change.
- **A conflict, for the person:** one field set to different values on two devices, or a delete on
  one device against an edit on another that never saw it.

## 🧪 Developing sync without an Apple account

`ZenFolderCloud` emulates CloudKit in a folder on disk — change tags, a refused save that returns
the server's copy, change tokens — under a file lock. An iOS Simulator app runs as a process on the
Mac and sees its files, so a macOS build and a simulator build pointed at one folder sync as two
devices. Choose it at compile time (`--dart-define=ZEN_SYNC=folder`). It stores payloads as they
are and uploads nothing: **development only**, never what a release build syncs through.

## ⚖️ Conflicts

`zen_ui_store` gives the person the screens to settle them — `ZenConflictBanner` and what it
opens — so an app normally only places the banner. Underneath, it is this:

```dart
for (final conflict in accounts.conflicts().dataOrNull!) {
  // conflict.sides: each device's version, latest first — deviceName, at, value (null = deleted)
  final choice = await askThePerson(conflict);
  await accounts.resolve(conflict.id, choice);    // null deletes; syncs to every device
}
```

Until it is resolved a record in conflict is still **shown** (each disputed field from its latest
version, so nothing vanishes from a screen), every side stays on disk on every device, and the
record **refuses `put` and `delete`** with a `ZenConflictError` — so no screen can settle it by
accident by saving over it.

## ⚠️ What it does not do

- **Rules across records are the application's.** A balance, a budget, a uniqueness constraint:
  there is no server to enforce them, and per-field merging cannot see them. Two devices can each
  make a valid edit whose combination breaks one; check after a sync.
- **A field is the unit.** A repeated or nested field merges as a whole: two devices adding
  different items to one list is a conflict on that field, not a combined list.
- **Tombstones are kept.** Purging one safely needs every device to have seen it.
- **Lost keys mean lost data.** If the user loses every device and their iCloud Keychain, nobody
  can read the data — the other face of nobody else being able to.

## 🛟 When a file is damaged

`ZenStore.open` refuses to open over a file it cannot decrypt — the wrong key, damage, tampering —
and writes nothing, so the user's data is never replaced by an empty store. `ZenStore.erase` is the
deliberate way back, on the person's say: what was synced returns from the other devices, what was
not is gone. An incoming record that cannot be read, including one from a newer version of the
app, is skipped and named in `ZenSyncReport.problems`; the others still merge.

## 🧪 Test

```sh
cd client/zen_store && dart test
```
