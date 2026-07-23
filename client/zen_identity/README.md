# zen_identity

The identity capability for the jZen client: the `IdentityRepository` contract and its
Supabase-backed implementation, called over `zen_transport`'s dual-mode `ZenClient`. It is the
data/logic layer for authentication — login, register, restore password, the current identity —
with no UI of its own (the adaptive screens live in `zen_ui_identity`, which depends only on this
contract).

> Part of the [jZen](https://github.com/jZenDev/jZen) monorepo. Inside the repo it is a path
> dependency in the `client/` pub workspace, versioned in lockstep with the product; this README
> also stands on its own for a reader who meets the package by itself.

## What it provides

- **`IdentityRepository`** — the contract the app and the UI depend on, so the backing
  implementation is injected rather than baked in.
- **`SupabaseIdentityRepository`** — the implementation that calls the jZen auth endpoints
  (`POST /api/v1/auth/{login,register,restore-password,logout,refresh}`,
  `GET /api/v1/auth/identity`) over `ZenClient`, and manages the session.
- **Identity models** — the typed shapes the flows exchange.

Auth on the server is framework-side too (the `AuthResource` in `zen-identity`), so the client
contract and the server surface are two halves of the same capability.

## Using it

```yaml
dependencies:
  zen_identity:
    path: ../zen_identity
```

Provide the repository to the UI by overriding `identityRepositoryProvider` in your app's
`ProviderScope` (see [`../zen_ui_identity/README.md`](../zen_ui_identity/README.md)):

```dart
ProviderScope(
  overrides: [
    identityRepositoryProvider.overrideWith((ref) => SupabaseIdentityRepository()),
  ],
  child: const MyApp(),
);
```

## Testing

`task test:client` runs the suite (pure Dart). Directly: `cd client/zen_identity && dart test`.
