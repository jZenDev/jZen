# scripts/

One-shot helpers for the local dev loop. They wrap the Taskfile targets and add the two things
`task` cannot do alone: run the backend together with a frontend, and dodge a leftover Supabase
stack from another project that shadows the local ports (notably `54321`/`54322`). Shared logic
(colors, Supabase bring-up, backend start, health wait, port freeing) lives in `lib.sh`, which the
runners source.

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
