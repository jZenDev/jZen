import 'package:zen_core/zen_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../zen_navigation_item.dart';

/// A page that displays overflow navigation items that don't fit in the bottom navigation bar.
///
/// This page is shown when the 'More' button is tapped in the mobile navigation.
/// It displays a list of overflow items and allows the user to navigate to them.
class NavigationMorePage extends StatelessWidget {
  /// Creates a new [NavigationMorePage].
  const NavigationMorePage({
    super.key,
    required this.overflowItems,
    required this.selectedIndex,
    required this.indexOffset,
    required this.onItemSelected,
    required this.labelMore,
  });

  /// The list of overflow navigation items to display.
  final List<ZenNavigationItem> overflowItems;

  /// The currently selected index (global across all items).
  final int selectedIndex;

  /// The index offset where overflow items start in the global list.
  final int indexOffset;

  /// Callback when an item is selected.
  final ValueChanged<int> onItemSelected;

  /// Label for the 'More' button.
  final String labelMore;

  @override
  Widget build(BuildContext context) {
    if (zenIsIOS) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(middle: Text(labelMore)),
        child: SafeArea(
          child: ListView.builder(
            itemCount: overflowItems.length,
            itemBuilder: (BuildContext context, int index) {
              final ZenNavigationItem item = overflowItems[index];
              final int globalIndex = indexOffset + index;
              final bool isSelected = selectedIndex == globalIndex;

              return CupertinoListTile(
                leading: Icon(
                  item.icon,
                  color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.label,
                ),
                title: Text(item.label),
                trailing: isSelected
                    ? const Icon(CupertinoIcons.checkmark_alt, color: CupertinoColors.activeBlue)
                    : null,
                onTap: () {
                  onItemSelected(globalIndex);
                },
              );
            },
          ),
        ),
      );
    }

    // Material design
    return Scaffold(
      appBar: AppBar(title: Text(labelMore)),
      body: ListView.builder(
        itemCount: overflowItems.length,
        itemBuilder: (BuildContext context, int index) {
          final ZenNavigationItem item = overflowItems[index];
          final int globalIndex = indexOffset + index;
          final bool isSelected = selectedIndex == globalIndex;

          return ListTile(
            leading: Icon(item.icon, color: isSelected ? Theme.of(context).primaryColor : null),
            title: Text(
              item.label,
              style: TextStyle(
                color: isSelected ? Theme.of(context).primaryColor : null,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: isSelected ? Icon(Icons.check, color: Theme.of(context).primaryColor) : null,
            onTap: () {
              onItemSelected(globalIndex);
            },
          );
        },
      ),
    );
  }
}
