import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_demo_client/src/providers.dart';
import 'package:zen_demo_client/src/screens/demo_language_menu.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  testWidgets('the language menu offers each locale under its own name and switches the locale', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: [zenWidgetsLocaleDelegate],
          home: Scaffold(body: DemoLanguageMenu(label: 'Language')),
        ),
      ),
    );

    await tester.tap(find.byType(ZenIconButton));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Українська'), findsOneWidget);

    await tester.tap(find.text('Українська'));
    await tester.pumpAndSettle();
    expect(container.read(localeProvider), const Locale(ZenLocales.uk));
    expect(find.text('English'), findsNothing, reason: 'the menu closed');

    // The locale in use is the marked one.
    await tester.tap(find.byType(ZenIconButton));
    await tester.pumpAndSettle();
    final actions = tester.widget<ZenActionMenu>(find.byType(ZenActionMenu)).actions;
    expect(actions.map((a) => (a.label, a.selected)), [('English', false), ('Українська', true)]);
  });
}
