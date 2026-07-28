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

## Email links, and what a native build would still need

On the web this works today and needs nothing from you: a confirmation or recovery link lands on
`/auth/callback`, the app reads the tokens out of the URL fragment, exchanges them for a session,
and renders already signed in (ADR-018).

**This app has no native runners** — there is no `android/`, `ios/`, or `macos/` directory, only
`web/`. So the native half of the flow is not "switched off", it has nowhere to be switched on.
Everything that is *not* platform-specific is already in place and shared: `ZenAuthLink.parse`
takes a plain `Uri`, and `IdentitySessionStore.consumeAuthLink(uri)` exchanges a link that arrives
while the app is running. What a native build would add, in order:

1. **Generate the runners** — `flutter create --platforms=android,ios,macos .` from this directory.
2. **Pick a scheme and register it** per platform: an Android `intent-filter`, an iOS
   `CFBundleURLTypes` entry (or Universal Links with an associated domain), a macOS URL type.
3. **Build with the matching define** so the backend is told where the link should return to:
   `--dart-define=ZEN_AUTH_REDIRECT_URI=zendemo://auth-callback`.
4. **Configure the same address server-side**, in `AUTH_REDIRECT_URIS` *and* in the Supabase
   project's Redirect URLs. The server accepts a client-named return address only on an **exact**
   match with a configured one, because that address is where a live session token gets mailed.
   Both halves or neither: registration fails loudly rather than silently mailing the wrong place.
5. **Deliver the received URL** to `consumeAuthLink` — a deep-link plugin or a platform channel;
   the framework does not care which, and takes a `Uri`.

One thing to get right in step 5: a tap that **starts** the app is not the same as one that arrives
while it is running. `IdentitySessionStore.build()` only sees the former on the web, because it
reads `Uri.base` — off the web that is a file path. The initial link has to be fetched from the
plugin and passed to `consumeAuthLink` as well, or deep links will appear to work only when the app
is already open.

Steps 1–3 and 5 cannot be verified without a simulator or a device, so they are not claimed as
done here. Step 4 is enforced and tested (`IdentityServiceTest`). The full plan, and an inventory
of what is already built, is in [`ROADMAP.md`](../../../docs/architecture/ROADMAP.md) under
"Item 4 in full".

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
