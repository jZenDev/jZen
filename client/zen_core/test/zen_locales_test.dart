import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('ZenLocales', () {
    test('declares the set the server declares', () {
      // Mirrors zen.core.i18n.ZenLocales.SHIPPED / FALLBACK. If the server's set changes,
      // this is the client assertion that must change with it.
      expect(ZenLocales.shipped, [ZenLocales.en, ZenLocales.uk]);
      expect(ZenLocales.fallback, ZenLocales.en);
    });

    test('resolve matches on the primary subtag only', () {
      expect(ZenLocales.resolve('uk'), ZenLocales.uk);
      expect(ZenLocales.resolve('uk-UA'), ZenLocales.uk);
      expect(ZenLocales.resolve('uk_UA'), ZenLocales.uk);
      expect(ZenLocales.resolve('UK'), ZenLocales.uk);
      expect(ZenLocales.resolve('en-GB'), ZenLocales.en);
    });

    test('resolve falls back for absent, blank, and unshipped tags', () {
      expect(ZenLocales.resolve(null), ZenLocales.fallback);
      expect(ZenLocales.resolve(''), ZenLocales.fallback);
      expect(ZenLocales.resolve('   '), ZenLocales.fallback);
      expect(ZenLocales.resolve('de'), ZenLocales.fallback);
      expect(ZenLocales.resolve('ukrainian'), ZenLocales.fallback);
    });

    // ADR-044: `shipped` is jZen's inventory, not a policy on what an application supports.
    // An app resolving against its own set keeps a locale jZen ships no strings for.
    test('resolve honours an application set that jZen does not ship', () {
      const appLocales = [ZenLocales.en, ZenLocales.uk, 'pl'];
      expect(ZenLocales.resolve('pl', against: appLocales), 'pl');
      expect(ZenLocales.resolve('pl-PL', against: appLocales), 'pl');
      expect(ZenLocales.resolve('uk', against: appLocales), ZenLocales.uk);
      // Still a closed set: a tag the *application* does not support falls back.
      expect(ZenLocales.resolve('de', against: appLocales), ZenLocales.fallback);
      // And the framework default is unchanged for callers that mean "what jZen ships".
      expect(ZenLocales.resolve('pl'), ZenLocales.fallback);
    });
  });
}
