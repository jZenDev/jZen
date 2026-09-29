import 'package:zen_core/zen_core.dart';
import 'package:flutter/material.dart';

import '../zen_navigation.dart';
import '../zen_navigation_item.dart';
import 'navigation_badge.dart';
import 'navigation_focus.dart';

/// Platform-specific navigation builder for web
/// It renders an AppBar w/ Drawer on narrow screens and
/// a top menu on wide screens using Material Design 3.
const PlatformNavigationBuilder buildPlatformNavigation = _widget;

Widget _widget({
  required BuildContext context,
  required int selectedIndex,
  required ValueChanged<int> onItemSelected,
  required List<ZenNavigationItem> items,
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
        child: NavigationRegion(
          child: ListView(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                ListTile(
                  // ListTile announces the label and selected state itself; the ring goes in the
                  // title because that is inside the tile's focus node.
                  title: FocusRing(child: Text(items[i].label)),
                  leading: navigationBadge(items[i]),
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
      ),
      body: NavigationContent(child: items[selectedIndex].builder(context)),
    );
  }

  // TOP MENU
  return Column(
    children: <Widget>[
      Material(
        elevation: 3,
        child: NavigationRegion(
          // Scrolls rather than overflows: at 200% text size (WCAG SC 1.4.4) the labels no longer
          // fit a row that was sized for 100%, and a clipped destination cannot be reached.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (int i = 0; i < items.length; i++)
                  _TopMenuDestination(
                    item: items[i],
                    selected: i == selectedIndex,
                    onPressed: () {
                      onItemSelected(i);
                      onItemSelectedId?.call(items[i].id);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      Expanded(child: NavigationContent(child: items[selectedIndex].builder(context))),
    ],
  );
}

/// One destination of the wide top menu.
///
/// A TextButton reports that it is a button and takes its label from its text, but it has no
/// notion of being the *current* destination — so the selected state is added and merged into
/// the button's own node, giving a screen reader one actionable "Home, selected, button" rather
/// than a stack of nested nodes of which only the innermost responds.
class _TopMenuDestination extends StatelessWidget {
  const _TopMenuDestination({required this.item, required this.selected, required this.onPressed});

  final ZenNavigationItem item;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: selected ? scheme.primary : scheme.onSurface,
          ),
          child: FocusRing(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[navigationBadge(item), const SizedBox(width: 8), Text(item.label)],
            ),
          ),
        ),
      ),
    );
  }
}
