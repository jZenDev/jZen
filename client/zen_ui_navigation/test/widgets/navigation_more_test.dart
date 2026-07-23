import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_more.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

void main() {
  testWidgets(
      'NavigationMorePage material branch shows selection and calls callback',
      (WidgetTester tester) async {
    // Material branch is not built on iOS; skip when running with zenIsIOS.
    if (zenIsIOS) return;
    final overflow = [
      ZenNavigationItem(
          id: 'a',
          label: 'A',
          icon: Icons.home,
          builder: (c) => const SizedBox.shrink()),
      ZenNavigationItem(
          id: 'b',
          label: 'B',
          icon: Icons.search,
          builder: (c) => const SizedBox.shrink()),
      ZenNavigationItem(
          id: 'c',
          label: 'C',
          icon: Icons.settings,
          builder: (c) => const SizedBox.shrink()),
    ];

    var selectedCalled = -1;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: overflow,
        selectedIndex: 5, // corresponds to overflow index 1 when indexOffset=4
        indexOffset: 4,
        onItemSelected: (i) => selectedCalled = i,
        labelMore: 'More',
      ),
    ));

    // AppBar title
    expect(find.text('More'), findsOneWidget);

    // Overflow item 'B' should be present and marked selected (trailing check icon)
    expect(find.text('B'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Verify selected title style is bold and has a non-null color.
    final Text titleB = tester.widget(find.text('B'));
    expect(titleB.style?.fontWeight, FontWeight.bold);
    expect(titleB.style?.color, isNotNull);

    // Verify the leading icon for B has the selected color set (non-null).
    final ListTile tileB = tester.widget(find.widgetWithText(ListTile, 'B'));
    final Icon? leadingIcon = tileB.leading as Icon?;
    expect(leadingIcon, isNotNull);
    expect(leadingIcon!.color, isNotNull);

    // Tap item B and verify callback receives global index 5
    await tester.tap(find.text('B'));
    await tester.pump();
    expect(selectedCalled, 5);
  });

  testWidgets('NavigationMorePage cupertino simple added test',
      (WidgetTester tester) async {
    if (!zenIsIOS) return;

    final items = List<ZenNavigationItem>.generate(
      2,
      (i) => ZenNavigationItem(
        id: 'id_cupertino_$i',
        label: 'CItem $i',
        builder: (c) => Text('cpage_$i'),
      ),
    );

    var selected = -1;

    await tester.pumpWidget(CupertinoApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: items,
        selectedIndex: 0,
        indexOffset: 0,
        onItemSelected: (int idx) => selected = idx,
        labelMore: 'More',
      ),
    ));

    // Verify cupertino labels present
    expect(find.text('CItem 0'), findsOneWidget);

    // Tap the second item and ensure callback receives correct global index
    await tester.tap(find.text('CItem 1'));
    await tester.pumpAndSettle();
    expect(selected, equals(1));
  });

  testWidgets('NavigationMorePage Cupertino shows checkmark and calls callback',
      (WidgetTester tester) async {
    // This test targets the Cupertino branch compiled for iOS.
    if (!zenIsIOS) return;

    var selected = -1;

    final items = <ZenNavigationItem>[
      ZenNavigationItem(
        id: 'a',
        label: 'A',
        icon: CupertinoIcons.home,
        builder: (context) => const SizedBox.shrink(),
      ),
      ZenNavigationItem(
        id: 'b',
        label: 'B',
        icon: CupertinoIcons.settings,
        builder: (context) => const SizedBox.shrink(),
      ),
    ];

    const indexOffset = 10;
    const selectedIndex = indexOffset + 1; // second item selected

    await tester.pumpWidget(CupertinoApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: items,
        selectedIndex: selectedIndex,
        indexOffset: indexOffset,
        onItemSelected: (i) => selected = i,
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('More'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);

    // The selected (second) item should show the Cupertino checkmark.
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsOneWidget);

    // Verify leading icon color for selected item is activeBlue.
    final cupertinoTileB =
        tester.widget(find.widgetWithText(CupertinoListTile, 'B'));
    // CupertinoListTile.leading is an Icon when used in this widget.
    final Icon cupertinoLeading = (cupertinoTileB as dynamic).leading as Icon;
    expect(cupertinoLeading.color, CupertinoColors.activeBlue);

    // Tap the first item and verify the callback receives the global index.
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();

    expect(selected, indexOffset + 0);
  });

  testWidgets(
      'NavigationMorePage material branch unselected items show no check and normal style',
      (WidgetTester tester) async {
    if (zenIsIOS) return;

    final overflow = [
      ZenNavigationItem(
          id: 'a',
          label: 'A',
          icon: Icons.home,
          builder: (c) => const SizedBox.shrink()),
      ZenNavigationItem(
          id: 'b',
          label: 'B',
          icon: Icons.search,
          builder: (c) => const SizedBox.shrink()),
    ];

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: overflow,
        selectedIndex: -1, // no selection
        indexOffset: 0,
        onItemSelected: (_) {},
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    // No check icons should be present
    expect(find.byIcon(Icons.check), findsNothing);

    // Titles should have normal fontWeight
    final Text titleA = tester.widget(find.text('A'));
    expect(titleA.style?.fontWeight, FontWeight.normal);
  });

  testWidgets(
      'NavigationMorePage cupertino branch unselected items use label color and no trailing',
      (WidgetTester tester) async {
    if (!zenIsIOS) return;

    final items = <ZenNavigationItem>[
      ZenNavigationItem(
          id: 'a',
          label: 'A',
          icon: CupertinoIcons.home,
          builder: (c) => const SizedBox.shrink()),
    ];

    await tester.pumpWidget(CupertinoApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: items,
        selectedIndex: -1,
        indexOffset: 0,
        onItemSelected: (_) {},
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    // No checkmark should be present
    expect(find.byIcon(CupertinoIcons.checkmark_alt), findsNothing);

    // Leading icon should use CupertinoColors.label
    final cupertinoTileA =
        tester.widget(find.widgetWithText(CupertinoListTile, 'A'));
    final Icon cupertinoLeading = (cupertinoTileA as dynamic).leading as Icon;
    expect(cupertinoLeading.color, CupertinoColors.label);
  });

  testWidgets(
      'NavigationMorePage material respects Theme primaryColor for selected visuals',
      (WidgetTester tester) async {
    if (zenIsIOS) return;

    final overflow = [
      ZenNavigationItem(
          id: 'a',
          label: 'A',
          icon: Icons.home,
          builder: (c) => const SizedBox.shrink()),
    ];

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      theme: ThemeData(primaryColor: Colors.green),
      home: NavigationMorePage(
        overflowItems: overflow,
        selectedIndex: 0,
        indexOffset: 0,
        onItemSelected: (_) {},
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    // Leading icon color should be the theme primaryColor
    final ListTile tileA = tester.widget(find.widgetWithText(ListTile, 'A'));
    final Icon leading = tileA.leading as Icon;
    expect(leading.color, Colors.green);

    // Trailing check icon should be present and colored with primaryColor
    final Icon check = tester.widget(find.byIcon(Icons.check));
    expect(check.color, Colors.green);
  });

  testWidgets(
      'NavigationMorePage material calls callback for each overflow item',
      (WidgetTester tester) async {
    if (zenIsIOS) return;

    final overflow = List.generate(
      3,
      (i) => ZenNavigationItem(
          id: 'id_$i',
          label: 'Item $i',
          icon: Icons.home,
          builder: (c) => const SizedBox.shrink()),
    );

    final called = <int>[];

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: overflow,
        selectedIndex: -1,
        indexOffset: 10,
        onItemSelected: called.add,
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    // Tap each item and verify callback receives global index
    for (var i = 0; i < overflow.length; i++) {
      await tester.tap(find.text('Item $i'));
      await tester.pump();
      expect(called.last, 10 + i);
    }
  });

  testWidgets('NavigationMorePage material empty overflow shows title only',
      (WidgetTester tester) async {
    if (zenIsIOS) return;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: const [],
        selectedIndex: -1,
        indexOffset: 0,
        onItemSelected: (_) {},
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('More'), findsOneWidget);
    // No list items should be present
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('NavigationMorePage cupertino empty overflow shows title only',
      (WidgetTester tester) async {
    if (!zenIsIOS) return;

    await tester.pumpWidget(CupertinoApp(
      localizationsDelegates: NavigationLocalizations.localizationsDelegates,
      supportedLocales: NavigationLocalizations.supportedLocales,
      home: NavigationMorePage(
        overflowItems: const [],
        selectedIndex: -1,
        indexOffset: 0,
        onItemSelected: (_) {},
        labelMore: 'More',
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('More'), findsOneWidget);
    expect(find.byType(CupertinoListTile), findsNothing);
  });
}
