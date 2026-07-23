import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

void main() {
  group('ZenLocales', () {
    test('declares the set the server declares', () {
      // Mirrors zen.core.i18n.ZenLocales.SUPPORTED / FALLBACK. If the server's set changes,
      // this is the client assertion that must change with it.
      expect(ZenLocales.supported, [ZenLocales.en, ZenLocales.uk]);
      expect(ZenLocales.fallback, ZenLocales.en);
    });

    test('resolve matches on the primary subtag only', () {
      expect(ZenLocales.resolve('uk'), ZenLocales.uk);
      expect(ZenLocales.resolve('uk-UA'), ZenLocales.uk);
      expect(ZenLocales.resolve('uk_UA'), ZenLocales.uk);
      expect(ZenLocales.resolve('UK'), ZenLocales.uk);
      expect(ZenLocales.resolve('en-GB'), ZenLocales.en);
    });

    test('resolve falls back for absent, blank, and unsupported tags', () {
      expect(ZenLocales.resolve(null), ZenLocales.fallback);
      expect(ZenLocales.resolve(''), ZenLocales.fallback);
      expect(ZenLocales.resolve('   '), ZenLocales.fallback);
      expect(ZenLocales.resolve('de'), ZenLocales.fallback);
      expect(ZenLocales.resolve('ukrainian'), ZenLocales.fallback);
    });
  });
}
