import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

class _FailingStore implements ZenLocaleStore {
  @override
  String? read() => null;

  @override
  Future<void> write(String tag) async => throw StateError('disk full');
}

void main() {
  const supported = ['en', 'uk', 'pl'];

  ZenLocalePreference prefs([String? stored]) =>
      ZenLocalePreference(supported: supported, store: ZenMemoryLocaleStore(stored));

  group('initial', () {
    test('a stored choice wins over the device language', () {
      expect(prefs('uk').initial(['pl-PL']), 'uk');
    });

    test('with no choice, the first supported device language is used', () {
      expect(prefs().initial(['de-DE', 'pl-PL', 'uk']), 'pl');
    });

    test('with no choice and no supported device language, it is the fallback', () {
      expect(prefs().initial(['de-DE']), ZenLocales.fallback);
      expect(prefs().initial(const []), ZenLocales.fallback);
    });

    test('a stored tag that is no longer supported falls through instead of throwing', () {
      expect(prefs('fr').initial(['uk']), 'uk');
      expect(prefs('fr').initial(['de']), ZenLocales.fallback);
      expect(prefs('').initial(const []), ZenLocales.fallback);
    });
  });

  group('choose', () {
    test('stores the primary subtag, and the next launch reads it back', () async {
      final store = ZenMemoryLocaleStore();
      final first = ZenLocalePreference(supported: supported, store: store);

      expect(await first.choose('pl-PL'), 'pl');

      final restarted = ZenLocalePreference(supported: supported, store: store);
      expect(restarted.initial(const []), 'pl');
    });

    test('refuses an unsupported language rather than storing the fallback', () async {
      final store = ZenMemoryLocaleStore('uk');
      final p = ZenLocalePreference(supported: supported, store: store);

      await expectLater(p.choose('de'), throwsArgumentError);
      expect(store.read(), 'uk');
    });

    test('a failed write is not swallowed', () async {
      final p = ZenLocalePreference(supported: supported, store: _FailingStore());
      await expectLater(p.choose('uk'), throwsStateError);
    });
  });

  test('the fallback must be supported', () {
    expect(
      () => ZenLocalePreference(supported: const ['uk'], store: ZenMemoryLocaleStore()),
      throwsArgumentError,
    );
  });
}
