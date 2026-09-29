import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

void main() {
  test('ships exactly the locales ZenLocales declares', () {
    expect(
      ZenWidgetsLocalizations.supportedLocales.map((Locale l) => l.languageCode),
      ZenLocales.shipped,
    );
  });

  test('resolves every string per locale', () async {
    final ZenWidgetsLocalizations en = await ZenWidgetsLocalizations.delegate.load(
      const Locale(ZenLocales.en),
    );
    final ZenWidgetsLocalizations uk = await ZenWidgetsLocalizations.delegate.load(
      const Locale(ZenLocales.uk),
    );

    expect(en.invalidAmount, 'Enter a valid amount');
    expect(uk.invalidAmount, 'Введіть коректну суму');
    expect(en.invalidAmountRange, isNot(uk.invalidAmountRange));
    expect(en.invalidDateRange, isNot(uk.invalidDateRange));
    expect(en.selectDate, 'Select a date');
    expect(uk.selectDate, 'Оберіть дату');
    expect(en.clearDate, 'Clear date');
    expect(uk.clearDate, 'Очистити дату');
    expect(en.done, 'Done');
    expect(uk.done, 'Готово');
  });

  // ADR-044: an application's locale set may be wider than what this package ships. The
  // generated delegate declines an unshipped locale; the degrading one falls back to English.
  test('the degrading delegate accepts an unshipped locale and loads the fallback', () async {
    expect(zenWidgetsLocaleDelegate.isSupported(const Locale('pl')), isTrue);
    expect(ZenWidgetsLocalizations.delegate.isSupported(const Locale('pl')), isFalse);

    final ZenWidgetsLocalizations pl = await zenWidgetsLocaleDelegate.load(const Locale('pl'));
    expect(pl.done, 'Done');

    final ZenWidgetsLocalizations uk = await zenWidgetsLocaleDelegate.load(
      const Locale('uk', 'UA'),
    );
    expect(uk.done, 'Готово');
  });
}
