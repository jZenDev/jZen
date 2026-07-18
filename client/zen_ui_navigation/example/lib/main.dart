import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/localization_providers.dart'; // Added import
import 'providers/navigation_providers.dart';

void main() {
  runApp(const ProviderScope(child: NavigationExampleApp()));
}

class NavigationExampleApp extends StatelessWidget {
  const NavigationExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'jZen Navigation Demo',
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
    final navItems = ref.watch(navigationItemsProvider);
    final localization = ref.watch(localizationServiceProvider);
    final language = ref.watch(languageProvider);

    return ZenNavigation(
      items: navItems,
      selectedIndex: selectedIndex,
      onItemSelected: (index) {
        ref.read(selectedNavigationIndexProvider.notifier).setIndex(index);
      },
      localization: localization,
      language: language,
    );
  }
}
