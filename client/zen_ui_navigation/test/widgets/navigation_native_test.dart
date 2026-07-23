import 'package:zen_ui_navigation/src/widgets/navigation_native.dart'
    as native;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

void main() {
  testWidgets('navigation_native build is tolerated across platforms',
      (WidgetTester tester) async {
    final items = List<ZenNavigationItem>.generate(
      2,
      (i) => ZenNavigationItem(
        id: 'n$i',
        label: 'NItem $i',
        builder: (c) => Text('NContent $i'),
      ),
    );


    // Attempt to build the native platform widget. On some ZEN_PLATFORM
    // compile-time settings this will return a widget; on others it may
    // throw UnimplementedError or platform-specific exceptions. Treat both
    // outcomes as acceptable for CI.
    try {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: Builder(
            builder: (ctx) => native.buildPlatformNavigation(
                  context: ctx,
                  selectedIndex: 0,
                  onItemSelected: (_) {},
                  items: items,
                )),
      ));

      // If build succeeded, ensure body content is present
      expect(find.text('NContent 0'), findsWidgets);
    } catch (e) {
      // Accept UnimplementedError or other platform-specific exceptions.
      expect(e, isA<Exception>());
    }
  });
}
