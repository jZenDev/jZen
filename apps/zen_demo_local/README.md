# zen_demo_local

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](zen_demo_local_client/LICENSE)

**The jZen Local reference app: a chore list with no server, no sign-in and no account — on iOS,
macOS, Android, Windows and Linux.** It is to Local mode what [`zen_demo`](../zen_demo/README.md) is
to the full stack: the showcase, and the end-to-end test stand. See ADR-073 (the mode) and
[`docs/plans/implemented/JZEN-LOCAL-PLAN.md`](../../docs/plans/implemented/JZEN-LOCAL-PLAN.md).

The model is one record, a `Chore` (`proto/zen_demo_local/v1/chore.proto`), with four independently
editable fields — title, note, done, priority — so that every behaviour of the mode is one tap away.

## What it shows

| You do | You see |
|---|---|
| Edit with no network | Everything works; the store is encrypted files on the device (`zen_store`). |
| Change the **note** on one device and the **priority** on another, offline, then sync | Both changes on both devices; nothing is asked. |
| Change the **title** on both | A banner, "needs your choice", then every version side by side; choosing one settles it everywhere. Until then the chore refuses edits. |
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
(`~/Library/Containers/dev.jzen.zenDemoLocalClient/Data/Documents/zen-cloud`) for both builds, as
`zen_store`'s README explains. The path must have no space in it (`Application Support` has one):
the defines are word-split and the task now refuses such a path.

**A macOS non-release dev build opens its data with no signing identity.** The store key (`zen_store_key`) and
the PIN hash (`zen_ui_lock`) live in the login keychain when `ZEN_ENV=dev` and the build is not `--release` (`ZEN_ENV` defaults to `dev` in the Taskfile, so a release build must not read it alone); the
data-protection Keychain gave an ad-hoc-signed app `-34018` ("a required entitlement is not
present"). Every other build, a `--release` build included, keeps the data-protection Keychain, which needs a signing identity; the free personal team provisions it for a debug build (the rows below, ADR-087). The two keychains do not see each other's items, so a Mac that
switches between a dev and a release build refuses to open the data rather than making a new key:
"Erase this device's copy" and sync again.

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

## Verification matrix

What has been run, and what has not. A simulator or an emulator is not a device: a row says exactly
what ran. Nothing below was run against a real sync service or on a real Android. The real-hardware rows are the Mac ones (macOS 27.0, Apple silicon) and the real iPhone one (iOS 27.2.1), both run later the same day with the free personal team. Run on
2026-11-17 on a Mac: the iOS Simulator (iPhone 17, iOS 26.5), a macOS debug build, and the Android
emulator `Pixel_9` (API 36, 16 KB page size, Google Play image). Evidence (screenshots, size
analysis) is kept with the #231 hand-over notes, not in the repository.

| Row | Status | Why |
|---|---|---|
| Two sessions through `ZenFolderCloud` and through the shared-folder transport on a Mac: merge, conflict, delete against edit, erase and re-sync | passed (automated, host tests) | `test/two_devices_test.dart` |
| Screens and accessibility (contrast, target size, names, 200% text) | passed (automated) | widget suites |
| macOS debug build, `ZEN_ENV=dev` (ad-hoc signed) | **passed on a real Mac (macOS 27.0), window looked at**: the window opens on the Chores screen, a chore added, and after quitting and reopening it was still there; the store key `zen_store.key` was in the login keychain. Without `ZEN_SYNC=folder` the app aborts in `CKContainer` (no iCloud entitlement), as before | ADR-080, ADR-087 |
| macOS build signed with the free personal team and **not** a dev build (`ZEN_ENV=prd`, debug mode, `ZEN_SYNC=folder`; data-protection Keychain, `keychain-access-groups` = `<team>.dev.jzen.zenDemoLocalClient`) | **passed on a real Mac (macOS 27.0), debug mode only**: signed by `Apple Development` (free personal team, not Developer ID), provisioned by Xcode with `-allowProvisioningUpdates` once an Apple ID was added in Xcode → Settings → Accounts. The window opened on an empty store (key created), a chore was added, and after a restart it was still there (key reused). **Not run: a `--release` build** (needs CloudKit, which needs the paid program). To build it the Runner project needed a `DEVELOPMENT_TEAM` and the entitlement; neither is in the tree (a temporary local edit, reverted). The window appeared only after the app was activated | ADR-087 |
| PIN on macOS (dev build): set, wrong PIN, "Forgot PIN?" | **passed on a real Mac**: PIN set, the lock screen shown after a restart, a wrong PIN refused ("Wrong PIN"), "Forgot PIN?" showed the system prompt and, once approved by the person at the Mac, opened the app with the PIN switched off. The signed build's PIN was not run | ADR-078 |
| Real iPhone (iPhone 17, iOS 27.2.1, free personal team, USB; a profile build with `ZEN_ENV=dev ZEN_SYNC=folder`): store key, chores, PIN, "Forgot PIN?", app-switcher snapshot, erase | **passed on a real iPhone, except Face ID, which was not exercised.** Observed through QuickTime Player (read-only view of the phone, since iPhone Mirroring would not open); every tap was the person's, and the app was launched and relaunched with `devicectl`. **Store key:** the app opened to the Chores screen on a first run and a chore the person added was still there after the process was terminated and relaunched (the key was created in the real Keychain and reused). **PIN:** set, shown at relaunch, a wrong PIN refused ("Wrong PIN"). **"Forgot PIN?":** showed the system prompt "Enter iPhone Passcode … Confirm it's you to reset the app's PIN"; the person entered the device passcode, no Face ID was tried (the prompt was the passcode screen), and the app then opened with the PIN off and the chore kept. **App switcher (ADR-085):** with a PIN set, the app's card was a plain dark cover with no chores. **Screen-capture hiding:** not applicable on iOS (ADR-085), the capture showed the content. **Erase:** after "Erase this device's copy" and a relaunch the person reported a PIN lock and, after unlocking, an empty chore list (user-reported; the QuickTime feed had dropped at that moment). The sync-folder banner ("Cannot use /tmp/zen-real") was expected: the dev-only folder is not writable in the iPhone sandbox, so no sync ran. The app was deleted from the phone; its Keychain items may remain, since iOS keeps them after an uninstall. Not done: Face ID, a `--release` build | ADR-085 |
| macOS ↔ iOS simulator through `ZenFolderCloud` | **passed on the iOS Simulator (iPhone 17, iOS 26.5) and a macOS debug build; no real device** | create on macOS appears on iOS; note edited on iOS and priority on macOS while the folder was gone merge to both on return; a title edited on both gives the banner and the chooser on both, and keeping one settles both; "Erase this device's copy" on iOS brings the chore back. "Offline" was the folder disappearing, not either app closed. The macOS leg ran with a local edit that is not in the tree (the data-protection keychain switched off); ADR-087 now does that for a dev build. |
| Windows ↔ Linux ↔ Android through Syncthing: pairing, merge, conflict, offline then reconnect, grant revoked | **not verified** | needs the three devices; the Android half now has an emulator pass (next rows) |
| The same through Dropbox or OneDrive | **not verified** | needs an account and the devices |
| iOS / macOS through real CloudKit | **not verified** | needs a paid Apple Developer Program membership; this is a free personal team |
| Android folder access (Storage Access Framework, grant surviving a restart) | **passed on the Android emulator (Pixel_9, API 36); no real device, no real sync app** | the system picker opened, a `content://` tree was granted, encrypted `.zen` files were written into it through the grant, and after `force-stop` and a restart a new chore was written through the same grant with no re-pick. Not tried against Syncthing-Fork, Dropbox or OneDrive's own provider. |
| Store key off Apple (spike 0.4) on Android | **passed on the Android emulator (Pixel_9); no real device** | the app made and read its key through `flutter_secure_storage` (Keystore-wrapped prefs present, data survives restarts). Windows, Linux and a Linux desktop with no secret service: **not verified** |
| PIN, "Forgot PIN?" and biometrics on Android | **passed on the Android emulator (Pixel_9) with an emulated fingerprint; no real device** | wrong PIN refused, right PIN opens, "Forgot PIN?" shows the system prompt and the emulated fingerprint resets the PIN. It failed before this run (below). Windows, Linux: **not verified** |
| Camera QR scanning when joining | **not verified** | no scanner plugin is wired; the typed 77-character code works everywhere, `ZenQrScannerBuilder` is the optional hook (`zen_ui_store`) |
| Windows and Linux runs; the `inactive` lifecycle and Android recents snapshot | **not verified** | not run on hardware; only built in CI (ADR-078, ADR-081) |
| Transports absent from a built Android binary (ADR-079) | **passed for an Android release arm64 build** (`--analyze-size` and the strings of `libapp.so`): no CloudKit, no `ZenFolderCloud`; `ZenSharedFolderSync` and the SAF adapter present. Windows, Linux: **not verified** | built here, inspected as files; no device needed |

Found and fixed by this run, none of which any host test could see:

- **Android "Start syncing" threw `Empty key`.** HKDF's salt was empty, and the native Android HMAC
  refuses an empty key (the host tests use the pure-Dart one). The salt is now 32 zero bytes, which
  RFC 5869 defines as no salt, so every derived key is unchanged (pinned by a test).
- **Android "Forgot PIN?" failed at once, with no prompt**: `MainActivity` was a `FlutterActivity`,
  and `local_auth` needs a `FragmentActivity` (also `USE_BIOMETRIC` and an AppCompat launch theme).
- **On iOS and macOS the back arrow and every Cupertino glyph drew as a "?" box**: `zen_ui_widgets`
  uses `CupertinoIcons` without depending on `cupertino_icons`, so the font was not bundled.
- **`ZEN_SYNC_FOLDER` with a space** (the path this README gave for macOS) broke `run:client`.

Open: a signed `--release` macOS build, and both devices naming themselves after the host
(`MBP14.local`) on the conflict cards when a simulator and a Mac share one host.

On Windows "Forgot PIN?" offers to erase this device's copy rather than Windows Hello (ADR-081), as
on Linux (ADR-078).
