import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_desktop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

void main() {
  testWidgets('buildDesktopNavigation renders NavigationRail and selected body',
      (WidgetTester tester) async {
    // Only run desktop-specific assertions when the platform is desktop.
    if (!zenIsDesktop) return;

    final items = <ZenNavigationItem>[
      ZenNavigationItem(
        id: 'one',
        label: 'One',
        icon: Icons.looks_one,
        builder: (c) => const Center(child: Text('Body One')),
      ),
      ZenNavigationItem(
        id: 'two',
        label: 'Two',
        icon: Icons.looks_two,
        builder: (c) => const Center(child: Text('Body Two')),
      ),
      ZenNavigationItem(
        id: 'three',
        label: 'Three',
        icon: Icons.looks_3,
        builder: (c) => const Center(child: Text('Body Three')),
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: Builder(
          builder: (context) => buildDesktopNavigation(
                context: context,
                selectedIndex: 1,
                onItemSelected: (_) {},
                items: items,
              )),
    ));

    await tester.pumpAndSettle();

    // NavigationRail is rendered with destinations for each item.
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);

    // The body for selectedIndex=1 should be visible.
    expect(find.text('Body Two'), findsOneWidget);
  });
}
