import 'package:zen_core/zen_core.dart';
import 'package:zen_localization/zen_localization.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_mobile.dart';
import 'package:zen_ui_navigation/src/zen_navigation_item.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = ZenLocalizationConfig();
  final service = ZenLocalizationService(config: config);

  testWidgets('mobile navigation shows body and items without overflow',
      (WidgetTester tester) async {
    final items = List.generate(
      3,
      (i) => ZenNavigationItem(
        id: 'id_$i',
        label: 'Item $i',
        icon: Icons.home,
        builder: (c) => Text('Content $i'),
      ),
    );

    var selected = 1;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (ctx) => buildMobileNavigation(
                context: ctx,
                selectedIndex: selected,
                onItemSelected: (i) => selected = i,
                items: items,
                localization: service,
                language: 'en',
                labelMore: 'More',
              )),
    ));

    // Body should show the selected item's content
    expect(find.text('Content 1'), findsOneWidget);
    // Bottom nav labels should be present
    expect(find.text('Item 0'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
  });

  testWidgets(
      'buildMobileNavigation shows bottom bar and opens more page for overflow (additional)',
      (WidgetTester tester) async {
    // Create more items than zenMaxItemsMobile (4) to cause overflow
    final items = List.generate(
      6,
      (i) => ZenNavigationItem(
        id: 'id_extra_$i',
        label: 'Item $i',
        builder: (c) => Text('page_$i'),
      ),
    );

    // reuse the service defined above
    var selected = -1;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (ctx) => buildMobileNavigation(
                context: ctx,
                selectedIndex: 0,
                onItemSelected: (i) => selected = i,
                items: items,
                localization: service,
                language: 'en',
                labelMore: 'More',
              )),
    ));

    // BottomNavigationBar should be present
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // Tap the 'More' label to navigate to the overflow page
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();

    // Overflow page should show overflow item labels
    expect(find.text('Item 4'), findsOneWidget);

    // Tap overflow item and ensure callback invoked with global index
    await tester.tap(find.text('Item 4'));
    await tester.pumpAndSettle();
    expect(selected, equals(4));
  });

  testWidgets('mobile navigation overflow opens NavigationMorePage and selects',
      (WidgetTester tester) async {
    // Create more items than zenMaxItemsMobile (4) to cause overflow
    final items = List.generate(
      5,
      (i) => ZenNavigationItem(
        id: 'id_$i',
        label: 'Item $i',
        icon: Icons.home,
        builder: (c) => Text('Content $i'),
      ),
    );

    var selectedCalled = -1;

    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (ctx) => buildMobileNavigation(
                context: ctx,
                selectedIndex: 4,
                onItemSelected: (i) => selectedCalled = i,
                items: items,
                localization: service,
                language: 'en',
                labelMore: 'More',
              )),
    ));

    // Selected item's body should be shown (overflow item)
    expect(find.text('Content 4'), findsOneWidget);

    // Tap the More label in the BottomNavigationBar to open overflow page
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();

    // NavigationMorePage should show label and overflow item
    expect(find.text('More'), findsWidgets);
    expect(find.text('Item 4'), findsOneWidget);

    // Tap the overflow item to trigger selection (global index should be 4)
    await tester.tap(find.text('Item 4'));
    await tester.pumpAndSettle();

    expect(selectedCalled, 4);
  });

  testWidgets(
      'mobile navigation uses localization more label when labelMore omitted (Material)',
      (WidgetTester tester) async {
    if (zenIsIOS) return;

    // Create more items than zenMaxItemsMobile (4) to cause overflow
    final items = List.generate(
      5,
      (i) => ZenNavigationItem(
        id: 'id_$i',
        label: 'Item $i',
        icon: Icons.home,
        builder: (c) => Text('Content $i'),
      ),
    );

    final prodService = ZenLocalizationService(
      config: const ZenLocalizationConfig(),
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (ctx) => buildMobileNavigation(
                context: ctx,
                selectedIndex: 4,
                onItemSelected: (_) {},
                items: items,
                localization: prodService,
                language: 'en',
                // labelMore omitted to exercise NavigationMessages.more
              )),
    ));

    await tester.pumpAndSettle();

    // The More label should come from localization (in production returns key)
    expect(find.text('navigation.more'), findsWidgets);
  });

  testWidgets(
      'mobile navigation uses localization more label when labelMore omitted (Cupertino)',
      (WidgetTester tester) async {
    if (!zenIsIOS) return;

    final items = List.generate(
      5,
      (i) => ZenNavigationItem(
        id: 'id_$i',
        label: 'Item $i',
        icon: CupertinoIcons.home,
        builder: (c) => Text('Content $i'),
      ),
    );

    final prodService = ZenLocalizationService(
      config: const ZenLocalizationConfig(),
    );

    await tester.pumpWidget(CupertinoApp(
      home: Builder(
          builder: (ctx) => buildMobileNavigation(
                context: ctx,
                selectedIndex: 4,
                onItemSelected: (_) {},
                items: items,
                localization: prodService,
                language: 'en',
                // labelMore omitted to exercise NavigationMessages.more
              )),
    ));

    await tester.pumpAndSettle();

    expect(find.text('navigation.more'), findsWidgets);
  });

  testWidgets(
      'mobile navigation (Cupertino) shows tab bar and handles overflow',
      (WidgetTester tester) async {
    if (!zenIsIOS) return;

    // Create more items than zenMaxItemsMobile to cause overflow
    final items = List.generate(
      5,
      (i) => ZenNavigationItem(
        id: 'id_$i',
        label: 'Item $i',
        icon: CupertinoIcons.home,
        builder: (c) => Text('Content $i'),
      ),
    );

    var selectedCalled = -1;

    await tester.pumpWidget(CupertinoApp(
      home: Builder(
          builder: (ctx) => buildMobileNavigation(
                context: ctx,
                selectedIndex: 4,
                onItemSelected: (i) => selectedCalled = i,
                items: items,
                localization: service,
                language: 'en',
                labelMore: 'More',
              )),
    ));

    await tester.pumpAndSettle();

    // Should render a CupertinoTabBar
    expect(find.byType(CupertinoTabBar), findsOneWidget);

    // Selected overflow body shown
    expect(find.text('Content 4'), findsOneWidget);

    // Open More page
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();

    // Overflow page should show and selecting item triggers callback
    expect(find.text('Item 4'), findsOneWidget);
    await tester.tap(find.text('Item 4'));
    await tester.pumpAndSettle();

    expect(selectedCalled, 4);
  });
}
