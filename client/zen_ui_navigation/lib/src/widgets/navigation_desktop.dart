import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart' show FocusRing;

import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_badge.dart';
import 'navigation_focus.dart';

/// Platform-specific navigation builder for desktop platforms.
/// Shows all navigation items in a NavigationRail.
///
/// NavigationRail announces each destination's label, its selected state and its position
/// ("Tab 1 of 3") itself, so the destinations add no semantics of their own. [FocusRing] sits
/// in the icon because the rail exposes no hook for its focus styling, and the icon is inside
/// the destination's focus node.
const PlatformNavigationBuilder buildDesktopNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
  ValueChanged<String>? onItemSelectedId,
  String? labelMore,
}) => Row(
  children: [
    NavigationRegion(
      child: NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: (int index) {
          onItemSelected(index);
          onItemSelectedId?.call(items[index].id);
        },
        labelType: NavigationRailLabelType.all,
        destinations: [
          for (final item in items)
            NavigationRailDestination(
              icon: FocusRing(child: navigationBadge(item)),
              label: Text(item.label),
            ),
        ],
      ),
    ),
    const VerticalDivider(thickness: 1, width: 1),
    Expanded(child: NavigationContent(child: items[selectedIndex].builder(context))),
  ],
);
