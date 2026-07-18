import 'package:zen_core/zen_core.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:flutter/material.dart';

import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_badge.dart';

/// Platform-specific navigation builder for web
/// It renders an AppBar w/ Drawer on narrow screens and
/// a top menu on wide screens using Material Design 3.
const PlatformNavigationBuilder buildPlatformNavigation = _widget;

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
  final double width = MediaQuery.of(context).size.width;
  final bool isNarrow = width < zenNarrowWidth;

  if (isNarrow) {
    // BURGER + Drawer
    return Scaffold(
      appBar: AppBar(title: Text(items[selectedIndex].label)),
      drawer: Drawer(
        child: ListView(
          children: <Widget>[
            for (int i = 0; i < items.length; i++)
              ListTile(
                title: Text(items[i].label),
                leading: navigationBadge(items[i], i == selectedIndex),
                selected: i == selectedIndex,
                onTap: () {
                  onItemSelected(i);
                  onItemSelectedId?.call(items[i].id);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
      body: items[selectedIndex].builder(context),
    );
  }

  // TOP MENU
  return Column(
    children: <Widget>[
      Material(
        elevation: 3,
        child: Row(
          children: <Widget>[
            for (int i = 0; i < items.length; i++)
              Semantics(
                label: items[i].label,
                button: true,
                selected: i == selectedIndex,
                child: TextButton.icon(
                  onPressed: () {
                    onItemSelected(i);
                    onItemSelectedId?.call(items[i].id);
                  },
                  icon: navigationBadge(items[i], i == selectedIndex),
                  label: Text(items[i].label),
                  style: TextButton.styleFrom(
                    foregroundColor: i == selectedIndex
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
      Expanded(child: items[selectedIndex].builder(context)),
    ],
  );
}
