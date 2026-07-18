// Ported from
// ../DartZen/packages/dartzen_localization/test/zen_localization_cache_test.dart.
import 'package:test/test.dart';
import 'package:zen_localization/src/zen_localization_cache.dart';

void main() {
  group('ZenLocalizationCache', () {
    late ZenLocalizationCache cache;
    setUp(() => cache = ZenLocalizationCache());

    test('set and get global', () {
      cache.setGlobal('en', {'foo': 'bar'});
      expect(cache.hasGlobal('en'), isTrue);
      expect(cache.getGlobal('en'), {'foo': 'bar'});
      expect(cache.getGlobal('uk'), isEmpty);
    });

    test('set and get module', () {
      cache.setModule('auth', 'en', {'login': 'Login'});
      expect(cache.hasModule('auth', 'en'), isTrue);
      expect(cache.getModule('auth', 'en'), {'login': 'Login'});
      expect(cache.getModule('auth', 'uk'), isEmpty);
      expect(cache.hasModule('auth', 'uk'), isFalse);
      expect(cache.getModule('profile', 'en'), isEmpty);
    });

    test('clear removes all data', () {
      cache.setGlobal('en', {'foo': 'bar'});
      cache.setModule('auth', 'en', {'login': 'Login'});
      cache.clear();
      expect(cache.hasGlobal('en'), isFalse);
      expect(cache.hasModule('auth', 'en'), isFalse);
      expect(cache.getGlobal('en'), isEmpty);
      expect(cache.getModule('auth', 'en'), isEmpty);
    });
  });
}
