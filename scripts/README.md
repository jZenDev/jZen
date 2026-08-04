# scripts/

One-shot helpers for the local dev loop. They wrap the Taskfile targets and add the two things
`task` cannot do alone: run the backend together with a frontend, and dodge a leftover Supabase
stack from another project that shadows the local ports (notably `54321`/`54322`). Shared logic for
the sh side (colors, Supabase bring-up, backend start, health wait, port freeing) lives in `lib.sh`,
which the runners source.

## Two languages, and which one a script is

This directory holds **sh and Python, and neither is the default**. The full rule is
[`STANDARDS.md`](../docs/architecture/STANDARDS.md) "Scripting" with the reasoning in
[`DECISIONS.md`](../docs/architecture/DECISIONS.md) ADR-029, but it is short enough to state here —
four ordered tests, first match wins:

| # | Test | Language |
|---|---|---|
| 0 | Must it run *before* the toolchain is verified? | **sh** |
| 1 | Does it start, background, signal, wait on, or kill a process — or export environment into its caller? | **sh** |
| 2 | Does it only run commands and branch on exit codes or scalars a tool hands it? | **sh** |
| 3 | Must it understand *content* — parse structure out of text, or construct structure safely into it? | **Python** |

**sh runs things; Python understands things.** That is why the four runners below are sh — Rule 1,
and structurally so: `lib.sh`'s `ensure_supabase` exports into *its caller* and `start_backend`
relies on `java` inheriting that, which a Python child process cannot do for its parent. And it is
why `pick-device.py` is Python: parsing `flutter devices --machine` JSON is Rule 3.

Python here is **floored at 3.9, not pinned** (`task doctor` checks it), and **stdlib only** — no
`pip`, no virtualenv, no `requirements.txt`. The floor is what keeps these scripts working on a Mac
carrying nothing but Xcode's Command Line Tools.

Shared helpers follow the same split: `lib.sh` is sourced by the runners, `lib.py` is imported by
the Python scripts, and the two mirror each other's vocabulary (`info`, `warn`, `die`, `ok`,
`fail`) so both halves of the directory read as one thing. A file that is *imported* keeps an
underscore (`lib.py`); a file that is *executed* keeps a hyphen (`pick-device.py`,
`verify-boundaries.py`).

## admin.sh — the admin panel stack

```
scripts/admin.sh [--no-build] [--port N]
```

Supabase + backend (on `--port`, default `$ZEN_APP_PORT` or `8085`) + the react-admin panel dev
server on `http://localhost:5173` (Vite proxies `/api` to the backend). Runs the admin server in the
foreground; `Ctrl-C` stops it and the backend it started. Backend log: `scripts/.dev-backend.log`.

## demo.sh — the ZenDemo reference app stack

```
scripts/demo.sh [--no-build] [--port N] [--web-port N]
```

Supabase + backend + the `zen_demo` Flutter client in Chrome on `http://localhost:5200`
(`--web-port`). The script form of `task run:demo`, with the same robust Supabase handling as
`admin.sh`.

## seed-admin.sh — create an admin login

```
scripts/seed-admin.sh [--email E] [--password P] [--port N]
```

Registers a user against the running backend, then flips its `users.role` to `admin` (roles live in
the table, loaded by `RoleAugmentor`, never the JWT). Defaults: `admin@jzen.local` / `password123`.
Log in with the printed credentials at `http://localhost:5173`.

## stop.sh — stop the stack

```
scripts/stop.sh [--supabase] [--port N]
```

Frees the backend port (`--port`, default `8085`), the Quarkus default `8080`, the admin `5173`, and
the demo `5200`. Pass `--supabase` to also `supabase stop`.

## Supabase port shadowing

`admin.sh`/`demo.sh` (via `lib.sh`'s `ensure_supabase`) stop any *other* project's Supabase stack
(non-jZen `supabase_*` containers) that would shadow the local ports, and recover a half-exited jZen
stack (CLI reports "running" but the db container has exited) with a `stop` before `start`.

## Typical flow

```
scripts/admin.sh            # terminal 1: Supabase + backend + admin panel
scripts/seed-admin.sh       # terminal 2: one-time, create the admin login
# ... open http://localhost:5173, log in ...
scripts/stop.sh --supabase  # tear everything down

scripts/demo.sh             # or: the ZenDemo reference app (Flutter) instead of the admin panel
```

## verify-boundaries.py — the client/server boundary gate

Run by `task verify:boundaries`, which is the first thing `task test` and CI do. What it enforces
and why is the task's own summary (`task verify:boundaries --summary`); the script's docstring
covers how.

Three checks over `client/*/lib` and `apps/*/*/lib`: no client package depends on an
identity-provider SDK, no client source names a provider host or credential, and no client source
hard-codes an absolute URL except the one compile-time base in `zen_identity_config.dart`.

**A scope that matches nothing fails.** The sh version ended each scan with `2>/dev/null … ||
true`, so renaming a directory under `client/` left every scan empty — which reads as a clean
repository, and reported green forever. `task test:scripts` covers this and each of the three
checks with planted violations.

## pick-device.py — which device a native run targets

Used by `task run:demo:native`. Prints `<device-id>\t<platform>` on stdout and everything a human
reads on stderr, so the task can capture the answer without the conversation.

`ZEN_TARGET` (an id **or** a name) wins when set; one attached device is used without asking;
several produce a numbered menu read from `/dev/tty`, which is what makes it work inside a command
substitution. A non-interactive caller with several devices is told to pass `ZEN_TARGET` rather
than left at a prompt nobody can see.

The platform comes from Flutter's `targetPlatform`, never from the shape of the id — `emulator-5554`
and a simulator UUID are both just strings, and guessing there is how an Android emulator once
built with `ZEN_PLATFORM=ios` and skipped the JDK check that would have explained the failure.
