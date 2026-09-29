import 'package:zen_core/zen_core.dart';
import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart' as m;

import '../l10n/generated/navigation_localizations.dart';
import '../zen_navigation_item.dart';

/// The icon of a navigation destination, with its badge when [ZenNavigationItem.badgeCount] is
/// positive.
///
/// It carries no label, role or selected state of its own: the control it sits in (a rail
/// destination, a bar item, a button, a list tile) already announces the destination's label and
/// whether it is selected. Announcing them here as well made a screen reader say every
/// destination two or three times and exposed a nested "button" that could not be activated.
/// What only this widget knows is the badge, so it contributes exactly that — as a semantic
/// *value*, read after the label ("Inbox, 3 new"), since a bare "3" gives no context.
m.Widget navigationBadge(ZenNavigationItem item) {
  final icon = (zenIsIOS || zenIsMacOS) ? c.Icon(item.icon) : m.Icon(item.icon);

  final int? count = item.badgeCount;
  if (count == null || count <= 0) return icon;

  return m.Builder(
    builder: (context) => m.Semantics(
      value: NavigationLocalizations.of(context).badgeCount(count),
      child: m.ExcludeSemantics(
        child: (zenIsIOS || zenIsMacOS)
            ? m.Badge(label: c.Text('$count'), child: icon)
            : m.Badge(label: m.Text('$count'), child: icon),
      ),
    ),
  );
}
