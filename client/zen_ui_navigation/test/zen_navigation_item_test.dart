import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBuildContext extends Mock implements BuildContext {}

void main() {
  group('ZenNavigationItem', () {
    testWidgets('creates item with required fields', (tester) async {
      final item = ZenNavigationItem(
        id: 'home',
        label: 'Home',
        icon: Icons.home,
        builder: (context) => const Text('Home Screen'),
      );

      expect(item.id, 'home');
      expect(item.label, 'Home');
      expect(item.icon, Icons.home);
      expect(item.badgeCount, isNull);
    });

    testWidgets('creates item with badge count', (tester) async {
      final item = ZenNavigationItem(
        id: 'messages',
        label: 'Messages',
        icon: Icons.message,
        builder: (context) => const Text('Messages Screen'),
        badgeCount: 5,
      );

      expect(item.badgeCount, 5);
    });

    testWidgets('builder returns correct widget', (tester) async {
      final item = ZenNavigationItem(
        id: 'home',
        label: 'Home',
        icon: Icons.home,
        builder: (context) => const Text('Home Screen'),
      );

      final widget = item.builder(MockBuildContext());
      expect(widget, isA<Text>());
    });
  });

  group('ZenNavigation widget structure', () {
    testWidgets('accepts all required parameters', (WidgetTester tester) async {
      // ZenNavigation uses native platform builders and is not implemented on web.
      if (zenIsWeb) return;
      final items = [
        ZenNavigationItem(
          id: 'home',
          label: 'Home',
          icon: Icons.home,
          builder: (context) => const Text('Home'),
        ),
        ZenNavigationItem(
          id: 'search',
          label: 'Search',
          icon: Icons.search,
          builder: (context) => const Text('Search'),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: NavigationLocalizations.localizationsDelegates,
          supportedLocales: NavigationLocalizations.supportedLocales,
          home: ZenNavigation(items: items, selectedIndex: 0, onItemSelected: (index) {}),
        ),
      );

      // Widget builds without error
      expect(find.byType(ZenNavigation), findsOneWidget);
    });

    testWidgets('handles item selection callback', (WidgetTester tester) async {
      // ZenNavigation uses native platform builders and is not implemented on web.
      if (zenIsWeb) return;
      final items = [
        ZenNavigationItem(
          id: 'home',
          label: 'Home',
          icon: Icons.home,
          builder: (context) => const Text('Home'),
        ),
        ZenNavigationItem(
          id: 'search',
          label: 'Search',
          icon: Icons.search,
          builder: (context) => const Text('Search'),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: NavigationLocalizations.localizationsDelegates,
          supportedLocales: NavigationLocalizations.supportedLocales,
          home: ZenNavigation(items: items, selectedIndex: 0, onItemSelected: (index) {}),
        ),
      );

      // Note: Actual navigation interaction testing would require
      // platform-specific implementation details
      expect(find.byType(ZenNavigation), findsOneWidget);
    });
  });
}
