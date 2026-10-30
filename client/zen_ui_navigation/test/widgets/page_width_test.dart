import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  testWidgets('shell width reaches pushed pages and leaves the detail host wide', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: ZenNavigation(
          selectedIndex: 0,
          onItemSelected: (_) {},
          contentMaxWidth: 300,
          contentGutter: 20,
          items: [
            ZenNavigationItem(
              id: 'home',
              label: 'Home',
              builder: (_) => ZenDetailHost(
                child: Builder(
                  builder: (context) => ZenPageScaffold(
                    title: 'Home page',
                    body: SizedBox(
                      key: const ValueKey('home body'),
                      child: TextButton(
                        onPressed: () => showZenDetail<void>(
                          context,
                          builder: (_) => const ZenPageScaffold(
                            title: 'Detail',
                            body: SizedBox(key: ValueKey('detail body')),
                          ),
                        ),
                        child: const Text('Open detail'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('home body'))).width, 300);
    expect(tester.getSize(find.byType(ZenDetailHost)).width, greaterThanOrEqualTo(720));
    await tester.tap(find.text('Open detail'));
    await tester.pumpAndSettle();
    expect(find.text('Home page'), findsOneWidget);
    expect(find.text('Detail'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('detail body'))).width, 300);
  });

  testWidgets('shell default applies to pages pushed in the destination navigator', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: NavigationLocalizations.localizationsDelegates,
        supportedLocales: NavigationLocalizations.supportedLocales,
        home: ZenNavigation(
          selectedIndex: 0,
          onItemSelected: (_) {},
          contentMaxWidth: 400,
          items: [
            ZenNavigationItem(
              id: 'home',
              label: 'Home',
              builder: (context) => ZenPageScaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ZenPageScaffold(
                        contentMaxWidth: 600,
                        body: SizedBox(key: ValueKey('pushed')),
                      ),
                    ),
                  ),
                  child: const Text('Push'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('pushed'))).width, 600);
  });
}
