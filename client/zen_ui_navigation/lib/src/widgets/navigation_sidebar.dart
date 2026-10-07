import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/generated/navigation_localizations.dart';
import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_content.dart';
import 'navigation_region.dart';
import 'navigation_sidebar_row.dart';

/// The desktop layout for macOS: a sidebar of destinations beside the selected page.
///
/// A sidebar is what a macOS app shows for top-level destinations; a tab bar belongs on iOS and
/// a rail is Material's idiom. Flutter ships no Cupertino sidebar, so it is built here from
/// primitives, and it is a navigation control with its own keyboard, focus and screen-reader
/// work: see [NavigationSidebarRow]. Colours come from the theme's [ColorScheme], as the other
/// Cupertino controls' do, so the sidebar follows the app's palette and its dark mode.
const PlatformNavigationBuilder buildSidebarNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
  ValueChanged<String>? onItemSelectedId,
  String? labelMore,
}) => Row(
  children: <Widget>[
    NavigationSidebar(
      items: items,
      selectedIndex: selectedIndex,
      onSelected: (int index) {
        onItemSelected(index);
        onItemSelectedId?.call(items[index].id);
      },
    ),
    const VerticalDivider(thickness: 1, width: 1),
    Expanded(child: NavigationContent(child: items[selectedIndex].builder(context))),
  ],
);

/// The column of [NavigationSidebarRow]s, a `navigation` landmark of one focus group.
class NavigationSidebar extends StatelessWidget {
  /// Creates the sidebar for [items] with [selectedIndex] shown.
  const NavigationSidebar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  /// The destinations, in display order.
  final List<ZenNavigationItem> items;

  /// The index of the destination currently shown.
  final int selectedIndex;

  /// Called with the index of the destination the user chose.
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final NavigationLocalizations strings = NavigationLocalizations.of(context);
    final Size screen = MediaQuery.sizeOf(context);
    // Grows with the text so a larger setting widens the column rather than squeezing it, but
    // never past two fifths of the window, which would leave the page no room.
    final double width = math.min(MediaQuery.textScalerOf(context).scale(210), screen.width * 0.4);

    return NavigationRegion(
      child: ColoredBox(
        color: scheme.surfaceContainerLow,
        child: SizedBox(
          width: width,
          height: double.infinity,
          // Scrolls rather than clips: a destination below the fold could not be reached, and
          // focus scrolls the one it lands on into view.
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  NavigationSidebarRow(
                    item: items[i],
                    selected: i == selectedIndex,
                    position: strings.position(i + 1, items.length),
                    onPressed: () => onSelected(i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
