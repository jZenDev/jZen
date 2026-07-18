import 'package:flutter/material.dart';

import 'zen_navigation.dart' show ZenNavigation;

/// A navigation item that can be used in a [ZenNavigation].
///
/// It is a builder pattern that allows you to create a navigation item
/// with a builder function that returns a widget. This is useful for
/// creating dynamic navigation items that can be built at runtime.
///
/// Example:
/// ```dart
/// final navigationItem = ZenNavigationItem(
///   id: 'home',
///   label: 'Home' // or t.Home for l10n
///   icon: const Icon(Icons.home),
///   builder: (context) => const HomeScreen(),
///   badgeCount: 3,
/// );
/// ```
class ZenNavigationItem {
  /// Creates a new [ZenNavigationItem].
  const ZenNavigationItem({
    required this.id,
    required this.label,
    this.icon = Icons.question_mark,
    required this.builder,
    this.badgeCount,
  });

  /// The unique identifier for the navigation item.
  final String id;

  /// The label for the navigation item.
  final String label;

  /// The icon for the navigation item.
  final IconData icon;

  /// The builder function that returns a widget for the navigation item.
  final WidgetBuilder builder;

  /// The badge count for the navigation item.
  final int? badgeCount;
}
