import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/example_localizations.dart';
import 'providers/navigation_providers.dart';

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
