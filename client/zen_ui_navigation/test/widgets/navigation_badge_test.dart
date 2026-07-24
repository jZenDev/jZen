import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_badge.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

void main() {
  testWidgets('navigationBadge shows badge text when badgeCount present (Material)', (
    WidgetTester tester,
  ) async {
    if (zenIsIOS || zenIsMacOS) return;

    final item = ZenNavigationItem(
      id: 'i',
      label: 'I',
      icon: Icons.home,
      badgeCount: 3,
      builder: (c) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Scaffold(body: navigationBadge(item, false)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsWidgets);
  });

  testWidgets('navigationBadge shows badge text when badgeCount present (Cupertino)', (
    WidgetTester tester,
  ) async {
    if (!zenIsIOS && !zenIsMacOS) return;

    final item = ZenNavigationItem(
      id: 'i',
      label: 'I',
      icon: CupertinoIcons.home,
      badgeCount: 2,
      builder: (c) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(
      CupertinoApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(builder: (c) => navigationBadge(item, false)),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget);
    expect(find.byType(Icon), findsWidgets);
  });

  testWidgets('navigationBadge without badgeCount shows icon only', (WidgetTester tester) async {
    final item = ZenNavigationItem(
      id: 'i',
      label: 'I',
      icon: Icons.home,
      builder: (c) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: navigationBadge(item, false))));
    await tester.pumpAndSettle();

    expect(find.text('1'), findsNothing);
    expect(find.byIcon(Icons.home), findsWidgets);
  });

  testWidgets('navigationBadge shows label when badgeCount present', (WidgetTester tester) async {
    final item = ZenNavigationItem(
      id: 'msg',
      label: 'Messages',
      icon: Icons.message,
      builder: (c) => const SizedBox.shrink(),
      badgeCount: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: navigationBadge(item, false))),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.message), findsOneWidget);
  });

  testWidgets('navigationBadge does not show label when badgeCount null', (
    WidgetTester tester,
  ) async {
    final item = ZenNavigationItem(
      id: 'home',
      label: 'Home',
      icon: Icons.home,
      builder: (c) => const SizedBox.shrink(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Scaffold(body: Center(child: navigationBadge(item, false))),
      ),
    );

    expect(find.text('0'), findsNothing);
    expect(find.byIcon(Icons.home), findsOneWidget);
  });

  testWidgets('navigationBadge cupertino variant from target merged', (WidgetTester tester) async {
    if (!zenIsIOS && !zenIsMacOS) return;

    final item = ZenNavigationItem(
      id: 'i3',
      label: 'LC',
      icon: Icons.cake,
      builder: (c) => const SizedBox.shrink(),
      badgeCount: 7,
    );

    await tester.pumpWidget(
      CupertinoApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: CupertinoPageScaffold(child: navigationBadge(item, false)),
      ),
    );

    expect(find.text('7'), findsOneWidget);
    expect(find.byIcon(Icons.cake), findsOneWidget);
  });
}
