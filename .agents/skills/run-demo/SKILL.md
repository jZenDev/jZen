---
name: run-demo
description: Run the jZen stack locally — the Quarkus backend, the zen_demo reference app, the admin panel, or the full showcase. Use when asked to start/run/boot the app, see a change work in the real app, or reproduce something end to end. Project-specific launcher; prefer this over generic run patterns.
---

# Running jZen locally

Everything launches through `Taskfile.yml` (go-task). **Docker must be running** (Supabase +
Quarkus Dev Services Postgres both need it). Run `task doctor` first if the toolchain is unproven.

## Pick the right target

- **`task run:demo`** — the full product showcase: boots Supabase, starts the Quarkus server on
  `ZEN_APP_PORT` (default **8085**, chosen to dodge a leftover stack shadowing :8080), waits for
  `/api/v1/health`, then runs `zen_demo` in Chrome pointed at it. Ctrl-C stops the app; the server
  is torn down on exit. Use this to watch auth, both transport modes, localization, and the WebSocket
  echo work end to end.
- **`task run:server`** — just the backend in Quarkus **dev mode** (live reload) on **:8080**.
  Installs the framework libs, then runs `apps/zen_demo/zen_demo_server`. Use when working the API.
- **`task run:all`** — Supabase + `run:server` (no client). Run the admin separately.
- **`task run:admin`** — the react-admin panel dev server on **:5173**, proxying `/api` to the
  backend. Start a backend first.
- **`task run:supabase`** / **`task stop:supabase`** — the local Supabase stack alone
  (API 54321, DB 54322, Studio 54323).

## To confirm a change works (not just tests)

For a manual visual check use `task run:demo`. For the **headless release gate** that asserts the
same flow against the live stack (register/login/logout, both transport modes, a localized surface,
the WebSocket echo, a `ZenError` path), use **`task test:e2e`** — it brings the stack up, runs
zen_demo's pure-Dart integration suite on `ZEN_APP_PORT`, tears down, and propagates the exit code.
No mocks; it hits real Supabase + Quarkus.

## Client build defines (compile-time config)

The Flutter client reads config at **compile time**. When running/building it manually, pass
`--dart-define=ZEN_ENV=<dev|prd>`, `--dart-define=ZEN_PLATFORM=<web|macos|linux|...>`, and
`--dart-define=ZEN_API_URL=<url>` (as `run:demo` does). Never introduce runtime client config.

## Ports at a glance

| Surface | Port |
|---|---|
| Quarkus dev (`run:server`) | 8080 |
| Quarkus under `run:demo`/e2e (`ZEN_APP_PORT`) | 8085 |
| zen_demo web (`ZEN_WEB_PORT`) | 5200 |
| Admin panel | 5173 |
| Supabase API / DB / Studio | 54321 / 54322 / 54323 |
