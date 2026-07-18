# zen_ui_identity

A cross-platform, adaptive Flutter UI package for jZen identity flows, built with domain
purity in mind. It depends only on the `IdentityRepository` contract from `zen_identity`, so
the backing implementation (e.g. `SupabaseIdentityRepository`) is injected by the app, not
baked in.

## Features

- **Adaptive design** — screens and widgets adapt to mobile and desktop layouts.
- **Domain pure** — speaks the `zen_identity` contracts; no transport or provider coupling.
- **Localized** — integrates with `zen_localization`.
- **Navigation ready** — composes with `zen_ui_navigation`.

## Components

- Widgets: `IdentityTextField`, `IdentityButton`, `IdentityStatusChip`.
- Screens: `LoginScreen`, `RegisterScreen`, `RestorePasswordScreen`, `ProfileScreen`,
  `AuthorityRolesScreen`.
- State: `identityRepositoryProvider` (override it in your app) and `identitySessionStoreProvider`.

## Getting started

### 1. Provide a repository

The package ships no repository; override the provider in your app's `ProviderScope`:

```dart
ProviderScope(
  overrides: [
    identityRepositoryProvider.overrideWith((ref) => SupabaseIdentityRepository()),
  ],
  child: const MyApp(),
);
```

### 2. Theming

```dart
MaterialApp(
  theme: ThemeData(
    extensions: [IdentityThemeExtension.fallback()],
  ),
);
```

### 3. Localization

```dart
final messages = IdentityMessages(localizationService, 'en');
```

## Running the example

The `example/` app wires `SupabaseIdentityRepository` and shows every identity flow composed
with `ZenNavigation`. It targets the compile-time `ZEN_API_URL`, so run the backend first
(`task run:all`), then:

```bash
cd example
flutter run --dart-define=ZEN_PLATFORM=<macos|ios|android|web> --dart-define=ZEN_API_URL=http://localhost:8080
```

See [example/lib/main.dart](example/lib/main.dart) for the wiring.

## Telemetry

The screens expose identity-aware success callbacks (e.g. `onLoginSuccess`) so an app can log
analytics without the package depending on any analytics library.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
