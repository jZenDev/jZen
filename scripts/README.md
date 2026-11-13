# scripts/

[![jZen](https://img.shields.io/badge/jZen-monorepo-blue.svg)](https://github.com/jZenDev/jZen)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](../LICENSE)

**One command boots the whole local stack — backend, frontend, and a clean Supabase — no manual dance.**

One-shot helpers for the local dev loop. They wrap the Taskfile targets and add the two things
`task` cannot do alone: run the backend together with a frontend, and dodge a leftover Supabase
stack from another project that shadows the local ports (notably `54321`/`54322`). Shared logic for
the sh side (colors, Supabase bring-up, backend start, health wait, port freeing) lives in `lib.sh`,
which the runners source.

## 🧰 Two languages, and which one a script is

This directory holds **sh and Python, and neither is the default**. The full rule is
[`STANDARDS.md`](../docs/architecture/STANDARDS.md) "Scripting" with the reasoning in
[`DECISIONS.md`](../docs/architecture/DECISIONS.md) ADR-032, but it is short enough to state here —
four ordered tests, first match wins:

| # | Test | Language |
|---|---|---|
| 0 | Must it run *before* the toolchain is verified? | **sh** |
| 1 | Does it start, background, signal, wait on, or kill a process — or export environment into its caller? | **sh** |
| 2 | Does it only run commands and branch on exit codes or scalars a tool hands it? | **sh** |
| 3 | Must it understand *content* — parse structure out of text, or construct structure safely into it? | **Python** |

**sh runs things; Python understands things.** That is why the three runners below (`admin.sh`,
`demo.sh`, `stop.sh`) are sh — Rule 1, and structurally so: `lib.sh`'s `ensure_supabase` exports
into *its caller* and `start_backend` relies on `java` inheriting that, which a Python child
process cannot do for its parent. And it is why `pick-device.py` is Python: parsing
`flutter devices --machine` JSON is Rule 3.

`seed-admin.py` is the case that shows the line is about the *job*, not the directory. It sits
among the runners and reads like one, but it supervises nothing — it builds a JSON body and a SQL
statement, which is Rule 3.

Python here is **floored at 3.9, not pinned** (`task doctor` checks it), and **stdlib only** — no
`pip`, no virtualenv, no `requirements.txt`. The floor is what keeps these scripts working on a Mac
carrying nothing but Xcode's Command Line Tools. One script is the exception: `verify-modules.py`
needs 3.11 (ADR-069) because it parses contributed `pom.xml` files, and it refuses to run, rather
than pass, on anything older.

Shared helpers follow the same split: `lib.sh` is sourced by the runners, `lib.py` is imported by
the Python scripts, and the two mirror each other's vocabulary (`info`, `warn`, `die`, `ok`,
`fail`) so both halves of the directory read as one thing. A file that is *imported* keeps an
underscore (`lib.py`); a file that is *executed* keeps a hyphen (`pick-device.py`,
`verify-boundaries.py`).

## 🖥️ admin.sh — the admin panel stack

```
scripts/admin.sh [--no-build] [--port N]
```

Supabase + backend (on `--port`, default `$ZEN_APP_PORT` or `8085`) + the react-admin panel dev
server on `http://localhost:5173` (Vite proxies `/api` to the backend). Runs the admin server in the
foreground; `Ctrl-C` stops it and the backend it started. Backend log: `scripts/.dev-backend.log`.

## 🎬 demo.sh — the ZenDemo reference app stack

```
scripts/demo.sh [--no-build] [--port N] [--web-port N]
```

Supabase + backend + the `zen_demo` Flutter client in Chrome on `http://localhost:5200`
(`--web-port`). The script form of `task run:demo`, with the same robust Supabase handling as
`admin.sh`.

## 🔁 run-dev.sh — the `run:dev` orchestration

Not a runner you invoke directly — the `run:dev` task (in `Taskfile.app.yml`, which an app
includes as `zen:run:dev`) `exec`s it after computing every path, port and `--dart-define`. It
exists as a real bash script for Rule 1: `task`'s own shell (`mvdan/sh`) rejects `trap … INT`
and `set -m`, so an inline task body can only tear down from an `EXIT` trap that fires *after*
`flutter run` returns — i.e. after a second Ctrl-C. Here `set -m` is toggled on only around each
`&` so the backgrounded server and client each get their own process group (a terminal Ctrl-C is
not delivered straight to them) while job control stays off for the rest of the script — left on,
the forked `sleep`/`curl` in the poll loops would each grab the terminal for their turn and eat
the Ctrl-C. The script keeps the terminal, so `trap … INT TERM EXIT` drives an ordered teardown
(client from its `--pid-file`, then the server by port) on the **first** signal.
Supabase is deliberately left up; the teardown message says so. Both backgrounded children run
with stdin closed (`< /dev/null`) — under `set -m` a background-group read of the controlling
terminal raises `SIGTTIN` and stops the group, so Quarkus dev mode's aesh console (and Flutter's
key handler) must not touch the TTY here.

## 🌱 seed-admin.py — create an admin login

```
scripts/seed-admin.py --password P [--email E] [--port N]
```

Registers a user against the running backend, then flips its `users.role` to `admin` (roles live in
the table, loaded by `RoleAugmentor`, never the JWT). The default email is `admin@jzen.local`;
choose a password with `--password`. Log in with those credentials at `http://localhost:5173`.
If the account already exists, the script promotes it without changing its existing password.

Both payloads are built by things that understand the format — `json.dumps` for the body, psql's
`:'email'` interpolation for the statement — so an address with an apostrophe or a password with a
quote is data, not syntax. The sh version assembled both by string interpolation and broke on
either. Note the statement arrives on **stdin**, not via `psql -c`: `-c` skips psql's own lexer, so
`:'email'` would never expand and the server would reject it outright.

## 🛑 stop.sh — stop the stack

```
scripts/stop.sh [--supabase] [--port N]
```

Frees the backend port (`--port`, default `8085`), the Quarkus default `8080`, the admin `5173`, and
the demo `5200`. Pass `--supabase` to also `supabase stop`.

## 🔌 Supabase port shadowing

`admin.sh`/`demo.sh` (via `lib.sh`'s `ensure_supabase`) stop any *other* project's Supabase stack
(non-jZen `supabase_*` containers) that would shadow the local ports, and recover a half-exited jZen
stack (CLI reports "running" but the db container has exited) with a `stop` before `start`.

## 🔁 Typical flow

```
scripts/admin.sh            # terminal 1: Supabase + backend + admin panel
scripts/seed-admin.py --password YOUR_LOCAL_PASSWORD  # terminal 2: create the admin login
# ... open http://localhost:5173, log in ...
scripts/stop.sh --supabase  # tear everything down

scripts/demo.sh             # or: the ZenDemo reference app (Flutter) instead of the admin panel
```

## 🛡️ verify-boundaries.py — the client/server boundary gate

Run by `task verify:boundaries`, which is the first thing `task test` and CI do. What it enforces
and why is the task's own summary (`task verify:boundaries --summary`); the script's docstring
covers how.

Three checks, each spanning both client languages — Dart under `client/*/lib` and `apps/*/*/lib`,
TypeScript under `admin/src` and `apps/*/*_admin/src`, because the admin panel is a client too. No
package depends on an identity-provider SDK, no source names a provider host or credential, and no
source hard-codes an absolute URL except the two compile-time bases (`zen_identity_config.dart`,
and `config.ts` under a panel).

**A scope that matches nothing fails.** The sh version ended each scan with `2>/dev/null … ||
true`, so renaming a directory under `client/` — or moving the panel out of `admin/src` — left a
scan empty, which reads as a clean repository and reported green forever. `task test:scripts`
covers that on both sides, plus each check and each exemption, with planted violations.

## 📄 verify-docs.py — the documentation drift gate

Run by `task verify:docs`, in CI beside the contract-drift gate. Two checks: every `task <name>` a
README names must exist in `task --list`, and every module `LICENSE` must be byte-identical to the
root one.

**Nothing passes vacuously.** An unreadable task list was already an error; the two `git ls-files`
scans now are too. Previously each fed a loop that simply did not run when the pattern matched
nothing, and then printed its success line — "All README task references resolve" is a true
statement about zero READMEs, and "All 0 module LICENSE copies are byte-identical" is a gate that
has stopped looking.

## 🧩 verify-widget-files.py — the one-widget-per-file gate

Run by `task verify:widget-files` (also part of `task test`, CI, and the first step of the
application-facing `zen:test:client`, so an application including `Taskfile.app.yml` inherits it).
It scans `lib/` of every Dart package under the paths it is given — skipping `generated/` — and
exits non-zero when a file defines more than one Flutter widget. The rule, and why a `StatefulWidget`
and its private `State` count as one, is STANDARDS "One widget per file".

```
scripts/verify-widget-files.py [--suppressions FILE] PATH...
```

Each `PATH` is a Dart package or a directory holding packages. It prints the file, the line and the
widgets found, with a widget's `State` beside it.

**It fails when it cannot look.** A path that does not exist, a path with no package under it, a file
that cannot be read, a scan that found no Dart file at all, and a suppression that matches nothing
each exit 1 with the reason — "we did not look" and "we looked and it was clean" must not share an
exit code.

**Suppressions** are one file of `<path>  <reason>` lines, and a line with no reason is a parse
error. `scripts/widget-files-suppressions.txt` is jZen's own and is empty. An application sets
`WIDGET_FILES_SUPPRESSIONS` on its `includes:` entry to name its own. An exemption must say what the
file carries that splitting would lose; an entry whose file stops holding two widgets fails the gate.

## 🗄️ verify-migrations.py — the applied-migrations-are-append-only gate

Run by `task verify:migrations` (also part of `task test` and CI). It lists every versioned
`V<n>__*.sql` under a `db/migration` directory on the base ref (`--base`, default `origin/main`) and
exits non-zero when the working-tree copy differs byte for byte, or is gone. New migrations pass;
`R__*` repeatable ones are exempt, and restoring text the file had earlier in the base history passes (it undoes a bad edit). Flyway checksums the text of an applied migration, comments
included, so an edit that changes no schema still stops every consumer database that applied it
(ADR-071). A base ref that does not resolve, or that holds no versioned migration, exits 1.

## 🔍 audit-maven.py — the Java dependency CVE gate

Run by `task audit:server` (and `task audit`, which adds `pnpm audit` for both TypeScript
packages). It reads `mvn dependency:list` output, queries [OSV](https://osv.dev) — no API key, no
local database — and exits non-zero on a finding.

**Maven resolves; this understands the result.** That split is not stylistic. The obvious answers
were Maven plugins and both were measured and rejected, because both **report success after
checking nothing** (`DECISIONS.md` ADR-034): `ossindex-maven-plugin` returns `BUILD SUCCESS` after
OSS Index answers its now-anonymous request with `401`, and `osv-scanner` pointed at `pom.xml`
exits `0` after failing to resolve the `zen:*` SNAPSHOT modules. `dependency-check-maven` fails
properly and needs an NVD API key, which is a credential this repository cannot hold.

**It fails when it cannot answer**, which is the property all of the above lack: a network error,
an HTTP error, a malformed response, a result count that does not match the query, an unreadable
suppression, or an *empty dependency list* each exit 1 with the reason. "We did not look" and "we
looked and it was clean" must not share an exit code.

Suppressions live in `audit-suppressions.txt` as `<ADVISORY-ID>  <why this is accepted>`, and a
line without the second half is a **parse error**. A suppression list rots because adding to it is
cheaper than justifying an entry; requiring the sentence makes the two cost the same. The file is
empty, which is the correct state.

Test scope is excluded by default (`--include-test-scope` asks the other question): a vulnerable
test library is a real finding about a developer's machine, but it is not shipped, and one verdict
cannot honestly mean both things.

## 🧹 deploy-cleanup.py — bound what a deploy leaves behind

```
task zen:deploy:cleanup            # also run last by deploy:cloudrun
CLEANUP_DRY_RUN=1 task zen:deploy:cleanup
task zen:deploy:pin PIN_IMAGE=<registry>/<svc>:<tag>               # protect an image before using it
task zen:deploy:pin PIN_IMAGE=<registry>/<svc>:<tag> PIN_HOLD=name # a consumer the cleanup cannot see
```

Deletes superseded Cloud Run revisions, then **deletes old Artifact Registry versions itself** (keep
the newest N per package and every pinned or held one; delete older tagged and untagged ones), and
prunes local Docker images and build cache, in that order. Python by Rule 3: it parses `gcloud` and
`docker` JSON. No registry cleanup policy is armed: Google's asynchronous evaluator never ran on the
`jzen` repository, and a plan carried out in the run is deterministic, testable, and prints its own
before/after listing (ADR-074, which supersedes the registry-policy half of ADR-064 and the policy
mechanics of ADR-068). The operator contract, every knob and the failure semantics are in `task
zen:deploy:cleanup --summary`. Tests run against stub `gcloud` and `docker` that keep state, under
`task test:scripts`.

**A run, in order.** List versions (before) → pins added and released → read EVERY version's manifest
(`docker buildx imagetools inspect --raw`) → plan → hazard check → remove jZen's own old cleanup
policies → delete one version per call, parents before children → list again (after). Anything that
makes the plan unprovable deletes **nothing** in the run: an unreadable manifest, a digest a
revision or job needs in the plan, a consumer whose image is already gone, an unreadable consumer
list, a failed pin, a cleanup policy that is not jZen's. A failed deletion is reported per version,
its children are skipped, the rest proceed, and the step exits non-zero ("the deploy itself
succeeded"; `CLEANUP_ON_FAILURE=warn` exits 0).

**What keeps an image that something still runs.** A count of newest versions and an age do not:
a quiet service ages out of its own window. So each digest a revision or Cloud Run job needs gets a
`zen-pin-<digest>` tag and the plan never selects a version carrying it. Consumers are every revision
and job in the project and region that names this repository; pins are added before anything is
selected and released only when no consumer needs the digest. A deploy pins its image right after
the push, before anything is pointed at it. A consumer the script cannot see is protected by a hold
(`PIN_HOLD`), which it never removes.

**Attachments leave only with their target.** A version whose manifest has a `subject` (cosign v3
signatures and SBOM attestations, an OCI referrer) is never selected; the registry deletes it with
its target. A version tagged `sha256-<hex>.sig|.att|.sbom` (cosign before v3) is deleted after
`sha256:<hex>` in the same run, never alone. A kept image therefore keeps its signature.

**Transition.** If every cleanup policy on the repository has an id starting `zen-`, the run removes
them before deleting any version. Any other id is reported and nothing is deleted; remove it or set
`CLEANUP_REGISTRY=off`.

**Operator requirements.** Point a service or job at an image by hand only after
`task zen:deploy:pin`; add a hold for any puller outside this project and region; never run the
cleanup concurrently with a deploy; do not delete `zen-pin-*` or `zen-hold-*` tags by hand while a
consumer exists; run the cleanup after a manual traffic change (it re-reads the consumers).

### Validating on the real repository (#177, #173)

What the stubs cannot show, and what ADR-074 does not claim until it is run: that `images delete
--delete-tags` removes an image index without its children (or refuses, or cascades), that deleting
a target removes its sigstore and attestation attachments, and a real before/after. The owner runs
it, since it changes cloud resources (`jzen-prod` / `europe-central2` / repo `jzen` / service
`zen-demo-server`).

```sh
# 0. Environment for every task call below.
export GCP_PROJECT=jzen-prod GCP_REGION=europe-central2 AR_REPO=jzen SERVICE_NAME=zen-demo-server
R=europe-central2-docker.pkg.dev/jzen-prod/jzen

# 1. Evidence before. Keep these files for the issue.
gcloud artifacts docker images list $R --include-tags --format=json > /tmp/images.before.json
gcloud run revisions list --project=jzen-prod --region=europe-central2 --format=json > /tmp/rev.before.json
gcloud run jobs list --project=jzen-prod --region=europe-central2 --format=json > /tmp/jobs.before.json
gcloud artifacts repositories describe jzen --project=jzen-prod --location=europe-central2 --format=json > /tmp/repo.before.json

# 2. Dry run: prints the plan, the pins and releases, and any policy removal. Changes nothing.
#    Read it: no digest a revision or job runs may appear under "would delete".
CLEANUP_DRY_RUN=1 task zen:deploy:cleanup

# 3. The real run: pins, removes the zen- cleanup policies, deletes, lists again.
task zen:deploy:cleanup

# 4. Evidence after, then check it.
gcloud artifacts docker images list $R --include-tags --format=json > /tmp/images.after.json
gcloud run revisions list --project=jzen-prod --region=europe-central2 --format=json > /tmp/rev.after.json
gcloud artifacts repositories describe jzen --project=jzen-prod --location=europe-central2 \
  --format='value(cleanupPolicies)'                       # must print nothing

# 5. A rerun must delete nothing more.
task zen:deploy:cleanup

# 6. Only once 2-5 are as expected: delete the throwaway repositories (whole repositories,
#    so no empty shell is left behind). Check what you are deleting first.
gcloud artifacts repositories list --project=jzen-prod --location=europe-central2
gcloud artifacts repositories delete zen-cleanup-probe --project=jzen-prod --location=europe-central2
gcloud artifacts repositories delete zen-cleanup-copy  --project=jzen-prod --location=europe-central2
```

Check: every `status.imageDigest` in `rev.after.json` and the digest each job resolves to is in
`images.after.json` with a `zen-pin-` tag; the migrate job's image is present; the signature or
attestation of every kept image is still listed (`cosign verify` of the serving image still
passes); the versions missing are only old, unreferenced ones. Paste the run's own before/after
listings and these files into #177 and #173 before closing them.

If a deletion fails on a version that has children, or an attachment is left behind, that is the
finding: stop, keep the output, and amend ADR-074 rather than working around it.

## 📱 pick-device.py — which device a native run targets

Used by `task run:demo:native`. Prints `<device-id>\t<platform>` on stdout and everything a human
reads on stderr, so the task can capture the answer without the conversation.

`ZEN_TARGET` (an id **or** a name) wins when set; an explicit desktop target bypasses discovery.
Otherwise Flutter lists only built-in and USB-attached devices (`--device-connection=attached`),
with CLI analytics suppressed. Wireless device discovery is disabled. One attached device is used without asking;
several produce a numbered menu read from `/dev/tty`, which is what makes it work inside a command
substitution. A non-interactive caller with several devices is told to pass `ZEN_TARGET` rather
than left at a prompt nobody can see.

For enumerated devices the platform comes from Flutter's `targetPlatform`, never from the shape of the id — `emulator-5554`
and a simulator UUID are both just strings, and guessing there is how an Android emulator once
built with `ZEN_PLATFORM=ios` and skipped the JDK check that would have explained the failure.
