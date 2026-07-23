import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/example_localizations.dart';
import 'providers/localization_providers.dart';
import 'providers/navigation_providers.dart';

void main() {
  runApp(const ProviderScope(child: NavigationExampleApp()));
}

class NavigationExampleApp extends ConsumerWidget {
  const NavigationExampleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'jZen Navigation Demo',
      // The chosen locale drives Localizations, which re-renders every screen reading
      // ExampleLocalizations.of(context) - including this package's own overflow label.
      locale: ref.watch(localeProvider),
      // Per-package generation (ADR-009) means each localized package brings its own
      // delegate and the app composes them: the example's own strings, plus the ones
      // zen_ui_navigation owns, plus Flutter's built-in Material/Cupertino/Widgets sets.
      localizationsDelegates: const [
        ...ExampleLocalizations.localizationsDelegates,
        NavigationLocalizations.delegate,
      ],
      supportedLocales: ExampleLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AdaptiveNavigationShell(),
    );
  }
}

/// Adaptive navigation shell that changes layout based on screen size
class AdaptiveNavigationShell extends ConsumerWidget {
  const AdaptiveNavigationShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedNavigationIndexProvider);

    return ZenNavigation(
      items: navigationItems(ExampleLocalizations.of(context)),
      selectedIndex: selectedIndex,
      onItemSelected: (index) {
        ref.read(selectedNavigationIndexProvider.notifier).setIndex(index);
      },
    );
  }
}
