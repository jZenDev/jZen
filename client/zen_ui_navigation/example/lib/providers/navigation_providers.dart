import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import 'localization_providers.dart';

/// Provider for navigation items
final navigationItemsProvider = Provider<List<ZenNavigationItem>>((ref) {
  final localization = ref.watch(localizationServiceProvider);
  final language = ref.watch(languageProvider);

  return [
    ZenNavigationItem(
      id: 'home',
      label: 'Home',
      icon: Icons.home,
      builder: (context) =>
          HomeScreen(localization: localization, language: language),
    ),
    ZenNavigationItem(
      id: 'search',
      label: 'Search',
      icon: Icons.search,
      builder: (context) =>
          SearchScreen(localization: localization, language: language),
    ),
    ZenNavigationItem(
      id: 'profile',
      label: 'Profile',
      icon: Icons.person,
      builder: (context) =>
          ProfileScreen(localization: localization, language: language),
      badgeCount: 3,
    ),
    ZenNavigationItem(
      id: 'settings',
      label: 'Settings',
      icon: Icons.settings,
      builder: (context) =>
          SettingsScreen(localization: localization, language: language),
    ),
  ];
});

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
