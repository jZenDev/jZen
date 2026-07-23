# zen_demo — the reference app

`zen_demo` is jZen's **reference application**: a full-stack app assembled from the framework,
and today the only one. It has two jobs, and doing both is the point:

- **The product showcase** — the fastest way to watch the whole framework work end to end.
- **The living end-to-end test stand** — the same flows, asserted headlessly against the real
  stack as jZen's release gate.

Because it assembles the framework on **both** sides (a Flutter client *and* a Quarkus server),
a green `zen_demo` run proves the framework composes end to end — which is exactly why it is the
integration gate rather than a toy (ADR-001).

## The three surfaces

`apps/zen_demo/` holds one folder per surface. Each assembles a different tier of the framework;
the reusable machinery each depends on is documented with the framework, not duplicated here.

| Surface | What it assembles | Framework docs |
|---|---|---|
| `zen_demo_client/` | The Flutter client — Riverpod + `zen_ui_identity` + `zen_ui_navigation` + `zen_transport` against the backend. | [`README`](zen_demo_client/README.md), [`client/`](../../client/README.md) |
| `zen_demo_server/` | The Quarkus backend — the only `quarkus`-packaged module, inheriting `zen-parent` and assembling the framework libraries. | [`server/`](../../server/README.md) |
| `zen_demo_admin/` | The react-admin panel — assembles `@jzen/admin-core` and registers domain resources. | [`admin/`](../../admin/README.md) |

## Running it (showcase)

```bash
task run:demo     # Supabase + backend + the Flutter client in Chrome
```

This brings up the local Supabase stack, starts the backend on `ZEN_APP_PORT` (default `8085`,
to dodge a leftover stack shadowing `:8080`), waits for `/health`, then runs the client in
Chrome pointed at it. To bring up the admin panel instead, `task run:admin`.

**Signing in — there is no pre-seeded demo account.** The client talks to real Supabase, and the
local stack auto-confirms sign-ups, so you **register a fresh account in the app** and it logs
you straight in. The login screen **says this on itself** — a banner points you at Sign Up — so a
first-time user is not left guessing (`zen_demo_client`'s `AuthFlow` fills the framework login
screen's `banner` slot with a localized hint). The **admin panel** does need an account with the
`admin` role (roles live in the `users` table, not the JWT), and that one *is* seeded for you: run
`scripts/seed-admin.sh`, which registers `admin@jzen.local` / `password123` and promotes it to
`admin` — then sign in at `http://localhost:5173`. See
[`../../scripts/README.md`](../../scripts/README.md).

**Stopping it.** In the `task run:demo` terminal, press **`q` once** — Flutter's quit key. The app
closes and the task's exit trap tears the backend down with it. A single **`Ctrl-C`** does the
same (it fires the same trap); you should not need to press it repeatedly. **Supabase is left
running** (other work may share it) — stop it alone with `task stop:supabase`. If a run ever
leaves something bound to a port, `scripts/stop.sh [--supabase]` frees the backend, `:8080`, admin
`:5173`, and demo web `:5200` in one pass (and stops Supabase with `--supabase`). There is
deliberately no `stop:demo` task: the run task cleans up after itself on exit, so the only
lingering process is the shared Supabase stack.

## Testing it (the gate)

```bash
task test:e2e     # the release gate — the same flow, headless, against the live stack
```

`task test:e2e` boots real Supabase + Quarkus and runs the client's **pure-Dart** integration
suite (`integration_test/e2e_test.dart`) on the VM, then propagates the suite's exit code. A
pure-Dart VM suite keeps CI headless and cheap, and because the VM is a `dart:io` platform it
exercises the **real** native session-cookie jar rather than a stub.

**No mocks — it hits the real stack.** What it asserts end to end:

- register + login via real Supabase, and the session cookie surviving across requests;
- an auth-gated endpoint working on a second client that shares the cookie jar;
- a typed round trip in **both** transport modes (JSON and Protobuf);
- a localized surface (`en` vs `uk`);
- the WebSocket echo;
- an error path returning a `ZenError`;
- the authenticated job trigger refusing an uncredentialed call and running due jobs with the
  shared secret;
- logout clearing the session.

`run:demo` and `test:e2e` are the same flow seen two ways — one for a human, one for CI. Unit
tests that do not need the live stack run under `task test:apps:client` (client) and `task
test:apps:server` (server, `@QuarkusTest` on Dev Services Postgres — Docker must be running).

## The reference backend's own README

The three surfaces do not each carry a separate README: their reusable stories live in
[`server/`](../../server/README.md), [`client/`](../../client/README.md), and
[`admin/`](../../admin/README.md), and their assembly story is this file. `zen_demo_client`
carries its own README because it is the surface `task run:demo` and `task test:e2e` drive
directly.
