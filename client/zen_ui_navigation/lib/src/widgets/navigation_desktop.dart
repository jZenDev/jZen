import 'package:zen_core/zen_core.dart';

import '../zen_navigation.dart';
import 'navigation_rail.dart';
import 'navigation_sidebar.dart';

/// Platform-specific navigation builder for desktop platforms.
///
/// macOS gets a sidebar, the shell a macOS app shows; Linux and Windows get a Material rail. The
/// choice is on a compile-time constant, so the other layout is tree-shaken out of the build.
const PlatformNavigationBuilder buildDesktopNavigation = zenIsApplePlatform
    ? buildSidebarNavigation
    : buildRailNavigation;
