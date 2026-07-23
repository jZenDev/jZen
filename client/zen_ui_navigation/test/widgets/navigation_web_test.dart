import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

// These two exercise the web navigation layout (a Scaffold.drawer / top menu). They belong
// to the web platform pass (ZEN_PLATFORM=web on the web runtime): on the host VM run the
// closed Scaffold.drawer is not built into the tree, so they are gated to the web platform.
void main() {
  testWidgets('web navigation renders narrow (drawer) layout',
      (WidgetTester tester) async {
    final items = List.generate(
      3,
      (i) => ZenNavigationItem(
        id: 'w$i',
        label: 'Item $i',
        builder: (c) => Text('Content $i'),
      ),
    );


    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 800)),
      child: MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
            builder: (ctx) => buildPlatformNavigation(
                  context: ctx,
                  selectedIndex: 0,
                  onItemSelected: (_) {},
                  items: items,
                )),
      ),
    ));

    // Narrow layout should include a Drawer
    expect(find.byType(Drawer), findsOneWidget);
    // Body should show selected content
    expect(find.text('Content 0'), findsOneWidget);
  }, skip: !zenIsWeb);

  testWidgets('web navigation renders wide (top menu) layout and responds',
      (WidgetTester tester) async {
    final items = List.generate(
      3,
      (i) => ZenNavigationItem(
        id: 'w$i',
        label: 'Item $i',
        builder: (c) => Text('Content $i'),
      ),
    );


    var selected = -1;

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(1200, 800)),
      child: MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
            builder: (ctx) => buildPlatformNavigation(
                  context: ctx,
                  selectedIndex: 1,
                  onItemSelected: (i) => selected = i,
                  items: items,
                )),
      ),
    ));

    // Top menu buttons should be present
    expect(find.byType(TextButton), findsWidgets);
    // Body should show content for selectedIndex (1)
    expect(find.text('Content 1'), findsOneWidget);

    // Tap the first top menu button to change selection
    await tester.tap(find.widgetWithText(TextButton, 'Item 0').first);
    await tester.pumpAndSettle();
    expect(selected, equals(0));
  }, skip: !zenIsWeb);
}
