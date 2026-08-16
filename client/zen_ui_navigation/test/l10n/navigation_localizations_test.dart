import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_navigation/zen_ui_navigation.dart';

/// The typed replacement for the retired string-key lookups (ROADMAP step 7b, ADR-009).
/// A missing key is now a compile error rather than a runtime miss, so what is left to assert
/// is the part the compiler cannot see: that this package ships exactly the locales the
/// framework declares, and that each one resolves to its own wording.
void main() {
  test('ships exactly the locales ZenLocales declares', () {
    expect(NavigationLocalizations.supportedLocales.map((l) => l.languageCode), ZenLocales.shipped);
  });

  test('resolves the overflow label per locale', () async {
    final en = await NavigationLocalizations.delegate.load(const Locale(ZenLocales.en));
    final uk = await NavigationLocalizations.delegate.load(const Locale(ZenLocales.uk));

    expect(en.more, 'More');
    expect(uk.more, 'Ще');
  });

  // ADR-044: an application's locale set may be wider than what this package ships. The
  // generated delegate declines an unshipped locale, which leaves nothing to resolve
  // NavigationLocalizations from and throws on first read; the degrading delegate falls back.
  test('the degrading delegate accepts an unshipped locale and loads the fallback', () async {
    expect(navigationLocaleDelegate.isSupported(const Locale('pl')), isTrue);
    expect(NavigationLocalizations.delegate.isSupported(const Locale('pl')), isFalse);

    final pl = await navigationLocaleDelegate.load(const Locale('pl'));
    expect(pl.more, 'More');

    // Exact where it can be: a shipped tag never degrades.
    final uk = await navigationLocaleDelegate.load(const Locale('uk', 'UA'));
    expect(uk.more, 'Ще');
  });
}
