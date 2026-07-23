# zen_demo_client — the reference app's Flutter client

The Flutter client of jZen's reference app, [`zen_demo`](../README.md). It is the surface `task
run:demo` opens in a browser and the one `task test:e2e` drives against the live stack, so it is
both the product showcase and the client half of the living end-to-end test stand.

It is an **assembly**, not a library: it wires the framework's client packages against the real
backend and owns no reusable mechanism of its own. The reusable pieces are documented with the
framework in [`client/`](../../../client/README.md); this app composes them:

- **`zen_transport`** — the dual-mode `ZenClient` and `ZenWebSocket`.
- **`zen_identity`** — `SupabaseIdentityRepository`, injected into the UI.
- **`zen_ui_identity`** / **`zen_ui_navigation`** — the adaptive screens and navigation shell.
- **`flutter_riverpod`** — provider wiring; **`flutter_localizations`** + a generated
  `DemoLocalizations` — its own typed strings (`lib/src/l10n/demo_*.arb`, ADR-009), composed
  alongside the packages' own delegates.

## Running it

The client reads its backend URL and platform as **compile-time** defines (jZen keeps client
config compile-time so the toolchain can tree-shake — STANDARDS "Client config is
compile-time"), so start the backend first, then pass the defines. The one-command path does
all of this for you:

```bash
task run:demo     # boots Supabase + backend, then runs this client in Chrome pointed at it
```

To run it by hand against an already-running backend:

```bash
cd apps/zen_demo/zen_demo_client
flutter run -d chrome \
  --dart-define=ZEN_ENV=dev \
  --dart-define=ZEN_PLATFORM=web \
  --dart-define=ZEN_API_URL=http://localhost:8085
```

## Testing

Two suites, deliberately kept apart:

| Suite | Command | What it is |
|---|---|---|
| Unit tests (`test/`) | `task test:apps:client` | Fast, offline widget/logic tests. Run headless with the host `ZEN_PLATFORM`. |
| End-to-end (`integration_test/e2e_test.dart`) | `task test:e2e` | The release gate. A **pure-Dart** suite on the VM against the **live** Supabase + Quarkus stack — no mocks. |

The e2e suite is pure Dart (`package:test`, not `flutter_test`) on purpose: it stays headless
and cheap, and because the VM is a `dart:io` platform it exercises the real native cookie jar.
Its base URL comes from `ZEN_API_URL` at runtime — this is a test harness, not the shipped
bundle, and `dart test` does not forward compile-time defines to the compiled test anyway, so
reading it at runtime does not bend the compile-time-config rule (which is about tree-shaking
the *app* bundle). See [`../README.md`](../README.md) for the full list of what it asserts.
