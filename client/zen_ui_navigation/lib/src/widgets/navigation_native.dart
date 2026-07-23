import 'package:zen_core/zen_core.dart';
import 'package:flutter/material.dart';

import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_desktop.dart';
import 'navigation_mobile.dart';

/// Platform-specific navigation builder for native platforms.
/// It defines the current platform via env variable ZEN_PLATFORM
/// and returns a Mobile or Desktop layout.
const PlatformNavigationBuilder buildPlatformNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
  ValueChanged<String>? onItemSelectedId,
  String? labelMore,
}) {
  if (zenIsMobile) {
    return buildMobileNavigation(
      context: context,
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      onItemSelectedId: onItemSelectedId,
      items: items,
      labelMore: labelMore,
    );
  }
  if (zenIsDesktop) {
    return buildDesktopNavigation(
      context: context,
      selectedIndex: selectedIndex,
      onItemSelected: onItemSelected,
      onItemSelectedId: onItemSelectedId,
      items: items,
      labelMore: labelMore,
    );
  }

  return throw UnimplementedError('Unsupported platform: $zenPlatform');
}
