import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/example_localizations.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';

/// The navigation items, with tab labels taken from the typed generated accessors.
///
/// A plain function of [ExampleLocalizations] rather than a provider, because the labels
/// depend on the ambient locale and that is read from the [BuildContext] - so the caller
/// (which has a context) supplies them and a locale switch relabels the bar for free.
List<ZenNavigationItem> navigationItems(ExampleLocalizations messages) {
  return [
    ZenNavigationItem(
      id: 'home',
      label: messages.homeTitle,
      icon: Icons.home,
      builder: (context) => const HomeScreen(),
    ),
    ZenNavigationItem(
      id: 'search',
      label: messages.searchTitle,
      icon: Icons.search,
      builder: (context) => const SearchScreen(),
    ),
    ZenNavigationItem(
      id: 'profile',
      label: messages.profileTitle,
      icon: Icons.person,
      builder: (context) => const ProfileScreen(),
      badgeCount: 3,
    ),
    ZenNavigationItem(
      id: 'settings',
      label: messages.settingsTitle,
      icon: Icons.settings,
      builder: (context) => const SettingsScreen(),
    ),
  ];
}

/// Notifier for selected navigation index
class NavigationIndexNotifier extends Notifier<int> {
  @override
  int build() {
    return 0;
  }

  void setIndex(int index) {
    state = index;
  }
}

/// Provider for selected navigation index
final selectedNavigationIndexProvider =
    NotifierProvider<NavigationIndexNotifier, int>(NavigationIndexNotifier.new);
