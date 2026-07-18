import 'package:zen_localization/zen_localization.dart';
import 'package:flutter/material.dart';

import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_badge.dart';

/// Platform-specific navigation builder for desktop platforms.
/// Shows all navigation items in a NavigationRail.
const PlatformNavigationBuilder buildDesktopNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
  required ZenLocalizationService localization,
  required String language,
  ValueChanged<String>? onItemSelectedId,
  String? labelMore,
}) =>
    Row(
      children: [
        NavigationRail(
          selectedIndex: selectedIndex,
          onDestinationSelected: (int index) {
            onItemSelected(index);
            onItemSelectedId?.call(items[index].id);
          },
          labelType: NavigationRailLabelType.all,
          destinations: [
            for (int i = 0; i < items.length; i++)
              NavigationRailDestination(
                icon: Semantics(
                  label: items[i].label,
                  button: true,
                  selected: i == selectedIndex,
                  child: navigationBadge(items[i], i == selectedIndex),
                ),
                label: Text(items[i].label),
              ),
          ],
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(child: items[selectedIndex].builder(context)),
      ],
    );
