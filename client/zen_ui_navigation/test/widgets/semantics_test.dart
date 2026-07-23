import 'dart:ui' as ui;

import 'package:zen_ui_navigation/src/widgets/navigation_badge.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_desktop.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_mobile.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

void main() {

  group('Semantics Tests', () {
    testWidgets('navigationBadge has correct semantics',
        (WidgetTester tester) async {
      final item = ZenNavigationItem(
        id: 'home',
        label: 'Home Label',
        icon: Icons.home,
        builder: (c) => const Text('home'),
      );

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Scaffold(
          body: navigationBadge(item, true),
        ),
      ));

      // Use finder that looks for the semantics label
      final findSemantics = find.bySemanticsLabel('Home Label');
      expect(findSemantics, findsOneWidget);

      final semantics = tester.getSemantics(findSemantics);
      final data = semantics.getSemanticsData();
      expect(data.label, 'Home Label');
      expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);
    });

    testWidgets('Mobile more button has correct semantics',
        (WidgetTester tester) async {
      final items = List.generate(
        6,
        (i) => ZenNavigationItem(
          id: 'id_$i',
          label: 'Item $i',
          builder: (c) => Text('page_$i'),
        ),
      );

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => buildMobileNavigation(
            context: ctx,
            selectedIndex: 0,
            onItemSelected: (_) {},
            items: items,
            labelMore: 'More Menu',
          ),
        ),
      ));

      // BottomNavigationBarItem semantics often combine label and other info
      expect(find.bySemanticsLabel(RegExp(r'.*More Menu.*')), findsWidgets);
    });

    testWidgets('Desktop NavigationRail items have explicit semantics',
        (WidgetTester tester) async {
      final items = [
        ZenNavigationItem(
            id: 'h', label: 'Home', builder: (c) => const Text('H')),
      ];

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => buildDesktopNavigation(
              context: context,
              selectedIndex: 0,
              onItemSelected: (_) {},
              items: items,
            ),
          ),
        ),
      ));

      expect(find.bySemanticsLabel('Home'), findsWidgets);
    });

    testWidgets('Web top menu items have explicit semantics',
        (WidgetTester tester) async {
      final items = [
        ZenNavigationItem(
            id: 'h', label: 'Home', builder: (c) => const Text('H')),
      ];

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: MaterialApp(
          localizationsDelegates: NavigationLocalizations.localizationsDelegates,
          supportedLocales: NavigationLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => buildPlatformNavigation(
              context: ctx,
              selectedIndex: 0,
              onItemSelected: (_) {},
              items: items,
            ),
          ),
        ),
      ));

      expect(find.bySemanticsLabel('Home'), findsWidgets);
    });
  });

  group('Telemetry Tests', () {
    testWidgets('onItemSelectedId is called when item is tapped (Desktop)',
        (WidgetTester tester) async {
      final items = [
        ZenNavigationItem(
            id: 'h', label: 'Home', builder: (c) => const Text('H')),
        ZenNavigationItem(
            id: 's', label: 'Settings', builder: (c) => const Text('S')),
      ];

      String? selectedId;
      int? selectedIndex;

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => buildDesktopNavigation(
            context: ctx,
            selectedIndex: 0,
            onItemSelected: (i) => selectedIndex = i,
            onItemSelectedId: (id) => selectedId = id,
            items: items,
          ),
        ),
      ));

      await tester.tap(find.text('Settings'));
      await tester.pump();

      expect(selectedIndex, 1);
      expect(selectedId, 's');
    });

    testWidgets('onItemSelectedId is called when item is tapped (Web)',
        (WidgetTester tester) async {
      final items = [
        ZenNavigationItem(
            id: 'h', label: 'Home', builder: (c) => const Text('H')),
        ZenNavigationItem(
            id: 's', label: 'Settings', builder: (c) => const Text('S')),
      ];

      String? selectedId;
      int? selectedIndex;

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(1200, 800)),
        child: MaterialApp(
          localizationsDelegates: NavigationLocalizations.localizationsDelegates,
          supportedLocales: NavigationLocalizations.supportedLocales,
          home: Builder(
            builder: (ctx) => buildPlatformNavigation(
              context: ctx,
              selectedIndex: 0,
              onItemSelected: (i) => selectedIndex = i,
              onItemSelectedId: (id) => selectedId = id,
              items: items,
            ),
          ),
        ),
      ));

      // In wide web layout, we have buttons. We can tap by text.
      await tester.tap(find.text('Settings'));
      await tester.pump();

      expect(selectedIndex, 1);
      expect(selectedId, 's');
    });

    testWidgets('onItemSelectedId is called when item is tapped (Mobile)',
        (WidgetTester tester) async {
      final items = [
        ZenNavigationItem(
            id: 'h', label: 'Home', builder: (c) => const Text('H')),
        ZenNavigationItem(
            id: 's', label: 'Settings', builder: (c) => const Text('S')),
      ];

      String? selectedId;
      int? selectedIndex;

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => buildMobileNavigation(
            context: ctx,
            selectedIndex: 0,
            onItemSelected: (i) => selectedIndex = i,
            onItemSelectedId: (id) => selectedId = id,
            items: items,
          ),
        ),
      ));

      await tester.tap(find.text('Settings'));
      await tester.pump();

      expect(selectedIndex, 1);
      expect(selectedId, 's');
    });

    testWidgets(
        'onItemSelectedId is called when overflow item is tapped (Mobile)',
        (WidgetTester tester) async {
      final items = List.generate(
        6,
        (i) => ZenNavigationItem(
          id: 'id_$i',
          label: 'Item $i',
          builder: (c) => Text('page_$i'),
        ),
      );

      String? selectedId;
      int? selectedIndex;

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => buildMobileNavigation(
            context: ctx,
            selectedIndex: 0,
            onItemSelected: (i) => selectedIndex = i,
            onItemSelectedId: (id) => selectedId = id,
            items: items,
            labelMore: 'More',
          ),
        ),
      ));

      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item 4'));
      await tester.pumpAndSettle();

      expect(selectedIndex, 4);
      expect(selectedId, 'id_4');
    });
  });
}
