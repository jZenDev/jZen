import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_rail.dart';
import 'package:zen_ui_navigation/src/widgets/navigation_sidebar.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../support/a11y.dart';

/// A page pushed from a destination stays in the content area (ADR-063). The shells are built
/// directly: the public one chooses its layout on a compile-time constant, so a run on one
/// platform would never reach the other's. The sidebar is the Apple branch, the rail the
/// non-Apple one.
final Map<String, PlatformNavigationBuilder> shells = <String, PlatformNavigationBuilder>{
  'sidebar (macOS)': buildSidebarNavigation,
  'rail (Windows, Linux)': buildRailNavigation,
};

List<ZenNavigationItem> items({required WidgetBuilder home}) => <ZenNavigationItem>[
  ZenNavigationItem(id: 'a', label: 'Item 0', builder: home),
  ZenNavigationItem(id: 'b', label: 'Item 1', builder: (_) => const Text('Other destination')),
];

Widget shell(PlatformNavigationBuilder build, BuildContext context, List<ZenNavigationItem> its) =>
    build(context: context, selectedIndex: 0, onItemSelected: (_) {}, items: its);

class _Home extends StatelessWidget {
  const _Home({required this.rootNavigator});

  final bool rootNavigator;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => Navigator.of(context, rootNavigator: rootNavigator).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(appBar: AppBar(), body: const Text('Pushed page')),
      ),
    ),
    child: const Text('Open'),
  );
}

void main() {
  for (final MapEntry<String, PlatformNavigationBuilder> entry in shells.entries) {
    group(entry.key, () {
      testWidgets('a pushed page fills the content area and leaves the menu in place', (
        tester,
      ) async {
        await pumpNavigation(
          tester,
          (context) =>
              shell(entry.value, context, items(home: (_) => const _Home(rootNavigator: false))),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Pushed page'), findsOneWidget);
        expect(find.text('Item 0'), findsOneWidget, reason: 'the menu is still shown');
        expect(find.text('Item 1'), findsOneWidget);
        final Rect page = tester.getRect(find.text('Pushed page'));
        final Rect menu = tester.getRect(find.text('Item 1'));
        expect(page.left, greaterThan(menu.right), reason: 'the page is beside the menu');
      });

      testWidgets('back returns to the destination', (tester) async {
        await pumpNavigation(
          tester,
          (context) =>
              shell(entry.value, context, items(home: (_) => const _Home(rootNavigator: false))),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.text('Pushed page'), findsNothing);
        expect(find.text('Open'), findsOneWidget);
        expect(find.text('Item 1'), findsOneWidget);
      });

      testWidgets('the root navigator still covers the menu, for a full-screen flow', (
        tester,
      ) async {
        await pumpNavigation(
          tester,
          (context) =>
              shell(entry.value, context, items(home: (_) => const _Home(rootNavigator: true))),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Pushed page'), findsOneWidget);
        expect(find.text('Item 1').hitTestable(), findsNothing);
      });

      testWidgets('a detail too narrow for a pane is pushed inside the content area', (
        tester,
      ) async {
        await pumpNavigation(
          tester,
          size: const Size(820, 800),
          (context) => shell(
            entry.value,
            context,
            items(
              home: (_) => ZenDetailHost(
                child: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showZenDetail<void>(
                      context,
                      builder: (_) => const Scaffold(body: Text('Detail page')),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Detail page'), findsOneWidget);
        expect(find.text('Item 1').hitTestable(), findsOneWidget, reason: 'the menu is reachable');
      });

      testWidgets('Tab reaches the menu before a page that has controls of its own', (
        tester,
      ) async {
        await pumpNavigation(
          tester,
          (context) =>
              shell(entry.value, context, items(home: (_) => const _Home(rootNavigator: false))),
        );
        await press(tester, LogicalKeyboardKey.tab);
        expect(ringed(tester), <int>[0], reason: 'the first stop is the menu');
        await press(tester, LogicalKeyboardKey.tab);
        await press(tester, LogicalKeyboardKey.tab);
        expect(
          Focus.of(tester.element(find.text('Open'))).hasFocus,
          isTrue,
          reason: 'then the page',
        );
      });

      testWidgets('choosing another destination discards the stack of the one left', (
        tester,
      ) async {
        int selected = 0;
        await pumpNavigation(
          tester,
          (context) => StatefulBuilder(
            builder: (context, setState) => entry.value(
              context: context,
              selectedIndex: selected,
              onItemSelected: (int i) => setState(() => selected = i),
              items: items(home: (_) => const _Home(rootNavigator: false)),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Item 1'));
        await tester.pumpAndSettle();
        expect(find.text('Other destination'), findsOneWidget);
        await tester.tap(find.text('Item 0'));
        await tester.pumpAndSettle();

        expect(find.text('Pushed page'), findsNothing);
        expect(find.text('Open'), findsOneWidget);
      });

      testWidgets('each destination has its own navigator', (tester) async {
        await pumpNavigation(
          tester,
          (context) =>
              shell(entry.value, context, items(home: (_) => const _Home(rootNavigator: false))),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // The content area's navigator is the one under the shell, not the application's.
        final NavigatorState content = tester.state(find.byType(Navigator).last);
        expect(content.canPop(), isTrue);
        expect(
          Navigator.of(tester.element(find.text('Pushed page')), rootNavigator: true),
          isNot(same(content)),
        );
      });
    });
  }
}
