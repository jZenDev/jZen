import 'package:zen_core/zen_core.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/navigation_messages.dart';
import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_badge.dart';
import 'navigation_more.dart';

/// Platform-specific navigation builder for mobile platforms.
/// It define the current platform via env variable ZEN_PLATFORM
/// and returns a CupertinoTabBar or BottomNavigationBar
const PlatformNavigationBuilder buildMobileNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
  required ZenLocalizationService localization,
  required String language,
  ValueChanged<String>? onItemSelectedId,
  String? labelMore,
}) {
  final messages = NavigationMessages(localization, language);
  final moreLabel = labelMore ?? messages.more;
  final List<ZenNavigationItem> visible = items.take(zenMaxItemsMobile).toList();
  final List<ZenNavigationItem> overflow = items.length > zenMaxItemsMobile
      ? items.skip(zenMaxItemsMobile).toList()
      : <ZenNavigationItem>[];

  // Determine the index to show in the bottom navigation bar
  // If an overflow item is selected, show the "more" button as selected
  final displayIndex = selectedIndex >= zenMaxItemsMobile
      ? zenMaxItemsMobile // Show "more" as selected
      : selectedIndex;

  // Display the selected item's page (works for both regular and overflow items)
  final Widget bodyWidget = items[selectedIndex].builder(context);

  // Build bottom navigation bar items
  final List<BottomNavigationBarItem> itemsElements = [];
  for (int i = 0; i < visible.length; i++) {
    final item = visible[i];
    itemsElements.add(BottomNavigationBarItem(
      icon: Semantics(
        label: item.label,
        button: true,
        selected: i == selectedIndex,
        child: navigationBadge(item, i == selectedIndex),
      ),
      label: item.label,
    ));
  }

  // Create the "more" item if there are overflow items
  final List<BottomNavigationBarItem> itemsMoreLabel = overflow.isNotEmpty
      ? <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Semantics(
              label: moreLabel,
              button: true,
              selected: selectedIndex >= zenMaxItemsMobile,
              child: const Icon(
                zenIsIOS ? CupertinoIcons.ellipsis : Icons.more_horiz,
              ),
            ),
            label: moreLabel,
            tooltip: moreLabel,
          ),
        ]
      : <BottomNavigationBarItem>[];

  final itemsList = <BottomNavigationBarItem>[
    ...itemsElements,
    ...itemsMoreLabel
  ];

  // Handle navigation bar tap
  void handleNavTap(int index) {
    if (overflow.isNotEmpty && index == zenMaxItemsMobile) {
      // Tapped on "more" button - navigate to the overflow menu page
      Navigator.of(context).push(
        zenIsIOS
            ? CupertinoPageRoute<void>(
                builder: (BuildContext context) => NavigationMorePage(
                  overflowItems: overflow,
                  selectedIndex: selectedIndex,
                  indexOffset: zenMaxItemsMobile,
                  onItemSelected: (int globalIndex) {
                    onItemSelected(globalIndex);
                    onItemSelectedId?.call(items[globalIndex].id);
                    Navigator.of(context).pop();
                  },
                  labelMore: moreLabel,
                ),
              )
            : MaterialPageRoute<void>(
                builder: (BuildContext context) => NavigationMorePage(
                  overflowItems: overflow,
                  selectedIndex: selectedIndex,
                  indexOffset: zenMaxItemsMobile,
                  onItemSelected: (int globalIndex) {
                    onItemSelected(globalIndex);
                    onItemSelectedId?.call(items[globalIndex].id);
                    Navigator.of(context).pop();
                  },
                  labelMore: moreLabel,
                ),
              ),
      );
    } else {
      // Tapped on a regular item
      onItemSelected(index);
      onItemSelectedId?.call(items[index].id);
    }
  }

  return Scaffold(
    body: bodyWidget,
    bottomNavigationBar: zenIsIOS
        ? CupertinoTabBar(
            currentIndex: displayIndex,
            onTap: handleNavTap,
            items: itemsList,
            height: 64,
          )
        : BottomNavigationBar(
            currentIndex: displayIndex,
            onTap: handleNavTap,
            items: itemsList,
            type: BottomNavigationBarType.fixed,
          ),
  );
}
