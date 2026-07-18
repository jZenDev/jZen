/// Unified, adaptive navigation layer for jZen applications.
///
/// This package provides platform-adaptive navigation components that
/// automatically adjust to different screen sizes and platform
/// (mobile, web, desktop). The state is managed by the user.
///
/// ## Usage
///
/// ```dart
/// import 'package:zen_ui_navigation/zen_ui_navigation.dart';
///
/// // Create a state provider for the navigation index
/// final navStateProvider = StateProvider<int>((ref) => 0);
///
/// // Define your navigation items
/// final navigationItems = [
///   ZenNavigationItem(
///     id: 'home',
///     label: 'Home', // or t.Home for l10n
///     icon: Icons.home,
///     builder: (context) => const HomeScreen(),
///   ),
/// ];
///
/// // Use the navigation bar in your app
/// ZenNavigation(
///     items: navigationItems,
///     selectedIndex: ref.watch(navProvider),
///     onItemSelected: ref.read(navProvider.notifier).select,
/// )
/// ```
library;

export 'src/zen_navigation.dart';
export 'src/zen_navigation_item.dart';
