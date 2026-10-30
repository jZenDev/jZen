import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_demo_client/src/l10n/generated/demo_localizations.dart';
import 'package:zen_demo_client/src/screens/showcase_screen.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  Future<void> show(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          ...DemoLocalizations.localizationsDelegates,
          zenWidgetsLocaleDelegate,
        ],
        supportedLocales: DemoLocalizations.supportedLocales,
        home: const ShowcaseScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('switch changes and disabled switch stays disabled', (tester) async {
    await show(tester, const Locale('en'));
    expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow).first).value, isFalse);
    await tester.tap(find.text('Notifications'));
    await tester.pump();
    expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow).first).value, isTrue);
    expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow).last).onChanged, isNull);
    expect(find.byType(ZenSegmentedControl<int>), findsOneWidget);
  });

  testWidgets('switch is localized in Ukrainian', (tester) async {
    await show(tester, const Locale('uk'));
    expect(find.text('Сповіщення'), findsOneWidget);
    await tester.tap(find.text('Сповіщення'));
    await tester.pump();
    expect(tester.widget<ZenSwitchRow>(find.byType(ZenSwitchRow).first).value, isTrue);
  });
}
