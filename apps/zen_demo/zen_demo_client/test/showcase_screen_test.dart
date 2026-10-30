import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_demo_client/src/l10n/generated/demo_localizations.dart';
import 'package:zen_demo_client/src/screens/showcase_screen.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  /// The page ends in a spinner that never stops, so `pumpAndSettle` would time out: this lets
  /// menus and sections finish animating, which is all a test here needs.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> show(WidgetTester tester, Locale locale) async {
    // Tall, so the whole list is built and every section can be reached without scrolling.
    tester.view.physicalSize = const Size(800, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    await settle(tester);
  }

  const en = Locale('en');

  /// The icon button inside [widget] - found by structure, not by tooltip, which only the
  /// Material idiom has.
  Finder buttonIn(Type widget) =>
      find.descendant(of: find.byType(widget), matching: find.byType(ZenIconButton));

  testWidgets('switch changes and disabled switch stays disabled', (tester) async {
    await show(tester, en);
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

  testWidgets('the parent checkbox is mixed while only one channel is on, and sets both', (
    tester,
  ) async {
    await show(tester, en);
    ZenCheckboxRow row(String label) => tester.widget(
      find.ancestor(of: find.text(label), matching: find.byType(ZenCheckboxRow)).first,
    );
    expect(row('All channels').value, isNull, reason: 'email on, SMS off: mixed');

    await tester.tap(find.text('SMS updates'));
    await tester.pump();
    expect(row('All channels').value, isTrue);

    await tester.tap(find.text('All channels'));
    await tester.pump();
    expect(row('Email updates').value, isFalse);
    expect(row('SMS updates').value, isFalse);
    expect(row('All channels').value, isFalse);

    expect(row('Unavailable setting').onChanged, isNull);
  });

  testWidgets('the radio group starts with nothing chosen and skips the disabled option', (
    tester,
  ) async {
    await show(tester, en);
    ZenRadioGroup group() => tester.widget(find.byWidgetPredicate((w) => w is ZenRadioGroup));
    expect(group().value, isNull);

    await tester.tap(find.text('Quarterly'));
    await tester.pump();
    expect(group().value, isNull, reason: 'the disabled option cannot be chosen');

    await tester.tap(find.text('Yearly'));
    await tester.pump();
    expect(group().value, isNotNull);
  });

  testWidgets('filters toggle independently and the disabled one does not', (tester) async {
    await show(tester, en);
    ZenFilterChip chip(String label) => tester.widget(
      find.ancestor(of: find.text(label), matching: find.byType(ZenFilterChip)).first,
    );
    expect(chip('Groceries').selected, isTrue);
    await tester.tap(find.text('Travel'));
    await tester.pump();
    expect(chip('Travel').selected, isTrue);
    expect(chip('Groceries').selected, isTrue, reason: 'independent of its neighbours');
    expect(chip('Archived').onSelected, isNull);
  });

  testWidgets('sliders show their app-formatted values and the disabled ones cannot move', (
    tester,
  ) async {
    await show(tester, en);
    expect(find.text('40 dB'), findsOneWidget);
    expect(find.text('3 of 5'), findsOneWidget);
    expect(find.text('€100 – €300'), findsOneWidget);
    final disabled = tester.widgetList<ZenSlider>(find.byType(ZenSlider)).last;
    expect(disabled.onChanged, isNull);
    final ranges = tester.widgetList<ZenRangeSlider>(find.byType(ZenRangeSlider));
    expect(ranges.last.onChanged, isNull);
  });

  testWidgets('searching filters the list, shows the empty result, and clearing restores it', (
    tester,
  ) async {
    await show(tester, en);
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Retirement'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).at(0), 'fund');
    await tester.pump();
    expect(find.text('Travel fund'), findsOneWidget);
    expect(find.text('Emergency fund'), findsOneWidget);
    expect(find.text('Savings'), findsNothing);

    await tester.enterText(find.byType(EditableText).at(0), 'zzz');
    await tester.pump();
    expect(find.text('No accounts match “zzz”'), findsOneWidget);

    await tester.tap(buttonIn(ZenSearchField));
    await tester.pump();
    expect(find.text('Savings'), findsOneWidget);
    expect(find.text('Retirement'), findsOneWidget);
    expect(find.textContaining('No accounts match'), findsNothing);
  });

  testWidgets('the action menu runs an enabled action and never the disabled one', (tester) async {
    await show(tester, en);
    expect(find.text('Nothing chosen yet'), findsOneWidget);

    await tester.tap(buttonIn(ZenActionMenu));
    await settle(tester);
    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(find.text('Nothing chosen yet'), findsOneWidget, reason: 'disabled: not fired');

    await tester.tap(find.text('Rename'));
    await settle(tester);
    expect(find.text('Chosen: Rename'), findsOneWidget);
  });

  testWidgets('sections open and close, keep or drop their content, and the locked one is inert', (
    tester,
  ) async {
    await show(tester, en);
    const body = 'These settings apply to every account. Change them only if you know why.';
    expect(find.text(body), findsNothing);

    await tester.tap(find.text('Advanced options'));
    await settle(tester);
    expect(find.text(body), findsOneWidget);
    await tester.tap(find.text('Advanced options'));
    await settle(tester);
    expect(find.text(body), findsNothing);

    await tester.tap(find.text('Locked section'));
    await settle(tester);
    expect(find.text(body), findsNothing);

    // The reference code survives closing the section it is in.
    await tester.tap(find.text('Reference code').first);
    await settle(tester);
    final reference = find.descendant(
      of: find.byType(ZenExpandableSection).at(1),
      matching: find.byType(EditableText),
    );
    await tester.enterText(reference, 'ABC-1');
    await tester.tap(find.text('Reference code').first);
    await settle(tester);
    expect(find.text('ABC-1'), findsNothing);
    await tester.tap(find.text('Reference code').first);
    await settle(tester);
    expect(find.text('ABC-1'), findsOneWidget);
  });

  testWidgets('the new sections are localized in Ukrainian', (tester) async {
    await show(tester, const Locale('uk'));
    expect(find.text('Канали сповіщень'), findsNothing); // a label, not a heading
    expect(find.text('Усі канали'), findsOneWidget);
    expect(find.text('Щомісяця'), findsOneWidget);
    expect(find.text('Продукти'), findsOneWidget);
    expect(find.text('40 дБ'), findsOneWidget);
    expect(find.text('100 € – 300 €'), findsOneWidget);
    expect(find.text('Ще нічого не обрано'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).at(0), 'xyz');
    await tester.pump();
    expect(find.text('Жоден рахунок не збігається з «xyz»'), findsOneWidget);
    expect(buttonIn(ZenSearchField), findsOneWidget);
  });
}
