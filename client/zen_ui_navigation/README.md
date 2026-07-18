# zen_ui_navigation

Unified, adaptive navigation layer for jZen Flutter applications, with platform-specific
optimizations.

## Features

- **Platform adaptive** — adapts to mobile, web, and desktop layouts.
- **Responsive** — breakpoint-based layouts with smart overflow handling.
- **Zero configuration** — sensible defaults, customizable when needed.

## Installation

Inside the jZen client workspace, depend on it by path:

```yaml
dependencies:
  zen_ui_navigation:
    path: ../zen_ui_navigation
```

## Quick start

```dart
import 'package:flutter/material.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  final List<ZenNavigationItem> _navItems = [
    ZenNavigationItem(id: 'home', label: 'Home', icon: Icons.home,
        builder: (context) => const HomeTab()),
    ZenNavigationItem(id: 'search', label: 'Search', icon: Icons.search,
        builder: (context) => const SearchTab()),
    ZenNavigationItem(id: 'profile', label: 'Profile', icon: Icons.person,
        builder: (context) => const ProfileTab(), badgeCount: 3),
  ];

  @override
  Widget build(BuildContext context) => ZenNavigation(
        items: _navItems,
        selectedIndex: _selectedIndex,
        onItemSelected: (index) => setState(() => _selectedIndex = index),
      );
}
```

## Platform support (compile-time)

The package tree-shakes to the target platform, so specify it with the `ZEN_PLATFORM` define
at compile time (jZen keeps client config compile-time, see `docs/architecture/STANDARDS.md`):

```bash
flutter run --dart-define=ZEN_PLATFORM=ios
flutter run -d chrome --dart-define=ZEN_PLATFORM=web
```

Supported values: `ios`, `android`, `web`, `macos`, `windows`, `linux`. If `ZEN_PLATFORM` is
unset, a debug assertion fails. (`task test:client` passes the host platform automatically.)

## Telemetry

`ZenNavigation` exposes an optional `onItemSelectedId` callback so analytics can key off a
stable item id rather than an index, keeping the UI decoupled from any analytics package:

```dart
ZenNavigation(
  items: _navItems,
  selectedIndex: _selectedIndex,
  onItemSelected: (index) => setState(() => _selectedIndex = index),
  onItemSelectedId: (id) => MyAnalytics.track('navigation_click', {'item_id': id}),
);
```

## Badges and overflow

Set `badgeCount` on an item to show a notification badge. On mobile, more than four items
overflow into a customizable "More" menu (`labelMore`).

## Example

See the [`example/`](example) directory.

## License

Apache License 2.0 — see [LICENSE](LICENSE).
