# Plan: jZen Local on every native target, shown by `zen_demo_local`

**Source:** ADR-073 (2026-11-06) — a serverless jZen application is a *Local* application, and its
sync transport follows `ZEN_PLATFORM`: CloudKit on iOS and macOS, a folder the person chooses on
Android, Windows and Linux, no web build. ADR-065 built the core (`zen_store`, `zen_store_cloudkit`,
`zen_ui_store`, `zen_ui_lock`); ADR-072 taught `Taskfile.app.yml` to run an application with no
server.

**Scope:** jZen only. The proof is a new reference application, `apps/zen_demo_local`, a client
with no server that builds and runs on **iOS, macOS, Android, Windows and Linux** — the Local
counterpart of `zen_demo`, and the end-to-end test stand for the mode the way `zen_demo` is for the
full stack. Prudent Local is out of scope here; it starts from what this plan leaves on `main`.

Each unit below is one branch and one PR (`<type>/<slug>`), landed in order unless it says
otherwise. A unit is done when its tests are green, `task verify:boundaries`, `verify:docs` and
`verify:widget-files` pass, and what it could not verify is written down in its PR and in
ROADMAP item 9.

## Ground rules

- **Nothing is lost without the person's say** (ADR-065). No unit may add a last-writer-wins path,
  including inside the new transport when a sync service delivers files late, twice or as
  "conflicted copies".
- **Client config is compile-time.** The transport, and everything platform-specific, is chosen
  from `ZEN_PLATFORM` / `ZEN_SYNC` with `String.fromEnvironment` and conditional imports, so a
  build carries only its own platform's code.
- **Encrypted everywhere the framework writes**: on the device (as today) and in the shared folder.
  The folder's sync service sees ciphertext only.
- **Framework first.** A gap the demo hits is fixed in `client/` with its own suite, then used —
  the demo never works around the framework.
- **Decisions get ADRs** (`add-adr` skill) as they are made; ADR-073 is not edited.

---

## Phase 0 — Spikes (answers before code; each ends in a note in the PR that closes it)

### 0.1 Android folder access
- **Question:** a folder chosen through the Storage Access Framework is a `content://` tree URI,
  which `dart:io` cannot open. Which way does `zen_store_shared_folder` read and write it — an
  existing, maintained pub.dev plugin, or a small Kotlin part of its own?
- **Done when:** a throwaway Android build lists, reads, writes and renames a file inside a
  SAF-chosen folder synced by a real sync app (Syncthing or Dropbox), and the grant survives a
  restart. The choice and its reason go into the unit 2 ADR.

### 0.2 Pairing on devices without a camera
- **Question:** which code carries the sync key from one device to another — a QR code where a
  camera exists (Android, iOS), and a typed code everywhere (Windows and Linux desktops usually
  have no scanner)? Its length, alphabet and check digit; whether it is a one-time code that
  wraps the key (and so needs both devices at once) or the key itself.
- **Done when:** the format is written down with its threat model (someone photographing the
  screen) and the scanner plugin, if any, is chosen.

### 0.3 "Forgot PIN?" without `local_auth`
- **Question:** `local_auth` has no Linux implementation. What does `zen_ui_lock` offer there —
  hide recovery, or recover by erasing this device's copy and re-syncing it from the others?
- **Done when:** the answer is decided and `zen_ui_lock`'s suite names the Linux path.

### 0.4 Key storage off Apple
- **Question:** does `flutter_secure_storage` 10.x give the store key the same "this device only"
  guarantee on Android (Keystore), Windows and Linux (libsecret) that the Keychain gives? What
  happens on a Linux desktop with no secret service running?
- **Done when:** each platform's behaviour is written down, including the failure, which must stop
  the open loudly rather than mint a new key over existing files.

---

## Phase 1 — Framework

### Unit 1 — The store key on every platform
- **Branch:** `feature/zen-store-key-all-platforms`
- **What:** `ZenKeychainStoreKey` lives in `zen_store_cloudkit`, which is Apple-only. Move the key
  to a package every Local application depends on (name it in the ADR; e.g. `zen_store_key` or
  inside the unit 3 package), keeping `protectDirectory` Apple-only. iOS/macOS behaviour is
  unchanged; Android, Windows and Linux get the behaviour 0.4 established.
- **Tests:** the existing key suite, run per platform channel; a missing secret service fails the
  load with a `ZenError`, never a fresh key.
- **ADR:** yes — where the key lives now, and why.

### Unit 2 — `zen_store_shared_folder`
- **Branch:** `feature/zen-store-shared-folder`
- **What:** a `ZenSyncTransport` over a folder a sync service keeps in step:
  - one subfolder per device; a device writes only its own files and reads everyone's, so no file
    ever has two writers;
  - every file encrypted with the shared sync key, its path bound in as associated data;
  - writes as temp-file-then-rename; a half-arrived or unreadable file is skipped and retried, and
    reported in `ZenSyncReport.problems`, never fatal and never merged;
  - a sync service's "conflicted copy" of a file is ignored by name pattern *and* by the
    one-writer rule (it cannot be newer than its writer's own file);
  - change detection by polling, plus a file watcher where the platform has one; no network code;
  - a `ZenSyncStatus` for: no folder chosen, folder unreachable, grant revoked (Android), not
    paired, a device from a newer app version.
  - On Android, the folder access chosen in 0.1.
- **Tests (pure Dart where possible):** two and three stores through one folder; a "lazy sync
  service" fake that delays, reorders, duplicates and truncates files, and produces conflicted
  copies; a delete against an unseen edit; a device removed and re-paired; payloads are never
  plaintext on disk.
- **ADR:** yes — layout, encryption, what the folder exposes (device count, sizes, timing).

### Unit 3 — Pairing
- **Branch:** `feature/zen-local-pairing`
- **What:** the 0.2 format in a framework package, plus screens in `zen_ui_store`: "Add a device"
  (show the code, as QR where useful and as text always) and "Join" (scan or type), with a
  cancel and an expiry. The sync key never appears in logs, URLs or the clipboard.
- **Tests:** round trip, wrong code, expired code, typo caught by the check digit; widget
  accessibility suite as for every `zen_ui_*` screen; en + uk strings.

### Unit 4 — Choosing the transport from the platform
- **Branch:** `feature/zen-local-sync-select`
- **What:** one call an application makes to start sync — CloudKit for `ios`/`macos`, the shared
  folder for `android`/`windows`/`linux`, `ZenFolderCloud` when `ZEN_SYNC=folder` — resolved from
  constants so the tree-shaker drops the others. The application no longer reads `ZEN_SYNC`
  itself. Update the `zen_store_cloudkit` and `zen_store` READMEs' "Use" snippets.
- **Tests:** a table test over every `ZEN_PLATFORM` × `ZEN_SYNC` combination, including the
  refused ones.

### Unit 5 — `zen_ui_lock` everywhere
- **Branch:** `feature/zen-ui-lock-all-platforms`
- **What:** the 0.3 decision; the privacy cover and lifecycle lock checked on Android, Windows and
  Linux, not only Apple.
- **Tests:** existing suite on every host; the Linux recovery path.

### Unit 6 — Taskfile and CI
- **Branch:** `orchestration/zen-local-targets`
- **What:** `Taskfile.app.yml` refuses `ZEN_PLATFORM=web` (and `build:web`) for an application
  with no server, with a message naming ADR-073; `build:runners` builds a Local application for
  every native target its host can build. CI's existing `android-runner` (Android + Linux),
  `windows-runner` and `macos-runner` (macOS + iOS simulator) jobs build `zen_demo_local` too.
- **Tests:** the stub-`flutter` check ADR-072 used, extended to the web refusal and the five
  targets.

---

## Phase 2 — `zen_demo_local`

### Unit 7 — The application
- **Branch:** `feature/zen-demo-local`
- **What:** `apps/zen_demo_local/zen_demo_local_client` (no `_server`, no `_admin`), a member of
  the `apps/` workspace, with `ios`, `macos`, `android`, `windows`, `linux` runners and no `web`.
  Its model is a `.proto` under `proto/zen/v1/` (generated Dart committed, `verify:contracts`
  green). Small on purpose — a list of records with several independently editable fields — so
  that every behaviour of the mode is one tap away:
  - edit offline; edits on two devices to different fields merge, the same field conflicts;
  - `ZenConflictBanner` → the conflict screens → choose a side; a delete against an edit;
  - `ZenSyncStatusBanner` for every status the platform's transport can report;
  - settings: PIN on/off (`zen_ui_lock`), sync folder (shared-folder platforms), add / join a
    device (pairing), erase this device's copy;
  - built only from `zen_ui_*` controls, one widget per file, en + uk.
- **Tests:** widget suites; an integration test running two app stores through
  `ZenFolderCloud` and through the shared-folder transport on the host; the accessibility suite.
- **Docs:** `apps/zen_demo_local/README.md` (what it shows, how to run two devices on one Mac or
  PC), root README "jZen Local" section and `apps/` description point at it.

### Unit 8 — Manual verification matrix
- **Branch:** `docs/zen-demo-local-verification`
- **What:** run the demo on real targets and record the result per row in the demo README and
  ROADMAP item 9:
  - Windows ↔ Linux ↔ Android through Syncthing, and through one commercial service (Dropbox or
    OneDrive): pairing, merge, conflict, offline then reconnect, grant revoked;
  - macOS ↔ iOS simulator through `ZenFolderCloud` (ADR-072's open item);
  - iOS / macOS through real CloudKit — **expected to stay open** until the paid Apple Developer
    Program membership exists; say so rather than mark it done.
- **Done when:** every row is either passed with the date and devices, or marked not verified
  with the reason.

---

## Phase 3 — Close

### Unit 9 — Documents
- **Branch:** `docs/jzen-local-done`
- **What:** BLUEPRINT "Local applications", README, ARCHITECTURE, CLAUDE.md/AGENTS.md and
  ROADMAP item 9 describe what was built (not planned); every "planned" in ADR-073's wake is
  either gone or still true; package CHANGELOGs.

### Unit 10 — Move this plan to `docs/plans/implemented/`
- **Branch:** the unit 9 branch or its own `docs/` branch.
- **What:** `git mv docs/plans/JZEN-LOCAL-PLAN.md docs/plans/implemented/`, with each unit above
  marked ✅ and its PR linked, and anything left open stated at the top.
