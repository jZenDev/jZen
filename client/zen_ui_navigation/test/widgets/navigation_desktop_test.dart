import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_desktop.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_rail.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_sidebar.dart';

import '../support/a11y.dart';

void main() {
  // The idiom is chosen on a compile-time constant, so a run reaches only its host's layout; the
  // layouts themselves are tested directly (keyboard_test, semantics_test, navigation_sidebar_test).
  testWidgets('desktop shows the sidebar on Apple and the rail elsewhere', (tester) async {
    if (!zenIsDesktop) return;

    await pumpNavigation(
      tester,
      (context) => buildDesktopNavigation(
        context: context,
        selectedIndex: 1,
        onItemSelected: (_) {},
        items: auditItems(),
      ),
    );

    expect(find.byType(NavigationSidebar), zenIsApplePlatform ? findsOneWidget : findsNothing);
    expect(find.byType(NavigationRail), zenIsApplePlatform ? findsNothing : findsOneWidget);
    for (int i = 0; i < 3; i++) {
      expect(find.text('Item $i'), findsOneWidget);
    }
    // The page for the selected index is shown.
    expect(find.text('page_1'), findsOneWidget);
  });

  testWidgets('the rail renders its destinations and the selected page', (tester) async {
    await pumpNavigation(
      tester,
      (context) => buildRailNavigation(
        context: context,
        selectedIndex: 1,
        onItemSelected: (_) {},
        items: auditItems(),
      ),
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('page_1'), findsOneWidget);
  });
}
