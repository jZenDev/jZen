# zen_demo_local

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](zen_demo_local_client/LICENSE)

**The jZen Local reference app: a chore list with no server, no sign-in and no account — on iOS,
macOS, Android, Windows and Linux.** It is to Local mode what [`zen_demo`](../zen_demo/README.md) is
to the full stack: the showcase, and the end-to-end test stand. See ADR-073 (the mode) and
`docs/plans/JZEN-LOCAL-PLAN.md`.

The model is one record, a `Chore` (`proto/zen_demo_local/v1/chore.proto`), with four independently
editable fields — title, note, done, priority — so that every behaviour of the mode is one tap away.

## What it shows

| You do | You see |
|---|---|
| Edit with no network | Everything works; the store is encrypted files on the device (`zen_store`). |
| Change the **note** on one device and the **priority** on another, offline, then sync | Both changes on both devices; nothing is asked. |
| Change the **title** on both | A banner, "needs your choice", then each device's version side by side; choosing one settles it everywhere. Until then the chore refuses edits. |
| Delete a chore on one device and edit it on another | The same banner; one card says "Deleted on this device", the other shows what deleting would throw away. |
| Stop sync (no folder chosen, a sync key missing, a folder gone, iCloud signed out) | `ZenSyncStatusBanner` says why, in words you can act on. |
| Settings → Security | A PIN (`zen_ui_lock`); "Forgot PIN?" per platform. |
| Settings → Sync (Android, Windows, Linux) | Choose the folder your sync service keeps in step; make this the first device, **Add a device** (shows a 77-character code) or **Join another device** (type it). |
| Settings → Erase this device's copy | Deletes what is stored here; your other devices send it back. |

It is built only from `zen_ui_*` controls, in English and Ukrainian, with no `zen_transport` and no
`zen_identity`: there is nothing to sign in to. Sync starts only through `ZenSync.start`; the app
reads neither `ZEN_PLATFORM` nor `ZEN_SYNC`.

## Run two devices on one Mac or PC

Two builds given the same folder sync as two devices (`ZenFolderCloud`, development only).
Each build keeps its own data, so run the second one as a different user, a different simulator,
or the second form below.

```sh
FOLDER=$HOME/zen-local-demo-cloud && mkdir -p "$FOLDER"
task zenlocal:run:client DEVICE=macos ZEN_SYNC=folder ZEN_SYNC_FOLDER="$FOLDER"
task zenlocal:run:client DEVICE=<ios-simulator-udid> CLIENT_PLATFORM=ios ZEN_SYNC=folder ZEN_SYNC_FOLDER="$FOLDER"
```

A sandboxed macOS app reaches only its own container: use a folder inside it
(`~/Library/Containers/dev.jzen.zenDemoLocalClient/Data/Library/Application Support/zen-cloud`) for
both builds, as `zen_store`'s README explains.

To try the release transport — the shared folder — on a Windows, Linux or Android build, run it
with no `ZEN_SYNC`: **Settings → Sync**, choose a folder a sync service shares (Syncthing, Dropbox,
OneDrive, ...), "Start syncing from this device" on the first one, then "Add a device" there and
"Join another device" on the second. On one machine, point both at the same folder.

## Test

```sh
task test:client          # includes this app's suites
cd apps/zen_demo_local/zen_demo_local_client && flutter test --dart-define=ZEN_PLATFORM=macos
```

- `test/two_devices_test.dart` runs two real sessions, each with its own encrypted store, through
  `ZenFolderCloud` and through the shared-folder transport: merge, conflict, delete against edit,
  erase and re-sync.
- `test/chores_flow_test.dart` drives the screens; `test/accessibility_test.dart` checks contrast,
  target size, names and 200% text in light and dark.

## Not verified

Real CloudKit (needs the paid Apple Developer Program), a real Android device with a real sync app
(and a Storage Access Framework grant surviving a restart), Windows and Linux hardware, and a real
sync service (Syncthing, Dropbox, OneDrive) between them. QR scanning when joining is not wired:
the typed code works everywhere, the camera is an optional `ZenQrScannerBuilder`
(`zen_ui_store`). Spike 0.1's and unit 8's matrix record what has been run on devices.
